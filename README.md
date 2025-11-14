# Project Bootstrap Template

This repository provides a reusable template to bootstrap a standardized project structure for documentation, scripts, and demos.

## 📦 Features

- 🧰 Self-contained initialization script (`init_project.sh`) with embedded template payload
- 🔁 Build script (`build_project.sh`) to package and update the payload
- 📄 Markdown-based documentation and Pandoc-compatible PDF generation
- 🧪 Compatible with macOS, Linux, and container-based dev environments
- 🚀 GitHub Actions workflow publishes the latest script to a GitHub Release

## 🚀 Getting Started

To create a new project from this template:

```bash
./bin/init_project.sh -d /path/to/target -n my-new-project
```

To update the embedded payload after making changes:

```bash
./bin/build_project.sh
```

## 🌐 Quick Download via GitHub Release

You can download the latest generated `init_project.sh` script directly from GitHub:

```bash
curl -fsSL -H "Authorization: token $GH_PAT" \
  -o init_project.sh \
  https://github.com/<user>/<repo>/releases/download/latest/init_project.sh
chmod +x init_project.sh
```

> Replace `<user>` and `<repo>` with your actual GitHub username and repository name.

## 📁 Folder Overview

| Folder         | Description                                                      |
|----------------|------------------------------------------------------------------|
| `artefacts/`   | Generated files like PDFs, Excel, or Office docs                 |
| `bin/`         | Utility scripts for setup and automation                         |
| `doc/`         | Markdown documentation sources                                   |
| `fonts/`       | Fonts used for PDF generation                                    |
| `images/`      | Screenshots, diagrams, and logos                                 |
| `notes/`       | Drafts, notes, and to-do items                                   |
| `sql/`         | SQL scripts for validation or automation                         |

## 🔐 GitHub Actions Setup

This repo includes a workflow that automatically builds `init_project.sh` and uploads it to the `latest` release.

To make this work:
1. Push to `main`
2. The GitHub Actions workflow will publish the script to the release

## 📝 License

Apache License 2.0 — See [LICENSE](http://www.apache.org/licenses/LICENSE-2.0)
