Here's the complete and accurate English version of your `doc/README.md`, with all requested additions:

---

# Folder: doc

This directory contains the **active project documentation** in Markdown format, including:

- Planning and design documents
- Meeting notes and decision logs
- Technical notes and to-do lists
- README files for the overall project structure

All Markdown files in this folder serve as the source for PDF generation (see `artefacts/`).

## Additional Information

- Images and diagrams referenced in documentation should be placed in the `images/` folder.
- Custom fonts used in the final PDF output should be stored in the `fonts/` folder.
- PDFs are built using **Pandoc** via a Docker container. Refer to the `bin/generate_pdf.sh` script for details.

## Metadata Files

Each document must have its own corresponding `metadata.yml` file in the `doc/` directory. This file defines title, author, layout settings, fonts, logos, and more for PDF generation.

## Splitting Documents

A single document can be split into multiple Markdown files for better organization and modular editing.
For example, `template.md` can be split as:

- `template-part1.md`
- `template-part2.md`
- `template-part3-appendix.md`

The build process automatically includes all files matching `template*.md` (where `template` is just an example). The file order must be controlled by consistent naming (e.g., numeric or alphabetical suffixes).

> ⚠️ Ensure file naming follows a logical sequence to preserve correct document structure during merging and PDF generation.
