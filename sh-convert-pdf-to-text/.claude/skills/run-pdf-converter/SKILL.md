---
name: run-pdf-converter
description: Run the PDF to text batch converter CLI tool, test conversion with tracking and OCR support
---

# Run: PDF to Text Converter

Batch converter that extracts text from PDFs using pdftotext, with OCR fallback for scanned/image-based PDFs. Includes conversion tracking to skip unchanged files on subsequent runs.

**This is a WSL/Ubuntu script.** Run it in Ubuntu WSL bash, not Windows PowerShell or Git Bash.

## Prerequisites

```bash
# Install in Ubuntu WSL
sudo apt-get update
sudo apt-get install -y poppler-utils jq tesseract-ocr
```

**Required:**
- `poppler-utils` - provides `pdftotext`, `pdfinfo`, `pdftoppm`
- Standard Unix tools: `stat`, `find`, `wc`

**Optional but recommended:**
- `jq` - enables conversion tracking (skip unchanged PDFs)
- `tesseract-ocr` - enables OCR for scanned/image-based PDFs

## Setup

1. **Copy environment template:**
   ```bash
   cd /path/to/sh-convert-pdf-to-text
   cp example.env .env
   ```

2. **Edit `.env` with your paths** (or leave commented to use prompts):
   ```bash
   # Example paths - adjust to your needs
   TRACKER_DIR="/path/to/sh-convert-pdf-to-text/temp"
   PDF_SOURCE_DIR="/path/to/your/pdf-files"
   PDF_TARGET_DIR="/path/to/your/output-txt-files"
   OCR_MIN_WORDS=10
   OCR_DPI=300
   OCR_LANG="eng"
   ```

3. **Ensure script is executable:**
   ```bash
   chmod +x convert-pdf-to-text.sh
   ```

## Run (Command-Line Parameters - Recommended)

Pass source and target paths directly as parameters:

```bash
cd /path/to/sh-convert-pdf-to-text
./convert-pdf-to-text.sh SOURCE=/path/to/pdfs TARGET=/path/to/output
```

**For paths with spaces, quote the entire parameter:**
```bash
./convert-pdf-to-text.sh "SOURCE=/path/with spaces/pdfs" "TARGET=/output/with spaces"
```

**Partial parameters** (combine with other methods):
```bash
# Use SOURCE from command-line, TARGET from .env or prompt
./convert-pdf-to-text.sh SOURCE=/path/to/pdfs

# Use TARGET from command-line, SOURCE from .env or prompt  
./convert-pdf-to-text.sh TARGET=/path/to/output
```

**Output:**
```
PDF to text batch converter (tracking enabled)
Source folder (from command-line): /path/to/pdfs
Target folder (from command-line): /path/to/output
Found 5 PDF(s). Converting...
  Articles/Smith (2024) - Title.pdf -> smith_2024_title.txt
  ...
Done. Converted: 5  Skipped: 0  Replaced: 0  Failed: 0  OCR: 1
```

## Run (Environment Variables)

If `.env` has `PDF_SOURCE_DIR` and `PDF_TARGET_DIR` set, the script uses them automatically:

```bash
./convert-pdf-to-text.sh
# No prompts - uses paths from .env
```

**Note:** Command-line parameters override `.env` values.

## Run (Interactive Mode)

Without parameters or `.env` configuration, the script prompts interactively:

```bash
./convert-pdf-to-text.sh
```

The script will prompt for:
1. Source folder containing PDFs (supports subdirectories)
2. Target folder for output .txt files

## Priority Order

The script determines paths using this priority (highest to lowest):
1. **Command-line parameters** (`SOURCE=` and `TARGET=`)
2. **Environment variables** (from `.env` file)
3. **Interactive prompts** (fallback)

## How It Works

### Filename Parsing

The script intelligently names output files based on PDF filenames:

| Input PDF | Output TXT |
|-----------|-----------|
| `Smith (2024) - Article Title.pdf` | `smith_2024_article_title.txt` |
| `Author1 and Author2 (2023) - Title.pdf` | `author1_2023_title.txt` |
| `Jones, et al. (2022) - Paper.pdf` | `jones_2022_paper.txt` |
| `LastName_2021_Title.pdf` | `lastname_2021_title.txt` |
| `Author - Simple Title.pdf` | `author_0000_simple_title.txt` |

Falls back to PDF metadata (Author/Title/Date) if filename doesn't match patterns.

### Text Extraction Strategy

1. **Try pdftotext** (fast, for text-based PDFs)
2. **Check word count** - if < 10 words, assume scanned/image-based
3. **Fall back to OCR** - convert PDF to images, run Tesseract OCR

### Tracking System

**Tracker location:** `temp/conversion-tracker.json`

**Requires jq.** The tracker stores:
```json
{
  "/full/path/to/source.pdf": {
    "source_mtime": "1718812345",
    "output_path": "/full/path/to/output.txt",
    "converted_at": "1718812346",
    "method": "ocr"
  }
}
```

**Skip logic:**
- Skip if: tracker entry exists + output file exists + source mtime unchanged
- Convert if: no entry OR output missing OR source modified

**Test tracking:**
```bash
# First run - converts all
./convert-pdf-to-text.sh
# Output: Converted: 5  Skipped: 0

# Second run - skips all
./convert-pdf-to-text.sh
# Output: Converted: 0  Skipped: 5

# Touch one file to simulate edit
touch "/path/to/one.pdf"
./convert-pdf-to-text.sh
# Output: Converted: 1  Skipped: 4
```

**View tracker:**
```bash
cat temp/conversion-tracker.json | jq .
```

**Reset tracker:**
```bash
rm temp/conversion-tracker.json
```

## Smoke Test

Run automated tests:

```bash
cd /path/to/sh-convert-pdf-to-text
./.claude/skills/run-pdf-converter/smoke.sh
```

The smoke test:
- Checks all prerequisites
- Creates a test PDF (if pdflatex available)
- Runs conversion
- Verifies output and tracking
- Tests filename parsing patterns

## Gotchas

### Windows Line Endings in .env
**Problem:** `.env` file has CRLF line endings, causing `$'\r': command not found`.

**Solution:** The script automatically strips `\r` when loading `.env`:
```bash
source <(tr -d '\r' < "$SCRIPT_DIR/.env")
```

If you still see errors, manually convert:
```bash
dos2unix .env  # or
sed -i 's/\r$//' .env
```

### Tracking Disabled
**Symptom:** `(tracking disabled - install jq to enable)`

**Solution:** Install jq:
```bash
sudo apt-get install -y jq
```

### OCR Disabled
**Symptom:** `OCR skipped: tesseract not installed`

**Solution:** Install Tesseract:
```bash
sudo apt-get install -y tesseract-ocr
```

For non-English PDFs, install language packs:
```bash
sudo apt-get install tesseract-ocr-spa  # Spanish
sudo apt-get install tesseract-ocr-fra  # French
# Then set OCR_LANG="spa" in .env
```

### tmpdir Unbound Variable Error
**Symptom:** `tmpdir: unbound variable` after successful OCR.

**Cause:** Trap cleanup tries to reference out-of-scope variable with `set -u`.

**Fixed in current version** - trap now expands `$tmpdir` at trap-set time:
```bash
trap "rm -rf '$tmpdir'" RETURN  # not 'rm -rf "$tmpdir"'
```

### Scanned PDF Shows 0 Words
**Expected behavior.** The script detects this and automatically falls back to OCR:
```
  Low text content (0 words), trying OCR...
  OCR extracted 27593 words
```

If OCR isn't installed, the conversion fails. Install tesseract-ocr.

### Output Names Unknown_0000_Unknown
**Cause:** PDF filename doesn't match expected patterns and has no metadata.

**Original filename was likely:** `Deetz - Organizational Communication.pdf` or similar.

**Fixed in current version** - now supports:
- Citation style: `Author (YEAR) - Title`
- Multiple authors: `A, B, C (YEAR) - Title` or `A and B (YEAR) - Title`
- No year: `Author - Title` → `author_0000_title.txt`

## Troubleshooting

### Error: pdftotext: command not found
Install poppler-utils:
```bash
sudo apt-get install -y poppler-utils
```

### Error: jq: command not found (warnings only)
Tracking is optional. Install for better performance:
```bash
sudo apt-get install -y jq
```

### Error: Permission denied
Make script executable:
```bash
chmod +x convert-pdf-to-text.sh
```

### Output directory doesn't exist
The script doesn't create the output directory. Create it first:
```bash
mkdir -p "/path/to/output"
```

### Conversion is slow
- **Text-based PDFs:** Fast (< 1 second each)
- **Image-based PDFs (OCR):** Slow (3-10 seconds per page)

OCR processes at 300 DPI by default. Lower `OCR_DPI` in `.env` for faster (but less accurate) conversion:
```bash
OCR_DPI=150  # Faster but lower quality
```

### Tracker file corrupted
The script auto-backs up corrupted trackers:
```bash
# Manual cleanup if needed
rm temp/conversion-tracker.json
rm temp/*.backup.*
```

## Example Session

```bash
$ cd /path/to/sh-convert-pdf-to-text
$ ./convert-pdf-to-text.sh
PDF to text batch converter (tracking enabled)
Enter Ubuntu WSL paths (e.g. /home/you/pdfs)

Source folder (PDFs): /home/user/documents/research-papers
Target folder (output .txt): /home/user/documents/research-papers-txt

Found 5 PDF(s). Converting...

  Articles/Ashcraft, et al. (2009) - Constitutional amendments 1.pdf -> ashcraft_2009_constitutional_amendments_1.txt
  Articles/Putnam, et al. (2001) - Handbook.pdf -> putnam_2001_handbook.txt
    Low text content (0 words), trying OCR...
    OCR extracted 27593 words
  Articles/Ma (2022) - Communication strategies.pdf -> ma_2022_communication_strategies.txt
  Articles/Osburn (2023) - Vendors.pdf -> osburn_2023_vendors.txt
  Articles/Walden, et al. (2017) - Employee communication.pdf -> walden_2017_employee_communication.txt

Done. Converted: 5  Skipped: 0  Replaced: 0  Failed: 0  OCR: 1  Output: /home/user/documents/research-papers-txt

$ # Run again - everything skipped
$ ./convert-pdf-to-text.sh
[same prompts]
Found 5 PDF(s). Converting...

  Articles/Ashcraft, et al. (2009) - Constitutional amendments 1.pdf -> ashcraft_2009_constitutional_amendments_1.txt (skipped - unchanged)
  Articles/Putnam, et al. (2001) - Handbook.pdf -> putnam_2001_handbook.txt (skipped - unchanged)
  Articles/Ma (2022) - Communication strategies.pdf -> ma_2022_communication_strategies.txt (skipped - unchanged)
  Articles/Osburn (2023) - Vendors.pdf -> osburn_2023_vendors.txt (skipped - unchanged)
  Articles/Walden, et al. (2017) - Employee communication.pdf -> walden_2017_employee_communication.txt (skipped - unchanged)

Done. Converted: 0  Skipped: 5  Replaced: 0  Failed: 0  OCR: 0  Output: [...]
```
