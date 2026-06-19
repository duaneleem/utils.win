#!/usr/bin/env bash
# Documentation update validator and helper
# Scans utilities for documentation drift and helps keep docs in sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly REPORT_FILE="$REPO_ROOT/.claude/skills/update-docs/sync-report.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Find all utility directories (those with README.md)
find_utilities() {
  find "$REPO_ROOT" -mindepth 2 -maxdepth 2 -name "README.md" -type f -exec dirname {} \; 2>/dev/null | while read -r dir; do
    # Skip hidden directories
    [[ "$(basename "$dir")" == .* ]] && continue
    echo "$dir"
  done
}

# Detect utility type (WSL bash, PowerShell, or batch)
get_utility_type() {
  local util_dir="$1"
  local has_sh=false has_ps1=false has_bat=false

  compgen -G "$util_dir/*.sh" > /dev/null 2>&1 && has_sh=true
  compgen -G "$util_dir/*.ps1" > /dev/null 2>&1 && has_ps1=true
  compgen -G "$util_dir/*.bat" > /dev/null 2>&1 && has_bat=true

  if [[ "$has_sh" == true ]]; then
    echo "wsl"
  elif [[ "$has_ps1" == true ]]; then
    echo "powershell"
  elif [[ "$has_bat" == true ]]; then
    echo "batch"
  else
    echo "unknown"
  fi
}

# Check if a utility has a skill
has_skill() {
  local util_dir="$1"
  [[ -f "$util_dir/.claude/skills/run-"*"/SKILL.md" ]]
}

# Get skill path for a utility
get_skill_path() {
  local util_dir="$1"
  find "$util_dir/.claude/skills" -name "SKILL.md" -type f 2>/dev/null | head -1
}

# Check if README mentions key features from code
check_readme_completeness() {
  local util_dir="$1"
  local readme="$util_dir/README.md"
  local issues=()
  local util_type
  util_type=$(get_utility_type "$util_dir")

  # Check for common documentation gaps
  if [[ -f "$util_dir/.env" ]] || [[ -f "$util_dir/example.env" ]]; then
    if ! grep -qi "\.env\|environment\s*variable" "$readme"; then
      issues+=("Missing: .env configuration documentation")
    fi
  fi

  if [[ -f "$util_dir/.gitignore" ]]; then
    # Check if there are important files being ignored that should be documented
    if grep -q "\.env$" "$util_dir/.gitignore" && ! grep -qi "example\.env\|\.env.*template" "$readme"; then
      issues+=("Missing: Reference to example.env or .env setup")
    fi
  fi

  # Check for script files based on type
  case "$util_type" in
    wsl)
      if ! grep -qi "chmod\|executable\|permission\|wsl\|ubuntu\|bash" "$readme"; then
        issues+=("Missing: WSL/bash script execution instructions (chmod +x)")
      fi
      if ! grep -qi "wsl\|ubuntu\|linux" "$readme"; then
        issues+=("Warning: Should mention this is a WSL/Ubuntu script")
      fi
      ;;
    powershell)
      if ! grep -qi "powershell\|\.ps1\|execution\s*policy" "$readme"; then
        issues+=("Missing: PowerShell execution instructions or requirements")
      fi
      ;;
    batch)
      if ! grep -qi "batch\|\.bat\|command\s*prompt\|cmd" "$readme"; then
        issues+=("Warning: Should mention this is a Windows batch script")
      fi
      ;;
  esac

  # Check if README mentions the platform
  if [[ "$util_type" == "wsl" ]] && ! grep -qi "windows.*wsl\|wsl.*windows\|ubuntu.*wsl" "$readme"; then
    issues+=("Suggestion: Clarify this requires WSL (Windows Subsystem for Linux)")
  fi

  printf '%s\n' "${issues[@]}"
}

# Check if README and SKILL.md are in sync
check_readme_skill_sync() {
  local util_dir="$1"
  local readme="$util_dir/README.md"
  local skill
  skill=$(get_skill_path "$util_dir")
  local issues=()

  [[ -z "$skill" ]] && return

  # Extract key sections from README
  local readme_has_prereq=false
  local readme_has_usage=false
  local readme_has_troubleshoot=false

  grep -qi "requirement\|prerequisite\|install" "$readme" && readme_has_prereq=true
  grep -qi "usage\|how to\|getting started" "$readme" && readme_has_usage=true
  grep -qi "troubleshoot\|common\s*issue\|error" "$readme" && readme_has_troubleshoot=true

  # Extract from SKILL.md
  local skill_has_prereq=false
  local skill_has_usage=false
  local skill_has_troubleshoot=false

  grep -qi "prerequisite\|requirement" "$skill" && skill_has_prereq=true
  grep -qi "usage\|run\|how to" "$skill" && skill_has_usage=true
  grep -qi "troubleshoot\|gotcha\|common\s*issue" "$skill" && skill_has_troubleshoot=true

  # Compare
  if [[ "$skill_has_prereq" == true ]] && [[ "$readme_has_prereq" == false ]]; then
    issues+=("SKILL.md has prerequisites section but README doesn't")
  fi

  if [[ "$skill_has_troubleshoot" == true ]] && [[ "$readme_has_troubleshoot" == false ]]; then
    issues+=("SKILL.md has troubleshooting but README doesn't")
  fi

  printf '%s\n' "${issues[@]}"
}

# Check root README lists all utilities
check_root_readme() {
  local root_readme="$REPO_ROOT/README.md"
  local issues=()

  while IFS= read -r util_dir; do
    local util_name
    util_name=$(basename "$util_dir")

    # Check if utility is mentioned in root README
    if ! grep -qi "$util_name" "$root_readme"; then
      issues+=("Utility '$util_name' not listed in root README")
    fi
  done < <(find_utilities)

  printf '%s\n' "${issues[@]}"
}

# Generate documentation sync report
generate_report() {
  local output="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  cat > "$output" <<EOF
# Documentation Sync Report

Generated: $timestamp

## Overview

This report identifies documentation drift and missing documentation across all utilities.

EOF

  log_info "Scanning utilities..."

  local total_issues=0
  local utils_checked=0

  # Get utilities into an array to avoid subshell issues
  mapfile -t utility_dirs < <(find_utilities)

  for util_dir in "${utility_dirs[@]}"; do
    local util_name
    util_name=$(basename "$util_dir")
    ((utils_checked++))

    log_info "Checking $util_name..."

    local util_issues=()

    # Check README completeness
    mapfile -t completeness_issues < <(check_readme_completeness "$util_dir" 2>/dev/null || true)
    util_issues+=("${completeness_issues[@]}")

    # Check README/SKILL sync
    if has_skill "$util_dir" 2>/dev/null; then
      mapfile -t sync_issues < <(check_readme_skill_sync "$util_dir" 2>/dev/null || true)
      util_issues+=("${sync_issues[@]}")
    else
      util_issues+=("No skill found - consider creating one")
    fi

    # Report for this utility
    if [[ ${#util_issues[@]} -gt 0 ]]; then
      ((total_issues += ${#util_issues[@]}))

      # Get relative path without realpath (more portable)
      local rel_path="${util_dir#$REPO_ROOT/}"

      cat >> "$output" <<EOF

## $util_name

**Location:** \`$rel_path\`

**Type:** $(get_utility_type "$util_dir")

**Issues found:** ${#util_issues[@]}

EOF

      for issue in "${util_issues[@]}"; do
        echo "- $issue" >> "$output"
        log_warning "  $issue"
      done
    else
      log_success "  No issues found"
    fi
  done

  # Check root README
  log_info "Checking root README..."
  mapfile -t root_issues < <(check_root_readme)

  if [[ ${#root_issues[@]} -gt 0 ]]; then
    ((total_issues += ${#root_issues[@]}))

    cat >> "$output" <<EOF

## Root README

**Issues found:** ${#root_issues[@]}

EOF

    for issue in "${root_issues[@]}"; do
      echo "- $issue" >> "$output"
      log_warning "  $issue"
    done
  else
    log_success "  Root README is complete"
  fi

  # Summary
  cat >> "$output" <<EOF

## Summary

- **Utilities checked:** $utils_checked
- **Total issues found:** $total_issues

EOF

  if [[ $total_issues -eq 0 ]]; then
    cat >> "$output" <<'EOF'

✅ **All documentation is in sync!**
EOF
    log_success "\nAll documentation is in sync!"
  else
    cat >> "$output" <<'EOF'

⚠️ **Documentation needs updates.** Review issues above and update accordingly.

### Quick Fixes

1. **Missing .env docs:** Document environment variables in README Prerequisites section
2. **Missing chmod docs:** Add execution instructions for scripts
3. **Root README outdated:** Add new utilities to the Utilities section
4. **README/SKILL drift:** Sync troubleshooting and prerequisites between files
EOF
    log_warning "\nFound $total_issues issue(s) across $utils_checked utilities"
  fi
}

# Interactive update mode
interactive_update() {
  log_info "Interactive documentation update mode"
  echo

  # Show recent git changes
  if git rev-parse --git-dir > /dev/null 2>&1; then
    log_info "Recent changes:"
    git diff --stat HEAD~1 2>/dev/null || log_warning "No recent commits to compare"
    echo
  fi

  # Find utilities with changes
  local changed_utils=()
  if git rev-parse --git-dir > /dev/null 2>&1; then
    while IFS= read -r util_dir; do
      local util_name
      util_name=$(basename "$util_dir")

      # Check if this utility has recent changes
      if git diff --quiet HEAD~1 -- "$util_dir" 2>/dev/null; then
        : # No changes
      else
        changed_utils+=("$util_dir")
        log_warning "Changes detected in: $util_name"
      fi
    done < <(find_utilities)
  fi

  if [[ ${#changed_utils[@]} -eq 0 ]]; then
    log_info "No recent changes to utilities detected"
  else
    echo
    log_info "These utilities may need documentation updates:"
    for util_dir in "${changed_utils[@]}"; do
      echo "  - $(basename "$util_dir")"
    done
  fi
}

# Main
main() {
  cd "$REPO_ROOT"

  local mode="${1:-report}"

  case "$mode" in
    report)
      log_info "Generating documentation sync report..."
      generate_report "$REPORT_FILE"
      log_success "\nReport saved to: $REPORT_FILE"

      # Show report
      if command -v cat &>/dev/null; then
        echo
        cat "$REPORT_FILE"
      fi
      ;;

    interactive)
      interactive_update
      ;;

    check)
      # Quick check mode - just count issues
      log_info "Quick documentation check..."
      generate_report "$REPORT_FILE" > /dev/null

      local issue_count
      issue_count=$(grep -c "^- " "$REPORT_FILE" || echo 0)

      if [[ $issue_count -eq 0 ]]; then
        log_success "All documentation is in sync!"
        exit 0
      else
        log_error "Found $issue_count documentation issue(s)"
        log_info "Run 'update-docs.sh report' for details"
        exit 1
      fi
      ;;

    *)
      echo "Usage: $0 [report|interactive|check]"
      echo
      echo "Modes:"
      echo "  report      - Generate full documentation sync report (default)"
      echo "  interactive - Show recent changes and suggest updates"
      echo "  check       - Quick check (exit 1 if issues found)"
      exit 1
      ;;
  esac
}

main "$@"
