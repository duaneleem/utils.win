# Obsidian and Open WebUI Sync

Sync files from one or more local folders (for example separate Obsidian course folders) into Open WebUI **Workspace → Knowledge** collections so you can use them for RAG in chats.

## What it does

- Reads **targets** from `targets.tsv`: each row is a **watch folder** plus a **Knowledge collection id** from Open WebUI (so `course1`, `course2`, etc. can each map to its own Knowledge base).
- Recursively finds files under each watch folder, filtered by extension (configurable).
- For each file not yet recorded for that Knowledge target, uploads it and attaches it to that collection.
- Appends each successfully processed **full file path** to a **per–Knowledge-id** tracker file so reruns skip duplicates and identical names in two courses do not collide.

## Open WebUI API (two steps)

Open WebUI uses a **file upload** then a **attach to knowledge** call (Bearer auth). Base URL example (yours may differ):

`http://192.168.50.218:13010`

1. **Upload** — `POST {BASE_URL}/api/v1/files/`  
   Headers: `Authorization: Bearer <API_KEY>`, `Accept: application/json`  
   Body: multipart form field `file` (the file bytes).  
   Response JSON includes the new file id (commonly `id`; the script also accepts `file_id`).

2. **Attach to Knowledge** — `POST {BASE_URL}/api/v1/knowledge/{knowledge_id}/file/add`  
   Headers: `Authorization: Bearer <API_KEY>`, `Content-Type: application/json`  
   Body: `{"file_id":"<id>"}` (same value returned from step 1).

Interactive docs on your instance: `{BASE_URL}/api/v1/docs`.

## Setup

1. Copy [`.env.sample`](.env.sample) to **`.env`** in this folder and set **`API_KEY`**. In Open WebUI, keys are created under **Settings → Account** in the **API Keys** section. If you do not see that section, an admin must turn on **Enable API Keys** under **Admin Panel → Settings → General → Authentication**, and non-admin accounts need the **API Keys** feature permission in **Admin Panel → Users → Groups**. See [API Keys (Open WebUI docs)](https://docs.openwebui.com/features/authentication-access/api-keys). Adjust **`BASE_URL`** if needed.
2. Copy [`targets.sample.tsv`](targets.sample.tsv) to **`targets.tsv`** (same folder). **`targets.sample.tsv` stays generic (placeholders only);** put your real watch folders and Knowledge ids in **`targets.tsv`** (gitignored). The Knowledge id is the last segment of the Knowledge URL (`…/workspace/knowledge/<id>`). Create one Knowledge per course in the UI if you want separate collections. **Columns are separated by a single tab; spaces in folder paths do not require quotes** (only avoid tab characters inside a path).

## Tracker files

For each `knowledge_id` in `targets.tsv`, the script writes under the **`trackers`** subfolder:

`trackers/uploaded_files_<knowledge_id>.txt`

Each **non-empty** line is:

`full_path_to_file` **TAB** `LastWriteTimeUtc_ticks`

(`…ticks` is the Windows file **last-write time in UTC**, as .NET `DateTime` ticks, so the script can tell when a note was saved and **upload again**.)

- **Legacy location:** If an older tracker still lives next to the script as `uploaded_files_<id>.txt`, it is **moved** into `trackers/` the first time that target runs.
- **Legacy:** older trackers used **path-only** lines (no tab). Those are still read on load: the script records each file’s **current** last-write time as the baseline and rewrites the file in the new format on the next run (no extra upload if nothing changed since then).
- Lines whose path **no longer exists** on disk are dropped the next time that target’s tracker is saved.
- To **force** a re-upload even when the timestamp did not change, temporarily change the file’s modified time (e.g. re-save in the editor) or remove that file’s line from the tracker.

**Note:** Re-uploading adds **another** copy in Open WebUI unless you remove the old document there; this tool does not delete remote files.

## Run

Double-click **`sync-obsidian.bat`** or from a terminal:

```bat
cd /d "d:\duaneleem\Code\utils.win\sync-obsidian"
sync-obsidian.bat
```

Requires **Windows** with **PowerShell 5.1+**. Uploads use **.NET `HttpClient`** (not `curl`) so paths with **Unicode / emoji** in file names open reliably; the attach step uses the same client.

If you **double-click** the `.bat` and something fails, the window **stays open** with `Press any key to continue . . .` so you can read the error.

### If some files still fail

| Symptom | Likely cause |
|--------|----------------|
| Warning says **cannot open file** | Permission denied, file exclusively locked (close Obsidian/PDF reader on that file), or rare path issues. |
| **HTTP 400** on upload | Open WebUI rejected the request: **file too large**, unsupported type, ingestion limits, or server-side validation. Check the warning line for the response body; confirm limits in your Open WebUI / RAG settings and logs. |
| **`[ERROR: Error uploading file]`** (no extra detail) | Same as upload 400: **logs**, **disk space**, **proxy body limits**, and **Documents** max upload settings. The script now sends a correct **Content-Type** per extension and a longer default **HTTP timeout** (see `.env.sample` `HTTP_TIMEOUT_SECONDS`). If **server logs** show **`OSError: [Errno 24] Too many open files`** during `POST /api/v1/files/`, the process hit the **open file descriptor limit** (often under **Docker**’s default `nofile`). Raise **`ulimits`** (Docker `nofile`) on the Open WebUI service and optionally set **`UPLOAD_DELAY_MS`** in `.env` to pace uploads. |
| **HTTP 400** on attach, message about **empty** content | The server often means **extracted text was empty** (common with **image-only / scanned PDFs** without OCR, encrypted PDFs, or extractor bugs)—not that your file is 0 bytes on disk. Try OCR’d PDFs, `.md` exports, or Open WebUI’s [RAG troubleshooting](https://docs.openwebui.com/troubleshooting/rag/). |
| **Server log:** `cannot reshape array` … `PyPDFParser` / `extract_images_from_page` | **LangChain PyPDF** failed while decoding an **embedded image** on a page (dimensions vs raw bytes mismatch: odd compression, CMYK/JPEG quirks, or slightly corrupt streams). Re-**print** or **re-export** the PDF (Acrobat, “Microsoft Print to PDF”), or try a **newer Open WebUI** release. Often the same PDF still yields **no extractable text** afterward, so you may see **empty content** on attach. |
| **HTTP 400** duplicate on **attach** | Same content is already in that Knowledge collection. The script treats this as **success**: it updates the local tracker so the next run does not keep re-uploading. (Each failed run may still have created an extra file in Open WebUI’s file list; you can clean orphans in the UI if needed.) |
| **`metadatas` / MetadataValue** on attach | Open WebUI / vector DB bug with some files or versions. Try **upgrading Open WebUI**, check **server logs**, or rename notes that use **emoji** in the file name to test. |
| **HTTP 400** … **parsing the body** (upload) | Often **not** Open WebUI app logic: the **HTTP request was cut off or malformed** (very common when a **reverse proxy** max body size is smaller than the PDF). Increase **nginx `client_max_body_size`** (or Traefik/Caddy equivalent), then retry. Compare with uploading the same file in the **browser UI**. |
| **Server log:** `Too many open files` / **Errno 24** on upload | The Open WebUI (Python) process ran out of **file descriptors**. Typical fix: in **`docker-compose.yml`**, on the Open WebUI service add `ulimits: { nofile: { soft: 65535, hard: 65535 } }` (or similar), then `docker compose up -d`. Optionally **`UPLOAD_DELAY_MS`** in `.env` (e.g. `150`) so the script sleeps briefly after each upload/attach. |
| **HTTP 4xx/5xx** on attach (other) | Knowledge id wrong, permission, or transient server error; response body in the warning helps. |


To capture output in a terminal you already have open (so nothing flashes away), run PowerShell directly:

```powershell
Set-Location "d:\duaneleem\Code\utils.win\sync-obsidian"
.\sync-obsidian.ps1
```

## Caveats

- **Edits:** After a successful sync, the tracker stores each file’s **last modified time (UTC)**. If you edit and save the file so its timestamp **changes**, the next run uploads and attaches again. It does **not** compare file **contents** (same timestamp after a no-op save means still skipped).
- **Deletes/renames** in the vault do not remove entries from Open WebUI; cleanup is manual or would need extra API work.
- **Formats:** Defaults favor note-friendly types; extend `FILE_EXTENSIONS` in `.env` if you need more.

## Files in this folder

| File | Purpose |
|------|---------|
| `.env` | Your secrets (not committed); create from `.env.sample` |
| `targets.sample.tsv` | Example layout only (placeholders); not used by the script |
| `targets.tsv` | Your watch folders + Knowledge ids (gitignored); create from the sample |
| `sync-obsidian.ps1` | Sync logic |
| `sync-obsidian.bat` | Launches the script |
| `trackers/` | Per–knowledge tracker files (gitignored); created automatically if missing |
| `trackers/uploaded_files_*.txt` | One tracker per Knowledge id (created on first successful save for that target) |
