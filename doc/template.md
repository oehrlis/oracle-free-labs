---
title: Project Title
subtitle: Short Subtitle or Document Purpose
author:
  - name: Your Name
    affiliation: Your Organization
date: YYYY-MM-DD
version: 0.1.0
lang: en
---
<!-- markdownlint-disable MD025 -->
<!-- markdownlint-configure-file { "MD013": { "tables": false } } -->

# Preface {-}

This document provides an overview of the topic and outlines its purpose.  
Replace this section with a high-level introduction tailored to your project.

## About This Document {.unlisted .unnumbered}

Describe the intended audience and scope.  
List assumptions and constraints relevant to readers.

## Copyright and Disclaimer {.unlisted .unnumbered}

Oracle and Java are registered trademarks of Oracle and/or its affiliates. Other
names may be trademarks of their respective owners. The Oracle products listed
in this report are subject to Oracle's license terms and conditions.

## Document Information {.unlisted .unnumbered}

- **Title**: Project Title - Implementation Guide
- **Status**: Draft
- **Last Updated**: YYYY-MM-DD
- **Authors**: Your Name(s)
- **Document Name**: template.pdf

| Lead Authors  | Contributors & Reviewers |
|---------------|--------------------------|
| Stefan Oehrli |                          |

Table: Authors

## Revision History {.unlisted .unnumbered}

| Version | Date       | Visa | Comment                                                |
|---------|------------|------|--------------------------------------------------------|
| 0.1.0   | 2024.07.11 | soe  | Initial document based on *Solution and Concept Guide* |
| 0.2.0   | 2024.08.21 | soe  | Complete update of chapter *TDE Configuration*         |
| 0.3.0   | 2024.08.22 | soe  | Complete update of chapter *TDE Migration*             |
| 0.4.0   | 2024.08.23 | soe  | Add migration procedure for RiskShield                 |

Table: Revision History

# Management Summary

Summarize the objectives and goals of the project.  
Keep this section short and informative for decision-makers.

# Introduction

Lorem ipsum dolor sit amet consectetur adipiscing elit. Quisque faucibus ex
sapien vitae pellentesque sem placerat. In id cursus mi pretium tellus duis
convallis. Tempus leo eu aenean sed diam urna tempor. Pulvinar vivamus fringilla
lacus nec metus bibendum egestas. Iaculis massa nisl malesuada lacinia integer nunc
posuere. Ut hendrerit semper vel class aptent taciti sociosqu. Ad litora torquent
per conubia nostra inceptos himenaeos.

## Project Overview

Lorem ipsum dolor sit amet consectetur adipiscing elit. Quisque faucibus ex
sapien vitae pellentesque sem placerat. In id cursus mi pretium tellus duis
convallis. Tempus leo eu aenean sed diam urna tempor. Pulvinar vivamus fringilla
lacus nec metus bibendum egestas. Iaculis massa nisl malesuada lacinia integer nunc
posuere. Ut hendrerit semper vel class aptent taciti sociosqu. Ad litora torquent
per conubia nostra inceptos himenaeos.

## Project Goals

Lorem ipsum dolor sit amet consectetur adipiscing elit. Quisque faucibus ex
sapien vitae pellentesque sem placerat. In id cursus mi pretium tellus duis
convallis. Tempus leo eu aenean sed diam urna tempor. Pulvinar vivamus fringilla
lacus nec metus bibendum egestas. Iaculis massa nisl malesuada lacinia integer nunc
posuere. Ut hendrerit semper vel class aptent taciti sociosqu. Ad litora torquent
per conubia nostra inceptos himenaeos.

## Document Conventions

The following typographical conventions are used throughout this documentation:

| Convention   | Meaning                                                                                                                        |
|--------------|--------------------------------------------------------------------------------------------------------------------------------|
| **boldface** | Boldface type indicates graphical user interface elements associated with an action, or terms defined in text or the glossary. |
| *italic*     | Italic type indicates book titles, product names, emphasis, or placeholder variables for which you supply values.              |
| `monospace`  | Used for blocks of code, inline code, commands, and script examples. Text should be interpreted exactly as presented.          |

Table: Document Conventions

In addition, the following text blocks are used to emphasize important points,
notes or warnings to highlight.

::: note
This text block is used for **hints** or specific explanations.
:::

::: important
Important notes, specifications etc. are indicated with the text block **Important**.
:::

# Requirements

## General Requirements

Describe compliance, security, performance, or functional requirements here.

## Scope and Assumptions

Define what is included in the project and any boundaries or dependencies.

# Solution Design

## Technical Approach

Describe the chosen approach, tools, technologies, and architecture at a high level.

## Implementation Steps

List the main steps for implementing the solution.  
Use bullet points or subheadings for clarity.

# Operations & Administration

Define operational responsibilities and how key tasks will be handled.  
Consider topics like monitoring, backups, access control, etc.

# Appendices

# Appendix A: References

List standards, links, or documentation used during preparation.

# Appendix B: Abbreviations

Define important terms, acronyms, or domain-specific language.

---

> **Tip**: Split long documents into multiple files using a naming scheme like:
> `ProjectGuide-part1.md`, `ProjectGuide-part2.md`. Use `ProjectGuide*.md` in your PDF build script.
>  
> Each document must include a corresponding metadata `.yml` file named `ProjectGuide.yml`.
