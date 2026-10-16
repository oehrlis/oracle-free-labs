# Container Runtime Runbook - Docker Desktop, Colima, Podman

How to prepare a host for the lab, check it before the first start, and pre-load
everything so the lab runs without network access (for example behind a VPN that
blocks the Oracle registry).

## Which Runtime

The Makefile and the helper scripts call the `docker` CLI and the
`docker compose` plugin. Any engine that speaks the Docker API works behind that
CLI.

<!-- markdownlint-disable MD013 MD060 -->
| Runtime | Status in this repository | Notes |
| --- | --- | --- |
| Docker Desktop (macOS arm64) | **Verified** (Docker Desktop, compose 5.6, 2026-10-16) | Reference setup |
| Colima (macOS arm64, `vz` + `virtiofs`) | **Verified** (Colima 0.10.3, Docker 29.5, compose 5.6, 2026-10-16) | Repository must be below `$HOME`, see below |
| Podman (podman machine) | **Not verified** - documented only | Use the docker CLI against the Podman socket, see below |
<!-- markdownlint-restore -->

Image facts (measured):

- `container-registry.oracle.com/database/free:latest` = Oracle AI Database 26ai
  Free 23.26.3.0.0, available for **arm64** and amd64, 13.1 GB unpacked.
  Digest on 2026-10-16: `sha256:f988b0c04c4c386cd306a2a914c0d7a9702d83acc31b064a28ad8eb6278a8fba`.
- The extended image `oracle-free-labs:<tag>` (`make build`) adds the OraDBA tools,
  `rlwrap` and the `/opt/oracle/network/admin` symlink that all named services
  need for `TNS_ADMIN`. It is about 13.2 GB.
- `.env.example` still defaults to `free:23.9.0.0` (23ai). The seclab service was
  verified on `free:latest`; set `DB_BASE_IMAGE` accordingly (see below).

## Pre-Flight Check

```bash
make check                    # runtime, resources, compose, disk
make check SERVICE=seclab     # plus .env, image, variables, ports of the service
```

`scripts/check_requirements.sh` is read-only, prints `PASS` / `WARN` / `FAIL`
per check and exits 1 on any `FAIL`. `make up-seclab` runs it automatically.
It never prints secret values, only whether they are set.

## Docker Desktop (macOS)

1. Install Docker Desktop and give the VM at least **4 CPUs and 6 GB memory**
   (Settings - Resources).
2. `docker compose version` must report the compose plugin (v2 or later).
3. Continue with [Prepare Images](#prepare-images-online-once).

## Colima (macOS, Apple Silicon)

Colima runs the Docker engine in a lightweight VM. The `docker` CLI and the
compose plugin are installed separately.

```bash
brew install colima docker docker-compose
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix)/opt/docker-compose/bin/docker-compose" ~/.docker/cli-plugins/docker-compose

colima start --cpu 4 --memory 6 --disk 60 --arch aarch64 --vm-type vz --mount-type virtiofs
docker context show           # colima
docker compose version
```

Measured on Apple Silicon with exactly these values (profile `ofl`):

| Step | Duration | Result |
| --- | --- | --- |
| `colima start` (new VM) | 40 s | vz, virtiofs, aarch64, VM reports 5.8 GiB |
| `docker pull ...free:latest` | 128 s | 13.1 GB |
| `make build` | 88 s | `oracle-free-labs:latest` |
| `make up-seclab` to end of setup | 130 s | 11 of 11 scenarios present |
| Memory of the seclab container | peak 2.5 GiB | limit 3 GiB |

Points that matter under Colima:

- **Clone the repository below `$HOME`.** Colima mounts only `$HOME` into the VM by
  default. A bind mount from another location (for example `/tmp`) silently
  becomes an empty directory inside the VM, the `TNS_ADMIN` symlink dangles and
  DBCA stops with `DBT-60127 Specified TNS_ADMIN path '/opt/oracle/network/admin'
  is not a directory`, after which the container restarts in a loop.
  `make check` detects this. Alternative: add the path to `mounts:` in
  `~/.colima/<profile>/colima.yaml` and restart Colima.
- **Use `--vm-type vz --mount-type virtiofs`.** With virtiofs the files written by
  the container user `oracle` (UID 54321) appear on the host as your user and
  stay writable for you - measured. `sshfs` mounts are slower and are reported as
  `WARN` by `make check`.
- **Memory:** 4 GB is the minimum for one database, 6 GB leaves headroom. Two
  databases at the same time need about 8 GB.
- **Architecture:** use `--arch aarch64` on Apple Silicon. The image is native
  arm64; x86 emulation is not needed and much slower.
- **Ports:** Colima forwards published ports to `127.0.0.1` of the Mac. Docker
  Desktop and Colima cannot publish the same port at the same time - stop the
  service in one engine before starting it in the other.
- **Several engines:** `colima start` switches the docker context. Switch back with
  `docker context use desktop-linux`, or address one engine per command with
  `DOCKER_CONTEXT=colima make ...`.

## Podman (Not Verified)

Podman was not available on the test host. The following is the expected setup,
not a measured one:

```bash
brew install podman docker docker-compose
podman machine init --cpus 4 --memory 6144 --disk-size 60
podman machine set --rootful          # bind mounts and UID handling like Docker
podman machine start
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
docker info && docker compose version
```

Restrictions to expect:

- **Use the docker CLI and `docker-compose` against the Podman socket.**
  `podman-compose` handles compose profiles, YAML merge keys and
  `deploy.resources.limits` differently or not at all; this repository relies on
  all three.
- **Rootless mode:** bind-mounted files are owned by a sub-UID on the host; the
  container user (UID 54321) may not be able to write `data/<service>/`.
  Rootful mode avoids this.
- `make check` reports Podman as the engine through `docker info`; the
  Colima-specific checks are skipped.
- Mount scope of `podman machine` on macOS is `$HOME` by default, like Colima.

## Prepare Images (Online, Once)

Everything the lab needs from the network is fetched in this step. Afterwards the
lab starts without registry or GitHub access.

```bash
git clone https://github.com/oehrlis/oracle-free-labs.git ~/oracle-free-labs
cd ~/oracle-free-labs
cp .env.example .env
# in .env: DB_BASE_IMAGE=container-registry.oracle.com/database/free:latest
#          and your own SECLAB_* passwords
docker pull container-registry.oracle.com/database/free:latest
make build                    # needs yum.oracle.com and github.com (OraDBA tools)
make check SERVICE=seclab
```

`make build` tags the image from the base tag (`free:latest` gives
`oracle-free-labs:latest`). `DB_IMAGE` is derived automatically.

Optional: export the images to move them to another host:

```bash
docker save oracle-free-labs:latest | gzip > oracle-free-labs-latest.tar.gz
docker load < oracle-free-labs-latest.tar.gz
```

## Offline / After a VPN Switch

- `make up-<service>` uses only local images and the files of the repository.
- `make build` needs the network again (base image layers are cached, but the
  `dnf` and OraDBA download layers are not if the cache was pruned).
- `scripts/apply_usecase.sh` needs no network at all.

## Plain Oracle Container Instead of the Lab Services

Use cases such as `seclab` can be applied to any running Oracle Database Free
container, without `make build` and without this repository's compose file:

```bash
docker run -d --name free26ai -p 127.0.0.1:1521:1521 \
  -e ORACLE_PWD=<password> container-registry.oracle.com/database/free:latest
scripts/apply_usecase.sh seclab free26ai          # or: make apply USECASE=seclab CONTAINER=free26ai
```

See [seclab-runbook.md](seclab-runbook.md) and [dbsat-runbook.md](dbsat-runbook.md).

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `DBT-60127 ... TNS_ADMIN path ... is not a directory`, container restarts | Repository outside the mounts of the Colima/Podman VM, or `data/<service>/dbconfig/FREE/` missing | Clone below `$HOME`; `git restore data/` restores the markers |
| `FAIL image oracle-free-labs:<tag> not present` | Extended image not built for this tag | `make build`, check `DB_BASE_IMAGE` in `.env` |
| `FAIL port ... is published by container ...` | Another service or engine holds the port | Stop the other container or change the port in `.env` |
| Container killed during setup (exit 137) | Memory limit of the VM or the service too low | VM at least 4 GB, service limit at least 3 GB |
| `Cannot connect to the Docker daemon` | Engine not running or wrong context | Start Docker Desktop / `colima start` / `podman machine start`; `docker context ls` |
