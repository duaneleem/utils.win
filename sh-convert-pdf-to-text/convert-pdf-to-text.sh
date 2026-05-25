#!/usr/bin/env bash
# Batch-convert PDFs to UTF-8 text via pdftotext (poppler-utils).
# Run in Ubuntu WSL: bash convert-pdf-to-text.sh

set -euo pipefail

readonly PDFTOTEXT_OPTS=(-enc UTF-8 -nopgbrk)

usage() {
  cat <<'EOF'
Usage: convert-pdf-to-text.sh

Prompts for source and target WSL folder paths, then converts every PDF
in the source folder (including subdirectories) to .txt files in the target folder.

Output names look like: authorlastname_year_shorttitle.txt
  - Parsed from filenames like AuthorLastName_2024_Short-Title.pdf
  - Or derived from PDF metadata (pdfinfo) when available
  - Otherwise: sanitized lowercase stem of the PDF name

Requires: pdftotext (install: sudo apt install poppler-utils)
Optional: pdfinfo for metadata-based naming
EOF
}

need_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' not found. $2" >&2
    exit 1
  fi
}

normalize_slug() {
  # Lowercase; keep letters, digits, underscores; collapse runs of underscores.
  local s
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  s=$(printf '%s' "$s" | tr -cs 'a-z0-9_' '_')
  s="${s#_}"
  s="${s%_}"
  s=$(printf '%s' "$s" | sed 's/__*/_/g')
  printf '%s' "$s"
}

author_lastname() {
  # "Smith, John" -> smith; "John Smith" -> smith
  local author="$1"
  author=$(printf '%s' "$author" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [[ -z "$author" ]]; then
    return 1
  fi
  if [[ "$author" == *","* ]]; then
    normalize_slug "${author%%,*}"
    return
  fi
  local last
  last="${author##* }"
  normalize_slug "$last"
}

derive_name_from_filename() {
  local base="$1"
  local author year title

  # AuthorLastName_2024_Short-Title or AuthorLastName-2024-Short Title
  if [[ "$base" =~ ^(.+)[_-]([0-9]{4})[_-](.+)$ ]]; then
    author=$(author_lastname "${BASH_REMATCH[1]}" || normalize_slug "${BASH_REMATCH[1]}")
    year="${BASH_REMATCH[2]}"
    title=$(normalize_slug "${BASH_REMATCH[3]}")
    if [[ -n "$author" && -n "$title" ]]; then
      printf '%s_%s_%s.txt' "$author" "$year" "$title"
      return 0
    fi
  fi
  return 1
}

derive_name_from_pdfinfo() {
  local pdf="$1"
  local info author_raw title_raw year author title

  if ! command -v pdfinfo &>/dev/null; then
    return 1
  fi
  if ! info=$(pdfinfo "$pdf" 2>/dev/null); then
    return 1
  fi

  author_raw=$(printf '%s\n' "$info" | sed -n 's/^Author:[[:space:]]*//p' | head -n1)
  title_raw=$(printf '%s\n' "$info" | sed -n 's/^Title:[[:space:]]*//p' | head -n1)
  year=$(printf '%s\n' "$info" | sed -n 's/^CreationDate:[[:space:]]*D:\([0-9]\{4\}\).*/\1/p' | head -n1)
  if [[ -z "$year" ]]; then
    year=$(printf '%s\n' "$info" | sed -n 's/^ModDate:[[:space:]]*D:\([0-9]\{4\}\).*/\1/p' | head -n1)
  fi

  author=$(author_lastname "$author_raw" 2>/dev/null || true)
  title=$(normalize_slug "$title_raw")

  if [[ -z "$author" || -z "$title" ]]; then
    return 1
  fi
  if [[ -z "$year" ]]; then
    year="0000"
  fi
  printf '%s_%s_%s.txt' "$author" "$year" "$title"
}

derive_output_name() {
  local pdf="$1"
  local base stem out

  base=$(basename "$pdf")
  stem="${base%.pdf}"
  stem="${stem%.PDF}"

  if out=$(derive_name_from_filename "$stem" 2>/dev/null); then
    printf '%s' "$out"
    return
  fi
  if out=$(derive_name_from_pdfinfo "$pdf" 2>/dev/null); then
    printf '%s' "$out"
    return
  fi

  printf '%s.txt' "$(normalize_slug "$stem")"
}

prompt_dir() {
  # Write path into caller's variable (nameref). Do not use $(prompt_dir):
  # command substitution word-splits on spaces and breaks paths.
  local label="$1"
  local -n _out="$2"
  local path=""
  while true; do
    IFS= read -r -p "$label: " path
    # Windows copy/paste often adds CR; strip quotes user may wrap around path.
    path="${path//$'\r'/}"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"
    if [[ "$path" == \"*\" && "$path" == *\" ]]; then
      path="${path:1:${#path}-2}"
    elif [[ "$path" == \'*\' && "$path" == *\' ]]; then
      path="${path:1:${#path}-2}"
    fi
    path="${path/#\~/$HOME}"
    path="${path%/}"
    if [[ -z "$path" ]]; then
      echo "  (required)" >&2
      continue
    fi
    if [[ ! -d "$path" ]]; then
      echo "  Not a directory: $path" >&2
      continue
    fi
    _out="$path"
    return
  done
}

target_path() {
  # Re-runs overwrite the same output name (no _2, _3 suffixes).
  local dir="$1"
  local name="$2"
  printf '%s' "$dir/$name"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need_cmd pdftotext "Install with: sudo apt install poppler-utils"

  echo "PDF to text batch converter"
  echo "Enter Ubuntu WSL paths (e.g. /home/you/pdfs)"
  echo

  local location_source location_target
  prompt_dir "Source folder (PDFs)" location_source
  prompt_dir "Target folder (output .txt)" location_target

  mapfile -d '' -t pdfs < <(find "$location_source" -type f \( -iname '*.pdf' \) -print0 | sort -z)

  if [[ ${#pdfs[@]} -eq 0 ]]; then
    echo "No PDF files found under: $location_source"
    exit 0
  fi

  echo
  echo "Found ${#pdfs[@]} PDF(s). Converting..."
  echo

  local ok=0 fail=0 replaced=0 pdf out_name out_path rel label
  for pdf in "${pdfs[@]}"; do
    out_name=$(derive_output_name "$pdf")
    out_path=$(target_path "$location_target" "$out_name")
    rel="${pdf#"$location_source"/}"
    if [[ "$rel" == "$(basename "$pdf")" ]]; then
      label="$(basename "$pdf")"
    else
      label="$rel"
    fi

    if [[ -e "$out_path" ]]; then
      ((replaced++)) || true
      printf '  %s -> %s (replace)\n' "$label" "$(basename "$out_path")"
    else
      printf '  %s -> %s\n' "$label" "$(basename "$out_path")"
    fi
    if pdftotext "${PDFTOTEXT_OPTS[@]}" "$pdf" "$out_path"; then
      ((ok++)) || true
    else
      echo "    FAILED: $pdf" >&2
      ((fail++)) || true
    fi
  done

  echo
  echo "Done. Converted: $ok  Replaced: $replaced  Failed: $fail  Output: $location_target"
}

main "$@"
