# Install DB*Star BasEnv in the Container

DB*Star Toolbox (formerly Trivadis BasEnv) provides shell environments, helper scripts, and conventions that simplify command line administration on Oracle DB servers. It can also be installed into this container for convenient interactive work. The installer additionally applies basic OS packages via `dnf` and deploys OraDBA utility scripts from [oehrlis/oradba](https://github.com/oehrlis/oradba).

## Requirements

- Internet access from the host and the container
  - Required to fetch `oradba_init` bootstrap and to install base OS packages via `dnf` or `microdnf`
- *DB*Star BasEnv* package zip
  - Not publicly available
  - By default the script looks for `artefacts/dbstar-basenv_24.05_basenv-24.05.final.b.zip`
  - You can provide an alternative package with `--basenv-pkg`
- A running compose service container
  - Defaults to `cdbfree` unless you pass a different service name

## What the installer does

- Installs OraDBA init into the running container
- Optionally installs *DB*Star BasEnv* from a provided zip package
- Installs a small set of useful tools inside the container
  - `file`, `lsof`, `which`, `tree` and optionally `rlwrap` if available in repos
- Relocates BasEnv configuration folder
  - Moves `/opt/oracle/local/dba/etc` into the persisted path `/opt/oracle/oradata/dbconfig/basenv/etc`
  - Replaces any symlinks inside the original `etc` with their target files prior to the move
  - Creates a symlink back to `/opt/oracle/local/dba/etc`
- Links Oracle Net config files to persisted dbconfig if they exist
  - Creates symlinks from the Oracle home `network/admin` to `/opt/oracle/oradata/dbconfig/FREE/{ldap.ora,listener.ora,sqlnet.ora,tnsnames.ora}`

## Where to place the BasEnv package

- Default location on the host
  - `./artefacts/dbstar-basenv_24.05_basenv-24.05.final.b.zip`
- Custom location
  - Pass with `--basenv-pkg` either as a filename under `./artefacts/` or as an absolute path

Examples

```bash
# default lookup in ./artefacts
./bin/install_oradba_init.sh

# explicit filename in ./artefacts
./bin/install_oradba_init.sh --basenv-pkg dbstar-basenv_24.05_basenv-24.05.final.b.zip

# explicit path
./bin/install_oradba_init.sh --basenv-pkg /tmp/custom-basenv-24.06.zip
```

## Usage

The setup script runs from the host and executes inside the container via Docker or Podman.

Basic usage

```bash
# autodetect engine, default container 'cdbfree'
./bin/install_oradba_init.sh
```

Specify engine and target container

```bash
# Docker, install into service 'odbrepo'
./bin/install_oradba_init.sh odbrepo

# Podman, install into service 'odbdemo'
./bin/install_oradba_init.sh --engine podman odbdemo
```

Install with a specific BasEnv package

```bash
# use an artefacts-local zip
./bin/install_oradba_init.sh --basenv-pkg dbstar-basenv_24.05_basenv-24.05.final.b.zip

# or with a full path
./bin/install_oradba_init.sh --basenv-pkg /path/to/dbstar-basenv_24.06.zip
```

## Example Installation

Below you find an example how to install BasEnv in container service **odbdemo** executing the engine **docker** and the default BasEnv package from `artefacts/`

```code
bin/install_oradba_init.sh odbdemo
INFO : Using engine        : docker
INFO : Target container    : odbdemo
INFO : Logging detailed install output to data/odbdemo/install_oradba_init_20250820_123641.log
INFO : Removing existing /opt/oradba (root)...
INFO : Fetching oradba_init setup (oracle)...
INFO : Mark setup executable (oracle)...
INFO : Run OraDBA setup as root...
INFO : Cleanup setup tmp...
INFO : Installing useful tools (file, lsof, which, tree; rlwrap if available)...
INFO : Installing BasEnv from /Users/stefan.oehrli/Development/github/oracle-free-labs/artefacts/dbstar-basenv_24.05_basenv-24.05.final.b.zip...
INFO : Cleaning BE_INITIALSID block in oracle's shell profiles...
INFO : Relocating BasEnv config to /opt/oracle/oradata/dbconfig/basenv/etc (reusing if present)...
INFO : Linking Oracle Net config to /opt/oracle/oradata/dbconfig/FREE if present...
INFO : Done. oradba_init installed and post-configuration applied to odbdemo
```

## Verifying the installation

Inside the container

```bash
# Docker example
docker exec -it cdbfree bash -l

# Podman example
podman exec -it cdbfree bash -l
```

Check folders and links

```bash
# BasEnv home
ls -l /opt/oracle/local/dba

# Persisted BasEnv etc
ls -l /opt/oracle/oradata/dbconfig/basenv/etc

# Oracle Net links (if config exists in dbconfig/FREE)
ls -l /opt/oracle/product/*/dbhome*/network/admin
```

You should see

- `/opt/oracle/local/dba/etc` as a symlink pointing to `/opt/oracle/oradata/dbconfig/basenv/etc`
- Oracle Net files in the Oracle home `network/admin` linking to `/opt/oracle/oradata/dbconfig/FREE`

## Example interactive usage

Open a shell and use DB\*Star helpers

```bash
docker exec -it odbrepo bash -l
# or
podman exec -it odbrepo bash -l
```

You can then use your usual BasEnv shortcuts and OraDBA scripts, for example

```bash
# common examples (adjust to your BasEnv profile)
. oraenv              # or your BasEnv profile helper
sqh
```

## Notes and tips

- BasEnv package zip is required only if you want DB\*Star features inside the container. The rest of the initialization still works without it.
- The installer tries to keep memory footprint low when installing OS tools. If repositories are limited, some optional tools like `rlwrap` may be skipped.
- If `/opt/oracle/oradata/dbconfig/basenv/etc` already exists from a previous run, it is reused and not overwritten.
- Symlink handling

  - Any symlinks found inside `/opt/oracle/local/dba/etc` are replaced with their target file content before the directory is moved to the persisted location
  - This avoids broken links after the relocation

## Troubleshooting

- No internet access

  - The `dnf` package step and bootstrap download will fail. Ensure the container can reach your package repos and GitHub

- BasEnv package not found

  - Confirm the file exists under `./artefacts/` or pass `--basenv-pkg /full/path/to/zip`

- Container not running

  - Start the desired compose service first and re-run the installer

```bash
docker compose --profile cdbfree up -d
# or
podman-compose --profile cdbfree up -d
```

## Links

- [Setup Lab Environment](setup_lab_environment.md)
- [Service Setup](service_setup.md)
- [Interactive Shell Access](interactive_shell.md)
- [SQL Access](sql_developer.md)
