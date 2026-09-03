#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: block_fingerprint.py
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.09.03
# Revision...: v1.0.0
# Purpose....: Block-level ciphertext fingerprinting of Oracle datafiles, used to
#              prove whether an RMAN clone re-encrypted the data blocks (new TEK)
#              or only re-wrapped the existing TEK in the file header.
# Notes......: Runs on the host against bind-mounted datafiles under data/<svc>/.
#              No third-party dependencies. Read-only: never writes to a datafile.
#              Freeze the tablespace (READ ONLY) before taking a baseline, other-
#              wise ordinary block writes make the comparison meaningless.
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------

"""Fingerprint and compare Oracle datafiles block by block.

Interpretation guide for the compare subcommand:

- only a handful of low-numbered blocks differ  -> re-wrap: the TEK is unchanged,
  just re-encrypted under a new master key in the datafile header
- (almost) every allocated block differs        -> re-encrypt: new tablespace key,
  blocks genuinely rewritten
"""

import argparse
import hashlib
import sys
from pathlib import Path

DEFAULT_BLOCK_SIZE = 8192
FP_MAGIC = "# oradba-block-fingerprint v1"


def fingerprint(path: Path, block_size: int):
    """Yield (block_no, sha256_hex, is_zero) for every block in path."""
    zero = bytes(block_size)
    with path.open("rb") as fh:
        block_no = 0
        while True:
            chunk = fh.read(block_size)
            if not chunk:
                break
            digest = hashlib.sha256(chunk).hexdigest()
            yield block_no, digest, chunk == zero or chunk == zero[: len(chunk)]
            block_no += 1


def cmd_fingerprint(args):
    path = Path(args.datafile)
    if not path.is_file():
        sys.exit(f"error: not a file: {path}")
    size = path.stat().st_size
    if size % args.block_size:
        print(
            f"warning: size {size} is not a multiple of block size "
            f"{args.block_size}; last block is short",
            file=sys.stderr,
        )
    out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
    try:
        print(FP_MAGIC, file=out)
        print(f"# datafile: {path}", file=out)
        print(f"# bytes: {size}", file=out)
        print(f"# block_size: {args.block_size}", file=out)
        count = zeros = 0
        for block_no, digest, is_zero in fingerprint(path, args.block_size):
            print(f"{block_no}\t{digest}", file=out)
            count += 1
            zeros += 1 if is_zero else 0
        print(f"# blocks: {count}", file=out)
        print(f"# zero_blocks: {zeros}", file=out)
    finally:
        if args.out:
            out.close()
            print(f"wrote {args.out}", file=sys.stderr)


def load_fingerprint(path: Path):
    """Return (meta_dict, {block_no: digest}) from a fingerprint file."""
    meta, blocks = {}, {}
    with path.open(encoding="utf-8") as fh:
        first = fh.readline().rstrip("\n")
        if first != FP_MAGIC:
            sys.exit(f"error: {path} is not a fingerprint file ({first!r})")
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("#"):
                key, _, value = line[1:].strip().partition(":")
                meta[key.strip()] = value.strip()
                continue
            block_no, _, digest = line.partition("\t")
            blocks[int(block_no)] = digest
    return meta, blocks


def cmd_compare(args):
    meta_a, blocks_a = load_fingerprint(Path(args.fingerprint_a))
    meta_b, blocks_b = load_fingerprint(Path(args.fingerprint_b))
    label_a = args.label_a or meta_a.get("datafile", args.fingerprint_a)
    label_b = args.label_b or meta_b.get("datafile", args.fingerprint_b)

    common = sorted(set(blocks_a) & set(blocks_b))
    only_a = sorted(set(blocks_a) - set(blocks_b))
    only_b = sorted(set(blocks_b) - set(blocks_a))
    differing = [n for n in common if blocks_a[n] != blocks_b[n]]
    identical = len(common) - len(differing)

    print("== Block-level ciphertext comparison ==")
    print(f"A: {label_a}")
    print(f"B: {label_b}")
    print(f"block_size A/B: {meta_a.get('block_size')}/{meta_b.get('block_size')}")
    print(f"blocks compared: {len(common)}")
    print(f"identical: {identical}")
    print(f"differing: {len(differing)}")
    if only_a or only_b:
        print(f"blocks only in A: {len(only_a)}  only in B: {len(only_b)}")
    if differing:
        shown = differing[: args.list_limit]
        print(f"first differing blocks: {shown}")
        if len(differing) > len(shown):
            print(f"... and {len(differing) - len(shown)} more")

    if not common:
        verdict = "INCONCLUSIVE - no comparable blocks"
    elif not differing:
        verdict = "IDENTICAL - byte-for-byte equal, no re-encryption whatsoever"
    elif len(differing) <= args.rewrap_threshold:
        verdict = (
            f"RE-WRAP INDICATED - only {len(differing)} block(s) changed; "
            "data blocks byte-identical, so the tablespace key is unchanged"
        )
    elif identical == 0:
        verdict = "RE-ENCRYPT INDICATED - every comparable block changed"
    else:
        verdict = (
            f"MIXED - {len(differing)} of {len(common)} blocks changed; "
            "inspect which ranges differ before drawing a conclusion"
        )
    print(f"verdict: {verdict}")
    return 0


def cmd_scan_plaintext(args):
    path = Path(args.datafile)
    if not path.is_file():
        sys.exit(f"error: not a file: {path}")
    needles = {
        "ascii": args.needle.encode("ascii", "ignore"),
        "utf-16-le": args.needle.encode("utf-16-le"),
    }
    hits = []
    with path.open("rb") as fh:
        block_no = 0
        while True:
            chunk = fh.read(args.block_size)
            if not chunk:
                break
            for encoding, needle in needles.items():
                if needle and needle in chunk:
                    offset = block_no * args.block_size + chunk.index(needle)
                    hits.append((block_no, offset, encoding))
            block_no += 1

    print("== Plaintext scan ==")
    print(f"datafile: {path}")
    print(f"needle: {args.needle!r}")
    if hits:
        print(f"HITS: {len(hits)} (data is readable in the clear)")
        for block_no, offset, encoding in hits[: args.list_limit]:
            print(f"  block {block_no} offset {offset} as {encoding}")
    else:
        print("no hits - needle not present as plaintext in this datafile")
    return 1 if (hits and args.expect_absent) else 0


def cmd_find_hex(args):
    """Locate a known byte sequence, e.g. the wrapped tablespace key."""
    path = Path(args.datafile)
    if not path.is_file():
        sys.exit(f"error: not a file: {path}")
    cleaned = args.hex_string.strip().replace(" ", "").replace(":", "")
    try:
        needle = bytes.fromhex(cleaned)
    except ValueError as exc:
        sys.exit(f"error: not a hex string: {exc}")
    if not needle:
        sys.exit("error: empty hex string")

    # Read with an overlap so a match spanning a block boundary is not missed.
    overlap = len(needle) - 1
    hits = []
    with path.open("rb") as fh:
        offset = 0
        carry = b""
        while True:
            chunk = fh.read(args.chunk_size)
            if not chunk:
                break
            window = carry + chunk
            start = 0
            while True:
                idx = window.find(needle, start)
                if idx < 0:
                    break
                abs_off = offset - len(carry) + idx
                hits.append(abs_off)
                start = idx + 1
            offset += len(chunk)
            carry = window[-overlap:] if overlap else b""

    print("== Hex needle search ==")
    print(f"datafile: {path}")
    print(f"needle: {cleaned.upper()} ({len(needle)} bytes)")
    if hits:
        print(f"HITS: {len(hits)}")
        for abs_off in hits[: args.list_limit]:
            block_no, in_block = divmod(abs_off, args.block_size)
            print(f"  offset {abs_off} -> block {block_no}, byte {in_block} in block")
        if len(hits) > len(hits[: args.list_limit]):
            print(f"... and {len(hits) - args.list_limit} more")
        print("verdict: the sequence is physically present in this datafile")
    else:
        print("HITS: 0")
        print("verdict: sequence not present - it is not stored verbatim here")
    return 0


def cmd_hexdump(args):
    """Hex plus printable dump of one block, for the file header analysis."""
    path = Path(args.datafile)
    if not path.is_file():
        sys.exit(f"error: not a file: {path}")
    offset = args.block * args.block_size
    size = path.stat().st_size
    if offset >= size:
        sys.exit(f"error: block {args.block} is past end of file ({size} bytes)")
    with path.open("rb") as fh:
        fh.seek(offset)
        data = fh.read(min(args.length, args.block_size))

    print("== Block hexdump ==")
    print(f"datafile: {path}")
    print(f"block: {args.block}  block_size: {args.block_size}  file offset: {offset}")
    print(f"sha256 of shown bytes: {hashlib.sha256(data).hexdigest()}")
    for i in range(0, len(data), 16):
        row = data[i : i + 16]
        hexpart = " ".join(f"{b:02x}" for b in row)
        asciipart = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"{offset + i:08x}  {hexpart:<47}  |{asciipart}|")
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    fp = sub.add_parser("fingerprint", help="hash every block of a datafile")
    fp.add_argument("datafile")
    fp.add_argument("--block-size", type=int, default=DEFAULT_BLOCK_SIZE)
    fp.add_argument("--out", help="write fingerprint to this file instead of stdout")
    fp.set_defaults(func=cmd_fingerprint)

    cmp_ = sub.add_parser("compare", help="compare two fingerprint files")
    cmp_.add_argument("fingerprint_a")
    cmp_.add_argument("fingerprint_b")
    cmp_.add_argument("--label-a")
    cmp_.add_argument("--label-b")
    cmp_.add_argument("--list-limit", type=int, default=20)
    cmp_.add_argument(
        "--rewrap-threshold",
        type=int,
        default=8,
        help="at most this many differing blocks is read as header-only re-wrap",
    )
    cmp_.set_defaults(func=cmd_compare)

    sc = sub.add_parser("scan-plaintext", help="search a datafile for a clear-text marker")
    sc.add_argument("datafile")
    sc.add_argument("needle")
    sc.add_argument("--block-size", type=int, default=DEFAULT_BLOCK_SIZE)
    sc.add_argument("--list-limit", type=int, default=20)
    sc.add_argument(
        "--expect-absent",
        action="store_true",
        help="exit non-zero if the marker IS found (use on encrypted datafiles)",
    )
    sc.set_defaults(func=cmd_scan_plaintext)

    fh = sub.add_parser(
        "find-hex",
        help="locate a known byte sequence, e.g. ENCRYPTEDKEY from V$ENCRYPTED_TABLESPACES",
    )
    fh.add_argument("datafile")
    fh.add_argument("hex_string", help="hex bytes to look for, spaces and colons allowed")
    fh.add_argument("--block-size", type=int, default=DEFAULT_BLOCK_SIZE)
    fh.add_argument("--chunk-size", type=int, default=1 << 20)
    fh.add_argument("--list-limit", type=int, default=20)
    fh.set_defaults(func=cmd_find_hex)

    hd = sub.add_parser("hexdump", help="hex dump one block, for file header analysis")
    hd.add_argument("datafile")
    hd.add_argument("--block", type=int, default=0)
    hd.add_argument("--block-size", type=int, default=DEFAULT_BLOCK_SIZE)
    hd.add_argument("--length", type=int, default=512, help="bytes to show from the block")
    hd.set_defaults(func=cmd_hexdump)

    return parser


def main():
    args = build_parser().parse_args()
    return args.func(args) or 0


if __name__ == "__main__":
    sys.exit(main())
# EOF --------------------------------------------------------------------------
