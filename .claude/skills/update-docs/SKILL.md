---
name: update-docs
description: Check and update documentation across all utilities in the repo, detect drift between READMEs and code, ensure docs stay in sync
---

# Update Documentation

Automated documentation maintenance skill that scans all utilities in the repo for documentation drift and helps keep READMEs, SKILL.md files, and other docs synchronized with code changes.

**When to use:** After making code changes to any utility, adding new features, or when documentation seems outdated.

## Repository Architecture

This repo contains multiple independent utilities, each with its **own isolated environment**:

- **WSL utilities** - Bash scripts (`.sh`) run in Ubuntu WSL
- **PowerShell utilities** - PowerShell scripts (`.ps1`) run in Windows PowerShell
- **Batch utilities** - Batch scripts (`.bat`) run in Windows Command Prompt

**Important:** Each utility uses ONE environment type, never mixed. Documentation should clearly state the environment and provide appropriate setup instructions for that type.

## What It Does

The skill analyzes:
- ✅ **README completeness** - checks if READMEs document all features (`.env` files, scripts, prerequisites)
- ✅ **README/SKILL.md sync** - ensures prerequisites and troubleshooting are consistent
- ✅ **Root README** - verifies all utilities are listed
- ✅ **Recent changes** - identifies utilities that changed recently and may need doc updates
- ✅ **Missing documentation** - flags utilities without skills or incomplete docs

## Quick Start

**Fast check** (recommended for Git Bash on Windows):
```bash
cd /path/to/utils.win
./.claude/skills/update-docs/quick-check.sh
```

**Detailed report** (comprehensive analysis):
```bash
./.claude/skills/update-docs/update-docs.sh
```

The quick check provides instant feedback. The detailed report generates a full analysis at `.claude/skills/update-docs/sync-report.md`.

## Usage Modes

### 1. Report Mode (Default)

Generates a comprehensive report of all documentation issues:

```bash
./.claude/skills/update-docs/update-docs.sh report
```

**Output:**
- Lists each utility with documentation issues
- Identifies missing sections (prerequisites, .env setup, troubleshooting)
- Checks README/SKILL.md consistency
- Verifies root README completeness
- Saves report to `.claude/skills/update-docs/sync-report.md`

**Example output:**
```
ℹ Scanning utilities...
ℹ Checking sh-convert-pdf-to-text...
✓   No issues found
ℹ Checking sync-obsidian...
⚠   Missing: Script execution permissions (chmod +x)
ℹ Checking root README...
✓   Root README is complete

⚠ Found 1 issue(s) across 4 utilities
```

### 2. Interactive Mode

Shows recent git changes and identifies utilities that may need documentation updates:

```bash
./.claude/skills/update-docs/update-docs.sh interactive
```

**Output:**
- Shows `git diff --stat` of recent changes
- Lists utilities with code changes
- Suggests which docs to review

**Use case:** Run this after making changes to see what documentation you should update.

### 3. Check Mode

Quick validation for CI/CD or pre-commit hooks:

```bash
./.claude/skills/update-docs/update-docs.sh check
```

**Output:**
- Exits 0 if all docs are in sync
- Exits 1 if issues found (with count)
- Minimal output

**Use case:** Add to git hooks or CI to enforce documentation standards.

## What It Checks

### README Completeness

For each utility's README, checks for:

| Feature Present | Check |
|----------------|-------|
| `.env` or `example.env` file | README mentions environment variables |
| `.env` in `.gitignore` | README references `example.env` or setup instructions |
| **WSL utilities** (`.sh` files) | README mentions WSL/Ubuntu requirement + `chmod +x` instructions |
| **PowerShell utilities** (`.ps1` files) | README mentions PowerShell + execution policy if needed |
| **Batch utilities** (`.bat` files) | README mentions Windows Command Prompt |
| Multiple script files | README documents each script's purpose |

The checker auto-detects utility type based on file extensions and validates platform-specific requirements.

### README ↔ SKILL.md Sync

Compares sections between README and SKILL.md:

- **Prerequisites** - Should exist in both if one has it
- **Troubleshooting** - SKILL.md troubleshooting should be reflected in README
- **Usage** - Basic usage should be consistent

**Why this matters:** READMEs are for humans browsing GitHub. SKILL.md is for agents. They should tell the same story.

### Root README Completeness

Checks if `README.md` at repo root lists all utilities found in subdirectories.

**Why this matters:** New utilities should be discoverable from the root README.

## Integration with Workflow

### After Code Changes

```bash
# 1. Make your changes
vim sh-convert-pdf-to-text/convert-pdf-to-text.sh

# 2. Check what docs need updating
./.claude/skills/update-docs/update-docs.sh interactive

# 3. Update the relevant docs
vim sh-convert-pdf-to-text/README.md

# 4. Verify all docs are in sync
./.claude/skills/update-docs/update-docs.sh check
```

### In Claude Code Workflow

When working with Claude Code:

1. **After implementing a feature:** "Run /update-docs to check documentation"
2. **Before committing:** "Check if documentation needs updates with /update-docs"
3. **When reviewing PRs:** "Use /update-docs to verify docs are current"

### As a Git Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/bash
if ! ./.claude/skills/update-docs/update-docs.sh check; then
  echo "❌ Documentation is out of sync. Update docs before committing."
  echo "   Run: ./.claude/skills/update-docs/update-docs.sh report"
  exit 1
fi
```

## Understanding the Report

The generated `sync-report.md` has this structure:

```markdown
# Documentation Sync Report

## Overview
[Summary of scan]

## <utility-name>
**Location:** `path/to/utility`
**Type:** wsl | powershell | batch
**Issues found:** N

- Issue description 1
- Issue description 2

## Root README
**Issues found:** N

- Root issue 1

## Summary
- **Utilities checked:** X
- **Total issues found:** Y

### Quick Fixes
[Actionable suggestions]
```

### Common Issues and Fixes

| Issue | Fix |
|-------|-----|
| "Missing: .env configuration documentation" | Add Prerequisites section documenting environment variables |
| "Missing: Reference to example.env" | Add setup instructions: `cp example.env .env` |
| "Missing: WSL/bash script execution instructions" | Add usage section with `chmod +x script.sh` and WSL requirement |
| "Warning: Should mention this is a WSL/Ubuntu script" | Add platform requirement to Prerequisites |
| "Missing: PowerShell execution instructions" | Document PowerShell requirement and any execution policy needs |
| "Warning: Should mention this is a Windows batch script" | Clarify platform in Prerequisites |
| "SKILL.md has troubleshooting but README doesn't" | Copy key troubleshooting items to README |
| "Utility 'X' not listed in root README" | Add entry to root README's Utilities section |
| "No skill found" | Consider creating a skill with `/run-skill-generator` |

## Examples

### Example: After Adding .env Support

**Scenario:** You added `.env` configuration to `sync-obsidian` utility.

```bash
$ ./.claude/skills/update-docs/update-docs.sh report

ℹ Checking sync-obsidian...
⚠   Missing: .env configuration documentation
⚠   Missing: Reference to example.env or .env setup

Found 2 issue(s)
```

**Fix:**
1. Open `sync-obsidian/README.md`
2. Add Prerequisites section documenting env vars
3. Add Setup section with `cp example.env .env`
4. Run check again: `./update-docs.sh check` → ✅

### Example: After Adding New Utility

**Scenario:** You created `new-utility/` with its own README.

```bash
$ ./.claude/skills/update-docs/update-docs.sh check

ℹ Checking root README...
⚠   Utility 'new-utility' not listed in root README

Found 1 issue(s)
```

**Fix:**
1. Open root `README.md`
2. Add entry under Utilities section
3. Describe what the utility does
4. Link to its directory

### Example: Interactive Mode After Changes

```bash
$ git commit -m "Add OCR support to pdf converter"

$ ./.claude/skills/update-docs/update-docs.sh interactive

ℹ Recent changes:
 sh-convert-pdf-to-text/convert-pdf-to-text.sh | 150 ++++++++++++++++---
 sh-convert-pdf-to-text/README.md              |  10 +-

ℹ These utilities may need documentation updates:
  - sh-convert-pdf-to-text

[Review sh-convert-pdf-to-text/README.md to document new OCR feature]
```

## Gotchas

### False Positives for .env

If a utility has `example.env` but doesn't actually use environment variables (it's just a template), the checker will still flag it. Manually verify these.

### Skill Detection

The checker looks for `.claude/skills/run-*/SKILL.md` pattern. Skills with different naming patterns may not be detected.

### Git-Based Change Detection

Interactive mode requires git history. In a fresh clone without commits, it won't detect recent changes.

### Markdown Keyword Matching

The checker uses keyword matching (`grep -qi "prerequisite"`). Very unconventional section names might not be detected. Use standard headings:
- "Prerequisites" or "Requirements"
- "Usage" or "Getting Started"
- "Troubleshooting" or "Common Issues"

## Extending the Checker

The script is designed to be extended. To add new checks:

1. **Add a check function:**
   ```bash
   check_my_custom_rule() {
     local util_dir="$1"
     local issues=()
     
     # Your checking logic here
     
     printf '%s\n' "${issues[@]}"
   }
   ```

2. **Call it in `generate_report()`:**
   ```bash
   mapfile -t custom_issues < <(check_my_custom_rule "$util_dir")
   util_issues+=("${custom_issues[@]}")
   ```

3. **Test:**
   ```bash
   ./update-docs.sh report
   ```

## Troubleshooting

### Permission Denied

**Symptom:** `Permission denied: ./update-docs.sh`

**Solution:**
```bash
chmod +x .claude/skills/update-docs/update-docs.sh
```

### Command Not Found: realpath

**Symptom:** `realpath: command not found` (on some systems)

**Solution:** The script uses `realpath` for relative paths. If unavailable, replace with:
```bash
# In the script, replace:
realpath --relative-to="$REPO_ROOT" "$util_dir"

# With:
echo "${util_dir#$REPO_ROOT/}"
```

### Report File Won't Generate

**Symptom:** No `sync-report.md` created

**Solution:** Check write permissions on `.claude/skills/update-docs/` directory:
```bash
ls -la .claude/skills/update-docs/
chmod 755 .claude/skills/update-docs/
```

### Colors Not Showing

**Symptom:** ANSI escape codes appear as literal text

**Cause:** Terminal doesn't support colors

**Solution:** The script uses standard ANSI codes. If needed, disable by commenting out color definitions at the top of `update-docs.sh`.

## Output Files

The skill creates one file:

- `.claude/skills/update-docs/sync-report.md` - Generated report (safe to commit or gitignore)

To ignore the report in git:
```bash
echo ".claude/skills/update-docs/sync-report.md" >> .gitignore
```

Or commit it to track documentation health over time.

## See Also

- Each utility's `README.md` - Human-facing documentation
- Each utility's `.claude/skills/run-*/SKILL.md` - Agent-facing instructions
- Root `README.md` - Project overview and utility index
