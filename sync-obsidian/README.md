# Obsidian and Open WebUI Sync

Sync files from one or more local folders (for example separate Obsidian course folders) into Open WebUI **Workspace → Knowledge** collections so you can use them for RAG in chats.

## What it does

- Reads **targets** from `targets.tsv`: each row is a **watch folder** plus a **Knowledge collection id** from Open WebUI (so `course1`, `course2`, etc. can each map to its own Knowledge base).
- Recursively finds files under each watch folder, filtered by extension (configurable).
- For each file not yet recorded for that Knowledge target, uploads it and attaches it to that collection.
- If a tracked file **disappears** from disk (deleted or moved out of the watch tree), calls Open WebUI to **remove** it from that Knowledge collection (when a `file_id` is stored in the tracker).
- Appends each successfully processed **full file path** (plus metadata) to a **per–Knowledge-id** tracker file so reruns skip duplicates and identical names in two courses do not collide.

## Open WebUI API (upload, attach, remove)

Open WebUI uses **Bearer** auth for upload, attach, and (when you delete locally) remove from Knowledge. Base URL example (yours may differ):

`http://192.168.50.218:13010`

1. **Upload** — `POST {BASE_URL}/api/v1/files/`  
   Headers: `Authorization: Bearer <API_KEY>`, `Accept: application/json`  
   Body: multipart form field `file` (the file bytes).  
   Response JSON includes the new file id (commonly `id`; the script also accepts `file_id`).

2. **Attach to Knowledge** — `POST {BASE_URL}/api/v1/knowledge/{knowledge_id}/file/add`  
   Headers: `Authorization: Bearer <API_KEY>`, `Content-Type: application/json`  
   Body: `{"file_id":"<id>"}` (same value returned from step 1).

3. **Remove from Knowledge** (when a tracked file is deleted locally) — `POST {BASE_URL}/api/v1/knowledge/{knowledge_id}/file/remove?delete_file=<true|false>`  
   Headers: same as step 2.  
   Body: `{"file_id":"<id>"}` (the id is stored in the tracker after a successful attach).  
   Query `delete_file` defaults to **true** in Open WebUI: when true and your user is the file owner (or admin), the server also deletes the global file record and storage. Set **`KNOWLEDGE_REMOVE_DELETE_FILE=false`** in `.env` to only unlink from this Knowledge (useful if the same uploaded file might be attached to multiple collections).

Interactive docs on your instance: `{BASE_URL}/api/v1/docs`.

## Setup

1. Copy [`.env.sample`](.env.sample) to **`.env`** in this folder and set **`API_KEY`**. In Open WebUI, keys are created under **Settings → Account** in the **API Keys** section. If you do not see that section, an admin must turn on **Enable API Keys** under **Admin Panel → Settings → General → Authentication**, and non-admin accounts need the **API Keys** feature permission in **Admin Panel → Users → Groups**. See [API Keys (Open WebUI docs)](https://docs.openwebui.com/features/authentication-access/api-keys). Adjust **`BASE_URL`** if needed.
2. Copy [`targets.sample.tsv`](targets.sample.tsv) to **`targets.tsv`** (same folder). **`targets.sample.tsv` stays generic (placeholders only);** put your real watch folders and Knowledge ids in **`targets.tsv`** (gitignored). The Knowledge id is the last segment of the Knowledge URL (`…/workspace/knowledge/<id>`). Create one Knowledge per course in the UI if you want separate collections. **Columns are separated by a single tab; spaces in folder paths do not require quotes** (only avoid tab characters inside a path).

## Tracker files

For each `knowledge_id` in `targets.tsv`, the script writes under the **`trackers`** subfolder:

`trackers/uploaded_files_<knowledge_id>.txt`

Each **non-empty** line is one of:

- **Current:** `full_path_to_file` **TAB** `LastWriteTimeUtc_ticks` **TAB** `open_webui_file_id`  
  The third column is written after a successful attach so the script can call **`/file/remove`** when the file is later deleted locally.
- **Older (still supported):** `full_path_to_file` **TAB** `LastWriteTimeUtc_ticks` with no third column — sync works as before, but **remote remove on delete** is not possible until that path is successfully synced again (then the tracker line gains a `file_id`).
- **Legacy:** path-only lines (no tab) — unchanged behavior on load.

(`…ticks` is the Windows file **last-write time in UTC**, as .NET `DateTime` ticks, so the script can tell when a note was saved and **upload again**.)

- **Legacy location:** If an older tracker still lives next to the script as `uploaded_files_<id>.txt`, it is **moved** into `trackers/` the first time that target runs.
- **Legacy:** older trackers used **path-only** lines (no tab). Those are still read on load: the script records each file’s **current** last-write time as the baseline and rewrites the file in the new format on the next run (no extra upload if nothing changed since then).
- **Deletes:** If a path is in the tracker but the file **no longer exists** under the watch folder, the script removes it from Open WebUI Knowledge when **`file_id`** is known; otherwise it prunes the tracker line and warns that Knowledge may still list the document until you remove it manually or re-sync after a successful attach stores an id.
- To **force** a re-upload even when the timestamp did not change, temporarily change the file’s modified time (e.g. re-save in the editor) or remove that file’s line from the tracker.

**Note:** Re-uploading after an edit (same path, new mtime) adds **another** copy in Open WebUI unless you removed the old document; the remove-on-delete flow clears the prior attachment when you delete the file locally and the tracker had a `file_id`.

### Resync a Knowledge target from scratch

Use this after experimenting with Open WebUI’s built-in directory sync, switching machines, or when you want a full re-upload for one course folder.

1. In Open WebUI, open each affected **Knowledge** collection and **remove all documents** (or delete and recreate the collection and update `knowledge_id` in `targets.tsv` if the id changed).
2. Delete that target’s local tracker file, for example:
   - COMM 310: `trackers/uploaded_files_e0f06c42-921c-465d-9bcb-3620c0e12a86.txt`
   - COMM 320: `trackers/uploaded_files_144e87a0-3980-4873-8c37-0b59977d6e4c.txt`
   (Pattern: `trackers/uploaded_files_<knowledge_id>.txt` from the second column in `targets.tsv`.)
3. Run **`sync-obsidian.ps1`** (or the `.bat`). Every file under that watch folder is treated as new and goes through upload + attach.

Skipping step 1 can leave **duplicate** entries in Knowledge (attach may report “duplicate content” for some files; others may appear twice). Other targets in `targets.tsv` are unaffected if you only delete their tracker files.

## Run

Double-click **`sync-obsidian.bat`** or from a terminal:

```bat
cd /d "d:\duaneleem\Code\utils.win\sync-obsidian"
sync-obsidian.bat
```

Requires **Windows** with **PowerShell 5.1+**. Uploads use **.NET `HttpClient`** (not `curl`) so paths with **Unicode / emoji** in file names open reliably; the attach step uses the same client.

If you **double-click** the `.bat` and something fails, the window **stays open** with `Press any key to continue . . .` so you can read the error.

To **append a full run log** to a file (including warnings), set **`LOG_PATH`** in `.env` (see [`.env.sample`](.env.sample)). Example: `LOG_PATH=temp/output.log` creates or appends under the `temp/` folder next to the script. Use an absolute path if you prefer. Empty or unset disables logging. Before each append, the script **trims** that file to the last **3** complete PowerShell transcript runs (so the file does not grow without bound). Override with **`LOG_KEEP_RUNS`** (e.g. `5`); set **`LOG_KEEP_RUNS=0`** to keep the full history.

### If some files still fail

| Symptom | Likely cause |
|--------|----------------|
| Warning says **cannot open file** | Permission denied, file exclusively locked (close Obsidian/PDF reader on that file), or rare path issues. |
| **HTTP 400** on upload | Open WebUI rejected the request: **file too large**, unsupported type, ingestion limits, **0-byte body** (the server often logs *empty content* but returns a generic **Error uploading file** in JSON), or other validation. **0-byte files** are **skipped before upload** and recorded like other empty-content skips (no `file_id`). If the response body ever includes **empty content**, failed uploads are handled the same way. Otherwise check the warning line for the response body and your Open WebUI / RAG settings and logs. Optional warnings: **`WARN_EMPTY_CONTENT`** / **`WARN_EMPTY_ATTACH`**. |
| **`[ERROR: Error uploading file]`** (no extra detail) | Same as upload 400: **logs**, **disk space**, **proxy body limits**, and **Documents** max upload settings. The script now sends a correct **Content-Type** per extension and a longer default **HTTP timeout** (see `.env.sample` `HTTP_TIMEOUT_SECONDS`). If **server logs** show **`OSError: [Errno 24] Too many open files`** during `POST /api/v1/files/`, the process hit the **open file descriptor limit** (often under **Docker**’s default `nofile`). Raise **`ulimits`** (Docker `nofile`) on the Open WebUI service and optionally set **`UPLOAD_DELAY_MS`** in `.env` to pace uploads. |
| **HTTP 400** on attach, message about **empty** content | The server often means **extracted text was empty** (common with **image-only / scanned PDFs** without OCR, encrypted PDFs, or extractor bugs)—not that your file is 0 bytes on disk. The script **records the path in the tracker** (with the uploaded `file_id`) so **later runs skip** that file until its **last modified time** changes; then it tries again (e.g. after OCR or re-save). Optional per-file **`Write-Warning`**: set **`WARN_EMPTY_CONTENT=true`** in `.env` (or legacy **`WARN_EMPTY_ATTACH=true`**). Try OCR’d PDFs, `.md` exports, or Open WebUI’s [RAG troubleshooting](https://docs.openwebui.com/troubleshooting/rag/). Each first failure may still leave an **orphan** uploaded file in Open WebUI’s file list; you can delete it in the UI if you care. |
| **Server log:** `cannot reshape array` … `PyPDFParser` / `extract_images_from_page` | **LangChain PyPDF** failed while decoding an **embedded image** on a page (dimensions vs raw bytes mismatch: odd compression, CMYK/JPEG quirks, or slightly corrupt streams). Re-**print** or **re-export** the PDF (Acrobat, “Microsoft Print to PDF”), or try a **newer Open WebUI** release. Often the same PDF still yields **no extractable text** afterward, so you may see **empty content** on attach. |
| **HTTP 400** duplicate on **attach** | Same content is already in that Knowledge collection. The script treats this as **success**: it updates the local tracker so the next run does not keep re-uploading. (Each failed run may still have created an extra file in Open WebUI’s file list; you can clean orphans in the UI if needed.) |
| **`metadatas` / MetadataValue** on attach | Open WebUI / vector DB bug with some files or versions. Try **upgrading Open WebUI**, check **server logs**, or rename notes that use **emoji** in the file name to test. |
| **HTTP 400** … **parsing the body** (upload) | Often **not** Open WebUI app logic: the **HTTP request was cut off or malformed** (very common when a **reverse proxy** max body size is smaller than the PDF). Increase **nginx `client_max_body_size`** (or Traefik/Caddy equivalent), then retry. Compare with uploading the same file in the **browser UI**. |
| **Server log:** `Too many open files` / **Errno 24** on upload | The Open WebUI (Python) process ran out of **file descriptors**. Typical fix: in **`docker-compose.yml`**, on the Open WebUI service add `ulimits: { nofile: { soft: 65535, hard: 65535 } }` (or similar), then `docker compose up -d`. Optionally **`UPLOAD_DELAY_MS`** in `.env` (e.g. `150`) so the script sleeps briefly after each upload/attach. |
| **Remove failed** (HTTP / transport on `/file/remove`) | Wrong `file_id`, permission, or Knowledge id; response body in the warning. The tracker row is **kept** so a later run retries. |
| **HTTP 4xx/5xx** on attach (other) | Knowledge id wrong, permission, or transient server error; response body in the warning helps. |


To capture output in a terminal you already have open (so nothing flashes away), run PowerShell directly:

```powershell
Set-Location "d:\duaneleem\Code\utils.win\sync-obsidian"
.\sync-obsidian.ps1
```

## Caveats

- **Edits:** After a successful sync, the tracker stores each file’s **last modified time (UTC)** and **`file_id`**. If you edit and save the file so its timestamp **changes**, the next run uploads and attaches again. It does **not** compare file **contents** (same timestamp after a no-op save means still skipped).
- **Deletes/renames:** If you **delete** a file that was synced with a stored `file_id`, the next run calls Open WebUI **`/knowledge/.../file/remove`** for that Knowledge target (see **`KNOWLEDGE_REMOVE_DELETE_FILE`** in `.env.sample`). If you **rename** or move a file, the old path is treated like a delete (remote remove if `file_id` was known) and the new path is uploaded as a new file when discovered.
- **Empty content (upload or attach):** **0-byte** files are **not sent** to the upload API (Open WebUI often logs *empty content* but returns a generic *Error uploading file* in JSON, so the script used to retry forever). The script records **mtime only** (clears stale `file_id`) until the file has content. If an upload response still mentions **empty content**, that is handled the same way. **Attach** empty-content failures record **mtime + `file_id`**. Orphan uploads after attach failures are unchanged; clean in the UI if needed. Per-file **`Write-Warning`** is **off** unless **`WARN_EMPTY_CONTENT=true`** (or legacy **`WARN_EMPTY_ATTACH=true`**) in `.env`.
- **Formats:** Defaults favor note-friendly types; extend `FILE_EXTENSIONS` in `.env` if you need more.

## Files in this folder

| File | Purpose |
|------|---------|
| `.env` | Your secrets (not committed); create from `.env.sample` |
| `targets.sample.tsv` | Example layout only (placeholders); not used by the script |
| `targets.tsv` | Your watch folders + Knowledge ids (gitignored); create from the sample |
| `sync-obsidian.ps1` | Sync logic |
| `sync-obsidian.bat` | Launches the script |
| `temp/` | Optional run logs when **`LOG_PATH`** in `.env` points here (gitignored) |
| `trackers/` | Per–knowledge tracker files (gitignored); created automatically if missing |
| `trackers/uploaded_files_*.txt` | One tracker per Knowledge id (created on first successful save for that target) |
