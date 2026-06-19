#!/usr/bin/env bash
# Batch-convert PDFs to UTF-8 text via pdftotext (poppler-utils).
# For image-based PDFs, falls back to OCR via Tesseract.
# Run in Ubuntu WSL: bash convert-pdf-to-text.sh

set -euo pipefail

# Load environment variables if .env exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # Strip Windows line endings and source the file
  # shellcheck disable=SC1090,SC1091
  source <(tr -d '\r' < "$SCRIPT_DIR/.env")
fi

readonly PDFTOTEXT_OPTS=(-enc UTF-8 -nopgbrk)
readonly OCR_MIN_WORDS="${OCR_MIN_WORDS:-10}"  # Threshold: if pdftotext yields < N words, try OCR
readonly OCR_DPI="${OCR_DPI:-300}"             # DPI for OCR conversion
readonly OCR_LANG="${OCR_LANG:-eng}"           # Tesseract language
readonly TRACKER_DIR="${TRACKER_DIR:-$SCRIPT_DIR/temp}"
readonly TRACKER_FILE="$TRACKER_DIR/conversion-tracker.json"

# Global associative array for tracker data
declare -A TRACKER

usage() {
  cat <<'EOF'
Usage: convert-pdf-to-text.sh

Prompts for source and target WSL folder paths, then converts every PDF
in the source folder (including subdirectories) to .txt files in the target folder.

Output names look like: authorlastname_year_shorttitle.txt
  - Parsed from filenames like AuthorLastName_2024_Short-Title.pdf
  - Or derived from PDF metadata (pdfinfo) when available
  - Otherwise: sanitized lowercase stem of the PDF name

Text extraction strategy:
  1. Try pdftotext (fast, for text-based PDFs)
  2. If result has < 10 words, assume scanned/image-based PDF
  3. Fall back to OCR via Tesseract (slower, for image-based PDFs)

Requires: pdftotext (install: sudo apt install poppler-utils)
Optional: pdfinfo for metadata-based naming
          tesseract-ocr, pdftoppm for OCR fallback on scanned PDFs
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
  local author year title first_author

  # Pattern 1: Citation style - "Author(s) (YEAR) - Title"
  # Handles: "Auer (2011) - Title"
  #          "Author and Author (2011) - Title"
  #          "Author, Author, Author (2011) - Title"
  #          "Author, et al. (2011) - Title"
  if [[ "$base" =~ ^(.+)[[:space:]]*\(([0-9]{4})\)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
    author="${BASH_REMATCH[1]}"
    year="${BASH_REMATCH[2]}"
    title=$(normalize_slug "${BASH_REMATCH[3]}")

    # Extract first author only from multiple author formats
    first_author="$author"

    # Remove "et al." variants
    first_author="${first_author//, et al.*/}"
    first_author="${first_author// et al.*/}"

    # For "Author1 and Author2" format, take first author
    if [[ "$first_author" == *" and "* ]]; then
      first_author="${first_author%% and *}"
    fi

    # For "Author1, Author2, Author3" format, take first author
    # Only split on comma if followed by space and capital letter (next author)
    if [[ "$first_author" =~ ^([^,]+),[[:space:]]*[A-Z] ]]; then
      first_author="${BASH_REMATCH[1]}"
    fi

    first_author=$(author_lastname "$first_author" || normalize_slug "$first_author")

    if [[ -n "$first_author" && -n "$title" ]]; then
      printf '%s_%s_%s.txt' "$first_author" "$year" "$title"
      return 0
    fi
  fi

  # Pattern 2: AuthorLastName_2024_Short-Title or AuthorLastName-2024-Short Title
  if [[ "$base" =~ ^(.+)[_-]([0-9]{4})[_-](.+)$ ]]; then
    author=$(author_lastname "${BASH_REMATCH[1]}" || normalize_slug "${BASH_REMATCH[1]}")
    year="${BASH_REMATCH[2]}"
    title=$(normalize_slug "${BASH_REMATCH[3]}")
    if [[ -n "$author" && -n "$title" ]]; then
      printf '%s_%s_%s.txt' "$author" "$year" "$title"
      return 0
    fi
  fi

  # Pattern 3: AuthorLastName - Title or AuthorLastName_Title (no year)
  if [[ "$base" =~ ^(.+)[_-](.+)$ ]]; then
    author=$(author_lastname "${BASH_REMATCH[1]}" || normalize_slug "${BASH_REMATCH[1]}")
    title=$(normalize_slug "${BASH_REMATCH[2]}")
    if [[ -n "$author" && -n "$title" ]]; then
      printf '%s_0000_%s.txt' "$author" "$title"
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

word_count() {
  # Count words in a file (rough heuristic for "is there real text?").
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo 0
    return
  fi
  wc -w < "$file" 2>/dev/null || echo 0
}

ocr_pdf() {
  # OCR a PDF via Tesseract: convert PDF pages to images, OCR each, combine.
  local pdf="$1"
  local out="$2"
  local tmpdir

  if ! command -v tesseract &>/dev/null; then
    echo "    OCR skipped: tesseract not installed" >&2
    return 1
  fi
  if ! command -v pdftoppm &>/dev/null; then
    echo "    OCR skipped: pdftoppm not installed (poppler-utils)" >&2
    return 1
  fi

  tmpdir=$(mktemp -d)
  # Expand $tmpdir now when setting trap, not when it fires
  trap "rm -rf '$tmpdir'" RETURN

  # Convert PDF to images (configurable DPI for OCR quality)
  if ! pdftoppm -r "$OCR_DPI" -png "$pdf" "$tmpdir/page" &>/dev/null; then
    echo "    OCR failed: pdftoppm conversion error" >&2
    return 1
  fi

  # OCR each page image
  local combined="$tmpdir/combined.txt"
  : > "$combined"

  local page_count=0
  for img in "$tmpdir"/page-*.png; do
    [[ -f "$img" ]] || continue
    ((page_count++)) || true
    if ! tesseract "$img" stdout -l "$OCR_LANG" 2>/dev/null >> "$combined"; then
      echo "    OCR warning: page $page_count failed" >&2
    fi
  done

  if [[ $page_count -eq 0 ]]; then
    echo "    OCR failed: no pages extracted" >&2
    return 1
  fi

  # Write combined OCR result
  if [[ -s "$combined" ]]; then
    cp "$combined" "$out"
    return 0
  else
    echo "    OCR failed: empty result" >&2
    return 1
  fi
}

load_tracker() {
  # Load tracker JSON into TRACKER associative array
  if ! command -v jq &>/dev/null; then
    return 1  # jq not available, tracking disabled
  fi

  if [[ ! -f "$TRACKER_FILE" ]]; then
    return 0  # No tracker yet, start fresh
  fi

  # Validate JSON and load
  if ! jq empty "$TRACKER_FILE" 2>/dev/null; then
    echo "Warning: tracker file corrupted, starting fresh" >&2
    mv "$TRACKER_FILE" "$TRACKER_FILE.backup.$(date +%s)" 2>/dev/null || true
    return 0
  fi

  # Read tracker data (format: "pdf_path|mtime|output_path|method")
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    TRACKER["$line"]=1
  done < <(jq -r 'to_entries[] | "\(.key)|\(.value.source_mtime)|\(.value.output_path)|\(.value.method)"' "$TRACKER_FILE" 2>/dev/null || true)
}

save_tracker() {
  # Save TRACKER data to JSON file
  if ! command -v jq &>/dev/null; then
    return 0  # jq not available, skip saving
  fi

  mkdir -p "$TRACKER_DIR" 2>/dev/null || true

  local json="{}"
  local pdf mtime output method key data
  for key in "${!TRACKER[@]}"; do
    IFS='|' read -r pdf mtime output method <<< "$key"
    json=$(echo "$json" | jq --arg pdf "$pdf" \
                              --arg mtime "$mtime" \
                              --arg output "$output" \
                              --arg method "$method" \
                              --arg ts "$(date +%s)" \
      '.[$pdf] = {source_mtime: $mtime, output_path: $output, converted_at: $ts, method: $method}')
  done

  if ! echo "$json" | jq . > "$TRACKER_FILE" 2>/dev/null; then
    echo "Warning: failed to save tracker" >&2
  fi
}

should_convert() {
  # Check if PDF needs conversion
  # Returns 0 (true) if should convert, 1 (false) if should skip
  local pdf="$1"
  local output="$2"
  local current_mtime key

  if ! command -v jq &>/dev/null; then
    return 0  # No tracking, always convert
  fi

  current_mtime=$(stat -c %Y "$pdf" 2>/dev/null || echo "0")

  # Check all tracker entries for this PDF
  for key in "${!TRACKER[@]}"; do
    IFS='|' read -r tracked_pdf tracked_mtime tracked_output tracked_method <<< "$key"
    if [[ "$tracked_pdf" == "$pdf" ]]; then
      # Entry exists - check if output exists and mtime matches
      if [[ -f "$tracked_output" && "$current_mtime" == "$tracked_mtime" ]]; then
        return 1  # Skip conversion
      fi
      # Output missing or mtime changed - need to convert
      return 0
    fi
  done

  # No entry found - need to convert
  return 0
}

update_tracker() {
  # Record successful conversion
  local pdf="$1"
  local output="$2"
  local method="$3"
  local mtime key

  if ! command -v jq &>/dev/null; then
    return 0  # No tracking
  fi

  mtime=$(stat -c %Y "$pdf" 2>/dev/null || echo "0")
  key="$pdf|$mtime|$output|$method"
  TRACKER["$key"]=1
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  need_cmd pdftotext "Install with: sudo apt install poppler-utils"

  # Load tracker
  if command -v jq &>/dev/null; then
    load_tracker
    echo "PDF to text batch converter (tracking enabled)"
  else
    echo "PDF to text batch converter (tracking disabled - install jq to enable)"
  fi
  echo "Enter Ubuntu WSL paths (e.g. /home/you/pdfs)"
  echo

  local location_source location_target

  # Use environment variables if set, otherwise prompt
  if [[ -n "${PDF_SOURCE_DIR:-}" ]]; then
    location_source="$PDF_SOURCE_DIR"
    echo "Source folder (from .env): $location_source"
  else
    prompt_dir "Source folder (PDFs)" location_source
  fi

  if [[ -n "${PDF_TARGET_DIR:-}" ]]; then
    location_target="$PDF_TARGET_DIR"
    echo "Target folder (from .env): $location_target"
  else
    prompt_dir "Target folder (output .txt)" location_target
  fi

  mapfile -d '' -t pdfs < <(find "$location_source" -type f \( -iname '*.pdf' \) -print0 | sort -z)

  if [[ ${#pdfs[@]} -eq 0 ]]; then
    echo "No PDF files found under: $location_source"
    exit 0
  fi

  echo
  echo "Found ${#pdfs[@]} PDF(s). Converting..."
  echo

  local ok=0 fail=0 replaced=0 skipped=0 ocr_count=0 pdf out_name out_path rel label wc method
  for pdf in "${pdfs[@]}"; do
    out_name=$(derive_output_name "$pdf")
    out_path=$(target_path "$location_target" "$out_name")
    rel="${pdf#"$location_source"/}"
    if [[ "$rel" == "$(basename "$pdf")" ]]; then
      label="$(basename "$pdf")"
    else
      label="$rel"
    fi

    # Check if conversion needed
    if ! should_convert "$pdf" "$out_path"; then
      ((skipped++)) || true
      printf '  %s -> %s (skipped - unchanged)\n' "$label" "$(basename "$out_path")"
      continue
    fi

    if [[ -e "$out_path" ]]; then
      ((replaced++)) || true
      printf '  %s -> %s (replace)\n' "$label" "$(basename "$out_path")"
    else
      printf '  %s -> %s\n' "$label" "$(basename "$out_path")"
    fi

    method="pdftotext"
    # Try pdftotext first
    if pdftotext "${PDFTOTEXT_OPTS[@]}" "$pdf" "$out_path" 2>/dev/null; then
      wc=$(word_count "$out_path")
      if [[ $wc -ge $OCR_MIN_WORDS ]]; then
        ((ok++)) || true
        update_tracker "$pdf" "$out_path" "$method"
        continue
      fi
      # Too few words — likely scanned/image-based PDF
      echo "    Low text content ($wc words), trying OCR..." >&2
      method="ocr"
      if ocr_pdf "$pdf" "$out_path"; then
        wc=$(word_count "$out_path")
        echo "    OCR extracted $wc words" >&2
        ((ok++)) || true
        ((ocr_count++)) || true
        update_tracker "$pdf" "$out_path" "$method"
      else
        echo "    FAILED: both pdftotext and OCR failed" >&2
        ((fail++)) || true
      fi
    else
      # pdftotext failed — try OCR directly
      echo "    pdftotext failed, trying OCR..." >&2
      method="ocr"
      if ocr_pdf "$pdf" "$out_path"; then
        wc=$(word_count "$out_path")
        echo "    OCR extracted $wc words" >&2
        ((ok++)) || true
        ((ocr_count++)) || true
        update_tracker "$pdf" "$out_path" "$method"
      else
        echo "    FAILED: $pdf" >&2
        ((fail++)) || true
      fi
    fi
  done

  # Save tracker
  save_tracker

  echo
  echo "Done. Converted: $ok  Skipped: $skipped  Replaced: $replaced  Failed: $fail  OCR: $ocr_count  Output: $location_target"
}

main "$@"
