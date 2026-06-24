# Convert PDF to Text (WSL)

Batch-converts PDFs to UTF-8 text files using `pdftotext`, with intelligent OCR fallback for scanned/image-based PDFs. Includes conversion tracking to skip unchanged files on subsequent runs.

**Key Features:**
- Text extraction from text-based PDFs (fast)
- OCR fallback for scanned/image-based PDFs (automatic)
- Conversion tracking - skips unchanged PDFs on re-run
- Enhanced filename parsing for academic citations
- Environment variable support for automation

## Requirements

**Required:**
- Ubuntu WSL
- [poppler-utils](https://poppler.freedesktop.org/): `sudo apt install poppler-utils`
  - Provides: `pdftotext`, `pdfinfo`, `pdftoppm`

**Optional but recommended:**
- `jq`: `sudo apt install jq` — enables conversion tracking
- `tesseract-ocr`: `sudo apt install tesseract-ocr` — enables OCR for scanned PDFs

## Quick Start

### Option 1: Command-Line Parameters (Fastest)

```bash
cd /path/to/sh-convert-pdf-to-text
chmod +x convert-pdf-to-text.sh
./convert-pdf-to-text.sh SOURCE=/path/to/pdfs TARGET=/path/to/output
```

**For paths with spaces, quote the entire parameter:**
```bash
./convert-pdf-to-text.sh "SOURCE=/path/with spaces" "TARGET=/output/with spaces"
```

### Option 2: Environment Variables

Create `.env` file (see Configuration section below), then:
```bash
./convert-pdf-to-text.sh
# Uses paths from .env automatically
```

### Option 3: Interactive Prompts

```bash
./convert-pdf-to-text.sh
```

The script prompts for:
1. **Source folder** — WSL path containing PDFs (searched recursively)
2. **Target folder** — WSL path where `.txt` files are written

### Priority Order

The script uses this priority order for determining source/target paths:
1. **Command-line parameters** (highest priority)
2. **Environment variables** from `.env` file
3. **Interactive prompts** (fallback)

## Configuration (Optional)

For automation or custom settings, create a `.env` file:

```bash
cp example.env .env
# Edit .env with your paths
```

Available settings:
- `TRACKER_DIR` — where conversion tracking data is stored
- `PDF_SOURCE_DIR` — skip source folder prompt
- `PDF_TARGET_DIR` — skip target folder prompt
- `OCR_MIN_WORDS` — word threshold for OCR fallback (default: 10)
- `OCR_DPI` — image resolution for OCR (default: 300)
- `OCR_LANG` — Tesseract language code (default: "eng")

## How It Works

### Text Extraction Strategy

1. **Try pdftotext** (fast, for text-based PDFs)
2. **Check word count** — if < 10 words, assume scanned/image-based
3. **Fall back to OCR** — convert pages to images, run Tesseract OCR

Example output:
```
  Articles/Paper.pdf -> paper_2024_title.txt
    Low text content (0 words), trying OCR...
    OCR extracted 27593 words
```

### Conversion Tracking

If `jq` is installed, the script tracks converted PDFs in `temp/conversion-tracker.json`.

**First run:**
```
Done. Converted: 5  Skipped: 0  Replaced: 0  Failed: 0  OCR: 1
```

**Second run (unchanged PDFs):**
```
Done. Converted: 0  Skipped: 5  Replaced: 0  Failed: 0  OCR: 0
```

The tracker stores:
- Source PDF path and modification timestamp
- Output file path
- Conversion timestamp and method used

**Skip logic:**
- Skip if: tracker entry exists + output file exists + PDF unchanged
- Convert if: no entry OR output missing OR PDF modified

To reset tracking: `rm temp/conversion-tracker.json`

### Output Naming

Files are saved as `authorlastname_year_title.txt`, for example:
- `smith_2024_machine_learning.txt`
- `jones_2023_deep_learning_survey.txt`

**Filename Parsing** (tried first):

| Input PDF | Output TXT |
|-----------|-----------|
| `Smith (2024) - Title.pdf` | `smith_2024_title.txt` |
| `Author1 and Author2 (2023) - Title.pdf` | `author1_2023_title.txt` |
| `Jones, et al. (2022) - Paper.pdf` | `jones_2022_paper.txt` |
| `LastName_2021_Title.pdf` | `lastname_2021_title.txt` |
| `Author - Title.pdf` | `author_0000_title.txt` |

Supported patterns:
- Academic citations: `Author (YEAR) - Title`
- Multiple authors: `Author1, Author2, Author3 (YEAR) - Title`
- "et al." format: `Author, et al. (YEAR) - Title`
- "and" separator: `Author1 and Author2 (YEAR) - Title`
- Underscore format: `Author_YEAR_Title`
- Simple dash: `Author - Title` (year defaults to 0000)

**Fallback** (if filename doesn't match patterns):
1. **PDF metadata** — Author, Title, year from `pdfinfo`
2. **Sanitized filename** — lowercase, underscores, no special chars

### Processing

PDFs are discovered **recursively** in the source folder and all subdirectories.

Re-running the script:
- **Skips unchanged PDFs** (if tracking enabled)
- **Overwrites output files** for modified PDFs (no `_2`, `_3` suffixes)

## Example Session

```bash
$ ./convert-pdf-to-text.sh
PDF to text batch converter (tracking enabled)
Enter Ubuntu WSL paths (e.g. /home/you/pdfs)

Source folder (PDFs): /home/user/documents/papers
Target folder (output .txt): /home/user/documents/papers-txt

Found 5 PDF(s). Converting...

  Ashcraft, et al. (2009) - Study.pdf -> ashcraft_2009_study.txt
  Putnam, et al. (2001) - Handbook.pdf -> putnam_2001_handbook.txt
    Low text content (0 words), trying OCR...
    OCR extracted 27593 words
  [... more files ...]

Done. Converted: 5  Skipped: 0  Replaced: 0  Failed: 0  OCR: 1
```

## Algorithm

```
Load .env configuration (if exists)
Load conversion tracker (if jq available)

location_source = prompt for WSL folder with PDFs (or use PDF_SOURCE_DIR)
    build array of *.pdf under that folder (recursive)

location_target = prompt for WSL output folder (or use PDF_TARGET_DIR)

for each PDF in location_source:
    output_name = derive from filename patterns or metadata
    
    if tracking enabled and PDF unchanged and output exists:
        skip (print "skipped - unchanged")
        continue
    
    # Try text extraction
    pdftotext -enc UTF-8 -nopgbrk <pdf> <output>
    
    if word_count(output) < OCR_MIN_WORDS:
        # OCR fallback for scanned PDFs
        pdftoppm -r OCR_DPI -png <pdf> <tmpdir>/*.png
        for each page image:
            tesseract <image> stdout -l OCR_LANG >> <output>
    
    update_tracker(pdf, output, method)

save_tracker()
print summary: Converted, Skipped, Replaced, Failed, OCR count
```

## Troubleshooting

### Tracking disabled
**Message:** `(tracking disabled - install jq to enable)`

**Solution:** `sudo apt install jq`

### OCR not working
**Message:** `OCR skipped: tesseract not installed`

**Solution:** `sudo apt install tesseract-ocr`

For non-English PDFs:
```bash
sudo apt install tesseract-ocr-spa  # Spanish
sudo apt install tesseract-ocr-fra  # French
# Set OCR_LANG="spa" in .env
```

### Line ending errors
**Message:** `$'\r': command not found`

**Cause:** Windows CRLF line endings in `.env`

**Solution:** The script auto-strips CRLF when loading `.env`. If error persists:
```bash
dos2unix .env  # or
sed -i 's/\r$//' .env
```

### Slow conversions
- **Text-based PDFs:** Fast (< 1 second each)
- **Image-based PDFs (OCR):** Slow (3-10 seconds per page)

To speed up OCR (with quality tradeoff), reduce DPI in `.env`:
```bash
OCR_DPI=150  # Faster but lower quality
```

## Files

- `convert-pdf-to-text.sh` — Main script
- `example.env` — Configuration template
- `.env` — Your configuration (copy from example.env)
- `temp/conversion-tracker.json` — Tracking database (auto-created)
- `.claude/skills/run-pdf-converter/` — Skill for automated testing
