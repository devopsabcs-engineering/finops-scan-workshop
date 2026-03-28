# Contributing to the FinOps Cost Governance Workshop

Thank you for your interest in contributing to this workshop. This guide covers how to submit changes and the style conventions for lab content.

## How to Contribute

1. **Fork** the repository.
2. **Create a feature branch** from `main`:

   ```bash
   git checkout -b feature/your-change-description
   ```

3. Make your changes following the style guide below.
4. **Test locally** by running `bundle exec jekyll serve` and verifying links and formatting.
5. **Submit a pull request** targeting `main` with a clear description of your changes.

## Lab Authoring Style Guide

### Voice and Tone

- Use **second-person voice** ("you", "your") to address the student directly.
- Use **present tense** and **active voice**.
- Keep instructions concise and action-oriented.

### Structure

Every lab follows this structure:

```markdown
# Lab XX — Title

## Objectives

- Objective 1
- Objective 2

## Prerequisites

- Prerequisite 1

## Steps

### Step 1: Description

Instructions...

### Step 2: Description

Instructions...

## Checkpoint

Verification criteria...

## Summary

What the student learned...

## Next Steps

Link to the next lab...
```

### Code Blocks

- Always specify the language in fenced code blocks (````powershell`, ````bash`, ````yaml`, ````bicep`).
- Use `powershell` for PowerShell commands and `bash` for shell commands.
- Include expected output when it helps the student verify their work.

### Callouts

Use GitHub alert syntax for tips, warnings, and notes:

```markdown
> [!NOTE]
> Additional context the student should know.

> [!TIP]
> Helpful shortcut or best practice.

> [!WARNING]
> Something that could cause issues if ignored.

> [!IMPORTANT]
> Critical information the student must follow.
```

### Screenshots

- Place screenshots in `images/lab-XX/` directories.
- Name files descriptively: `lab-02-psrule-output.png`, `lab-06-security-tab-filters.png`.
- Reference using relative paths: `![Description](../images/lab-02/psrule-output.png)`.
- Use the `scripts/capture-screenshots.ps1` script for automated captures when available.

### Links

- Use relative links for cross-references between labs.
- Link to external documentation by URL with descriptive text.

## Reporting Issues

Open an issue describing the problem, including which lab and step number is affected. Include error messages and your environment details (OS, tool versions).
