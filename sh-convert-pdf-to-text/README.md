# Convert PDF to Text (WSL)

Some PDFs are not translated to plain text by Open WebUI. This script batch-converts them with `pdftotext` in Ubuntu WSL.

Re-running the script **overwrites** existing `.txt` files with the same output name (no `_2`, `_3` suffixes).

PDFs are discovered **recursively** in the source folder and all subdirectories.

## Requirements

- Ubuntu WSL
- [poppler-utils](https://poppler.freedesktop.org/): `sudo apt install poppler-utils`
- Optional: `pdfinfo` (same package) for metadata-based output names

## Usage

From WSL, in this folder:

```bash
chmod +x convert-pdf-to-text.sh
./convert-pdf-to-text.sh
```

The script prompts for:

1. **Source folder** — WSL path containing PDFs (searched recursively, including subfolders)
2. **Target folder** — WSL path where `.txt` files are written

Paths may contain spaces (paste the full path as one line; quotes are optional).

For each PDF it runs:

```bash
pdftotext -enc UTF-8 -nopgbrk input.pdf output.txt
```

## Output naming

Files are saved as `authorlastname_year_shorttitle.txt`, for example `smith_2023_machine_learning.txt`.

Naming is chosen in this order:

1. **Filename pattern** — `AuthorLastName_2024_Short-Title.pdf` (underscore or hyphen separators)
2. **PDF metadata** — Author, Title, and year from CreationDate/ModDate via `pdfinfo`
3. **Fallback** — sanitized lowercase stem of the PDF filename

If a target name already exists, it is replaced on the next run.

## Algorithm

```
location_source = prompt for WSL folder with PDFs
    build array of *.pdf under that folder (recursive)

location_target = prompt for WSL output folder

for each PDF in location_source:
    output_name = authorlastname_year_shorttitle.txt (see rules above)
    pdftotext -enc UTF-8 -nopgbrk <pdf> <location_target>/<output_name>
```

Script: `convert-pdf-to-text.sh`
