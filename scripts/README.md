# Folder: bin

This folder contains **utility scripts** used for initializing and managing the project structure. These scripts help maintain consistency, automate setup, and simplify documentation generation.

## Included Scripts

### `init_project.sh`

Unpacks a pre-embedded base64-encoded `.tgz` archive containing the full project structure.

**Usage:**

```bash
./bin/init_project.sh [OPTIONS]
```

**Options:**

- `-d, --directory <dir>`  Destination directory (default: current directory)
- `-n, --name <folder>`   Target folder name for extraction (default: `project-template`)
- `-r, --root`         Extract only the contents of the template, not the wrapper folder
- `-t, --tgz-only`      Only extract the `.tgz` file, do not unpack
- `-f, --force`         Overwrite the target folder if it already exists
- `-h, --help`         Display help and usage

### `build_project.sh`

Creates a `.tgz` archive from the project structure and updates the embedded payload in `init_project.sh`.

**Usage:**

```bash
./bin/build_project.sh [OPTIONS]
```

**Options:**

- `-d, --directory <dir>`  Directory to pack (default: project root)
- `-n, --name <file>`    Name of the `.tgz` archive (default: `project_structure.tgz`)
- `-i, --init-script <path>` Path to the `init_project.sh` script to update
- `-h, --help`         Display help and usage

## Notes

- `build_project.sh` preserves LF line endings when updating the init script.
- `init_project.sh` shows a project tree at the end, if the `tree` utility is installed.
