#!/usr/bin/env bash
# Quick documentation check - fast version for Git Bash on Windows
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Quick Documentation Check ==="
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

total_issues=0

# Check each utility
for util_dir in */; do
  # Skip hidden dirs and non-utility dirs
  [[ "$util_dir" == .* ]] && continue
  [[ ! -f "$util_dir/README.md" ]] && continue

  util_name="${util_dir%/}"
  echo "Checking $util_name..."

  # Detect type
  type="unknown"
  compgen -G "$util_dir"*.sh > /dev/null 2>&1 && type="wsl"
  compgen -G "$util_dir"*.ps1 > /dev/null 2>&1 && type="powershell"
  compgen -G "$util_dir"*.bat > /dev/null 2>&1 && type="batch"

  readme="$util_dir/README.md"
  issues=0

  # Check .env documentation
  if [[ -f "$util_dir/.env" ]] || [[ -f "$util_dir/example.env" ]]; then
    if ! grep -qi "\.env\|environment.*variable" "$readme" 2>/dev/null; then
      echo -e "  ${YELLOW}⚠${NC} Missing .env documentation"
      ((issues++))
    fi
  fi

  # Check platform-specific docs
  case "$type" in
    wsl)
      if ! grep -qi "wsl\|ubuntu\|bash" "$readme"; then
        echo -e "  ${YELLOW}⚠${NC} Should mention WSL/Ubuntu requirement"
        ((issues++))
      fi
      if ! grep -qi "chmod" "$readme"; then
        echo -e "  ${YELLOW}⚠${NC} Missing chmod +x instructions"
        ((issues++))
      fi
      ;;
    powershell)
      if ! grep -qi "powershell" "$readme"; then
        echo -e "  ${YELLOW}⚠${NC} Should mention PowerShell requirement"
        ((issues++))
      fi
      ;;
    batch)
      if ! grep -qi "batch\|\.bat\|command" "$readme"; then
        echo -e "  ${YELLOW}⚠${NC} Should mention this is a batch script"
        ((issues++))
      fi
      ;;
  esac

  # Check if has skill
  if [[ ! -d "$util_dir/.claude/skills" ]]; then
    echo -e "  ${YELLOW}⚠${NC} No skill found"
    ((issues++))
  fi

  if [[ $issues -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} OK"
  else
    ((total_issues += issues))
  fi

  echo
done

# Check root README
echo "Checking root README..."
root_issues=0
for util_dir in */; do
  [[ "$util_dir" == .* ]] && continue
  [[ ! -f "$util_dir/README.md" ]] && continue

  util_name="${util_dir%/}"
  if ! grep -qi "$util_name" README.md 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} '$util_name' not listed in root README"
    ((root_issues++))
    ((total_issues++))
  fi
done

if [[ $root_issues -eq 0 ]]; then
  echo -e "  ${GREEN}✓${NC} OK"
fi

echo
echo "=== Summary ==="
if [[ $total_issues -eq 0 ]]; then
  echo -e "${GREEN}✓${NC} All documentation is in sync!"
  exit 0
else
  echo -e "${RED}✗${NC} Found $total_issues issue(s)"
  echo "Run: .claude/skills/update-docs/update-docs.sh report (for detailed analysis)"
  exit 1
fi
