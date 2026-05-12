#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $ScriptDir '.env'
$TargetsFile = Join-Path $ScriptDir 'targets.tsv'

function Read-DotEnv {
  param([string]$Path)
  $result = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $result }
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    if ($line.StartsWith('REM ', [System.StringComparison]::OrdinalIgnoreCase)) { return }
    $eq = $line.IndexOf('=')
    if ($eq -lt 1) { return }
    $key = $line.Substring(0, $eq).Trim()
    $val = $line.Substring($eq + 1).Trim()
    if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'")))) {
      $val = $val.Substring(1, $val.Length - 2)
    }
    if ($key) { $result[$key] = $val }
  }
  $result
}

function Normalize-BaseUrl {
  param([string]$Url)
  $u = $Url.Trim()
  while ($u.EndsWith('/')) { $u = $u.Substring(0, $u.Length - 1) }
  $u
}

function Get-TrackerPath {
  param([string]$KnowledgeId)
  $safe = $KnowledgeId -replace '[^a-zA-Z0-9\-_]', '_'
  $trackersDir = Join-Path $ScriptDir 'trackers'
  $newPath = Join-Path $trackersDir "uploaded_files_$safe.txt"
  $legacyPath = Join-Path $ScriptDir "uploaded_files_$safe.txt"
  if ((Test-Path -LiteralPath $legacyPath) -and -not (Test-Path -LiteralPath $newPath)) {
    if (-not (Test-Path -LiteralPath $trackersDir)) {
      New-Item -ItemType Directory -Path $trackersDir -Force | Out-Null
    }
    Move-Item -LiteralPath $legacyPath -Destination $newPath -Force
  }
  $newPath
}

function Load-UploadedState {
  param([string]$TrackerPath)
  $dict = [System.Collections.Generic.Dictionary[string, long]]::new([StringComparer]::OrdinalIgnoreCase)
  if (-not (Test-Path -LiteralPath $TrackerPath)) { return ,$dict }
  foreach ($line in @(Get-Content -LiteralPath $TrackerPath -Encoding utf8)) {
    $line = $line.TrimEnd("`r", "`n")
    if (-not $line) { continue }
    $tab = $line.IndexOf("`t", [System.StringComparison]::Ordinal)
    if ($tab -lt 0) {
      # Legacy: path only (no mtime). Assume current on-disk mtime as baseline without re-uploading.
      $p = $line.Trim()
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
      $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
      if (-not $fi) { continue }
      $dict[$fi.FullName] = $fi.LastWriteTimeUtc.Ticks
      continue
    }
    $p = $line.Substring(0, $tab).TrimEnd()
    $rest = $line.Substring($tab + 1).Trim()
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $ticks = [long]0
    if (-not [long]::TryParse($rest, [ref]$ticks)) { continue }
    $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $fi) { continue }
    $dict[$fi.FullName] = $ticks
  }
  return ,$dict
}

function Save-UploadedState {
  param(
    [string]$TrackerPath,
    [System.Collections.Generic.Dictionary[string, long]]$State
  )
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($k in (@($State.Keys) | Sort-Object)) {
    if (-not (Test-Path -LiteralPath $k -PathType Leaf)) { continue }
    [void]$lines.Add("$k`t$($State[$k])")
  }
  $parent = Split-Path -Parent $TrackerPath
  if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  [System.IO.File]::WriteAllLines($TrackerPath, $lines.ToArray(), $utf8)
}

function Get-FileIdFromUploadJson {
  param([string]$Json)
  if (-not $Json) { return $null }
  try {
    $o = $Json | ConvertFrom-Json
  } catch {
    return $null
  }
  if ($null -ne $o.file_id) { return [string]$o.file_id }
  if ($null -ne $o.id) { return [string]$o.id }
  $null
}

function Format-OpenWebUiFailureMessage {
  param(
    [ValidateSet('Upload', 'Attach')]
    [string]$Stage,
    [string]$FilePath,
    [int]$StatusCode,
    [string]$RawBody,
    [string]$TransportDetail
  )
  $leaf = [System.IO.Path]::GetFileName($FilePath)
  if ($TransportDetail) {
    return ("{0} failed: {1}`n  Reason: {2}`n  Path: {3}" -f $Stage, $leaf, $TransportDetail, $FilePath)
  }
  $detail = $null
  if ($RawBody) {
    try {
      $j = $RawBody | ConvertFrom-Json
      if ($null -ne $j.detail) {
        $detail = if ($j.detail -is [string]) { $j.detail } else { ($j.detail | ConvertTo-Json -Compress -Depth 5) }
      }
      elseif ($null -ne $j.message) { $detail = [string]$j.message }
    } catch {
      $t = $RawBody.Trim()
      if ($t.Length -gt 500) { $t = $t.Substring(0, 500) + '...' }
      $detail = $t
    }
  }
  if (-not $detail) { $detail = '(no JSON detail in response body)' }
  $hints = New-Object System.Collections.Generic.List[string]
  if ($detail -match '(?i)content provided is empty') {
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -eq '.md') {
      [void]$hints.Add('For .md: often a blank note, whitespace-only body, or embeds/Dataview that Open WebUI does not expand to text.')
    } elseif ($ext -eq '.pdf') {
      [void]$hints.Add('For .pdf: common on image-only scans (no text layer); try OCR or export to text.')
    } else {
      [void]$hints.Add('Extractor returned no text; file on disk may still have bytes.')
    }
  }
  if ($detail -match '(?i)duplicate') {
    [void]$hints.Add('Same content is already in this Knowledge collection.')
  }
  if ($detail -match '(?i)metadatas') {
    [void]$hints.Add('Backend bug in some Open WebUI + vector DB builds. Try upgrading; if the filename has emoji, try renaming without emoji.')
  }
  if ($detail -match '(?i)Error uploading file') {
    [void]$hints.Add('Server-side: Open WebUI logs, disk space, global file limits. If Open WebUI is behind nginx/Caddy, check max request / body size vs PDF file size. If logs show Errno 24 / Too many open files, raise Docker `nofile` ulimits and consider `UPLOAD_DELAY_MS` in `.env`.')
  }
  if ($detail -match '(?i)too many open files|errno\s*24') {
    [void]$hints.Add('Per-process file descriptor limit (EMFILE). In Docker Compose set `ulimits` `nofile` soft/hard (e.g. 65535) on the Open WebUI service, recreate the container, and optionally set `UPLOAD_DELAY_MS` (e.g. 100–250) to reduce upload bursts.')
  }
  if ($Stage -eq 'Upload' -and $detail -match '(?i)parsing the body') {
    [void]$hints.Add('Multipart was truncated or rejected before the app ran (common: reverse proxy body limit smaller than the PDF). Raise client_max_body_size (nginx) or equivalent, or test the same upload in the Open WebUI browser UI.')
  }
  $hintBlock = if ($hints.Count) { "`n  Hint: " + ($hints -join ' ') } else { '' }
  return ("{0} failed [HTTP {1}]: {2}{3}`n  Path: {4}" -f $Stage, $StatusCode, $detail, $hintBlock, $FilePath)
}

function New-OpenWebUiHttpClient {
  param(
    [string]$BearerToken,
    [int]$TimeoutSeconds = 600
  )
  Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
  $handler = [System.Net.Http.HttpClientHandler]::new()
  $client = [System.Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
  $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $BearerToken)
  [void]$client.DefaultRequestHeaders.Accept.ParseAdd('application/json')
  return [pscustomobject]@{ Client = $client; Handler = $handler }
}

function Get-UploadContentType {
  param([string]$Extension)
  switch ($Extension.ToLowerInvariant()) {
    '.pdf' { return 'application/pdf' }
    '.md' { return 'text/markdown' }
    '.html' { return 'text/html' }
    '.htm' { return 'text/html' }
    '.csv' { return 'text/csv' }
    '.txt' { return 'text/plain' }
    default { return 'application/octet-stream' }
  }
}

function Invoke-OpenWebUiFileUpload {
  param(
    [System.Net.Http.HttpClient]$Client,
    [string]$Url,
    [string]$FilePath
  )
  $multipart = $null
  $fs = $null
  try {
    $fs = [System.IO.File]::OpenRead($FilePath)
  } catch {
    return [pscustomobject]@{
      Success    = $false
      StatusCode = 0
      Content    = $null
      Detail     = "cannot open file: $($_.Exception.Message)"
    }
  }
  try {
    $origName = [System.IO.Path]::GetFileName($FilePath)
    # Some servers choke on non-ASCII filenames in Content-Disposition; bytes still come from $FilePath.
    $dispName = if ($origName -match '[^\x00-\x7F]') {
      [regex]::Replace($origName, '[^\x20-\x7E]', '_')
    } else {
      $origName
    }
    $streamContent = [System.Net.Http.StreamContent]::new($fs)
    $ext = [System.IO.Path]::GetExtension($FilePath)
    $mime = Get-UploadContentType -Extension $ext
    try {
      $streamContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new($mime)
    } catch {
      # leave default if MIME construction fails
    }
    $multipart = [System.Net.Http.MultipartFormDataContent]::new()
    $multipart.Add($streamContent, 'file', $dispName)
    $resp = $Client.PostAsync($Url, $multipart).GetAwaiter().GetResult()
    $bodyStr = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return [pscustomobject]@{
      Success    = $resp.IsSuccessStatusCode
      StatusCode = [int]$resp.StatusCode
      Content    = $bodyStr
      Detail     = $null
    }
  } catch {
    return [pscustomobject]@{
      Success    = $false
      StatusCode = 0
      Content    = $null
      Detail     = $_.Exception.Message
    }
  } finally {
    if ($null -ne $multipart) { $multipart.Dispose() }
    elseif ($null -ne $fs) { $fs.Dispose() }
  }
}

function Invoke-OpenWebUiKnowledgeFileAdd {
  param(
    [System.Net.Http.HttpClient]$Client,
    [string]$Url,
    [string]$JsonBody
  )
  $sc = $null
  try {
    $sc = [System.Net.Http.StringContent]::new(
      $JsonBody,
      [System.Text.UTF8Encoding]::new($false),
      'application/json'
    )
    $resp = $Client.PostAsync($Url, $sc).GetAwaiter().GetResult()
    $bodyStr = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return [pscustomobject]@{
      Success    = $resp.IsSuccessStatusCode
      StatusCode = [int]$resp.StatusCode
      Content    = $bodyStr
      Detail     = $null
    }
  } catch {
    return [pscustomobject]@{
      Success    = $false
      StatusCode = 0
      Content    = $null
      Detail     = $_.Exception.Message
    }
  } finally {
    if ($null -ne $sc) { $sc.Dispose() }
  }
}

$envMap = Read-DotEnv -Path $EnvFile
if (-not $envMap['API_KEY'] -or $envMap['API_KEY'] -eq 'replace-with-your-open-webui-api-key') {
  Write-Error "Missing API_KEY in .env (copy from .env.sample and set your Open WebUI API key)."
}

$baseUrl = Normalize-BaseUrl $(if ($envMap['BASE_URL']) { $envMap['BASE_URL'] } else { 'http://192.168.50.218:13010' })
$apiKey = $envMap['API_KEY']

$httpTimeoutSec = 600
if ($envMap['HTTP_TIMEOUT_SECONDS']) {
  $ts = 0
  if ([int]::TryParse($envMap['HTTP_TIMEOUT_SECONDS'], [ref]$ts) -and $ts -gt 0) { $httpTimeoutSec = $ts }
}

$uploadDelayMs = 0
if ($envMap['UPLOAD_DELAY_MS']) {
  $dm = 0
  if ([int]::TryParse($envMap['UPLOAD_DELAY_MS'], [ref]$dm) -and $dm -ge 0) { $uploadDelayMs = $dm }
}

$extList = @('.md', '.txt', '.pdf', '.html', '.csv')
if ($envMap['FILE_EXTENSIONS']) {
  $extList = $envMap['FILE_EXTENSIONS'].Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
}

if (-not (Test-Path -LiteralPath $TargetsFile)) {
  Write-Error "targets.tsv not found. Copy targets.sample.tsv to targets.tsv and edit watch_folder + knowledge_id columns."
}

$rows = Import-Csv -LiteralPath $TargetsFile -Delimiter "`t"
if (-not $rows -or $rows.Count -eq 0) {
  Write-Error 'targets.tsv has no data rows (need header: watch_folder tab knowledge_id).'
}

$uploadUrl = "$baseUrl/api/v1/files/"

$http = New-OpenWebUiHttpClient -BearerToken $apiKey -TimeoutSeconds $httpTimeoutSec
try {
  $httpClient = $http.Client

  $totalOk = 0
  $totalSkip = 0
  $totalFail = 0
  $totalChanged = 0
  $totalDupAttachOk = 0

  foreach ($row in $rows) {
    $watch = [string]$row.watch_folder
    $kid = [string]$row.knowledge_id
    if (-not $watch -or -not $kid) { continue }
    $watch = $watch.Trim()
    $kid = $kid.Trim()
    if (-not $watch -or -not $kid) { continue }
    if ($kid -eq 'paste-open-webui-knowledge-id-here') { continue }

    if (-not (Test-Path -LiteralPath $watch -PathType Container)) {
      Write-Warning "Skipping missing folder: $watch"
      continue
    }

    $trackerPath = Get-TrackerPath -KnowledgeId $kid
    $uploaded = Load-UploadedState -TrackerPath $trackerPath
    $addUrl = "$baseUrl/api/v1/knowledge/$kid/file/add"

    Write-Host ('Target: {0} -> knowledge {1} (tracker: {2})' -f $watch, $kid, (Split-Path -Leaf $trackerPath))

    $files = Get-ChildItem -LiteralPath $watch -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
      $full = $f.FullName
      $ext = $f.Extension.ToLowerInvariant()
      if ($extList -notcontains $ext) { continue }

      $ticksNow = $f.LastWriteTimeUtc.Ticks
      $priorTicks = [long]0
      $hadPrior = $uploaded.TryGetValue($full, [ref]$priorTicks)
      if ($hadPrior -and ($priorTicks -eq $ticksNow)) {
        $totalSkip++
        continue
      }

      $up = Invoke-OpenWebUiFileUpload -Client $httpClient -Url $uploadUrl -FilePath $full
      if (-not $up.Success) {
        $msg = if ($up.Detail) {
          Format-OpenWebUiFailureMessage -Stage Upload -FilePath $full -StatusCode $up.StatusCode -RawBody $null -TransportDetail $up.Detail
        } else {
          Format-OpenWebUiFailureMessage -Stage Upload -FilePath $full -StatusCode $up.StatusCode -RawBody $up.Content -TransportDetail $null
        }
        Write-Warning $msg
        $totalFail++
        if ($uploadDelayMs -gt 0) { Start-Sleep -Milliseconds $uploadDelayMs }
        continue
      }

      $upJson = [string]$up.Content
      $fileId = Get-FileIdFromUploadJson -Json $upJson
      if (-not $fileId) {
        $msg = Format-OpenWebUiFailureMessage -Stage Upload -FilePath $full -StatusCode 0 -RawBody $upJson -TransportDetail 'Response had no file id (id / file_id).'
        Write-Warning $msg
        $totalFail++
        if ($uploadDelayMs -gt 0) { Start-Sleep -Milliseconds $uploadDelayMs }
        continue
      }

      $body = (@{ file_id = $fileId } | ConvertTo-Json -Compress)
      $add = Invoke-OpenWebUiKnowledgeFileAdd -Client $httpClient -Url $addUrl -JsonBody $body
      if (-not $add.Success) {
        $attachBody = [string]$add.Content
        if ($attachBody -match '(?i)duplicate\s+content\s+detected') {
          Write-Host ("  OK (already in Knowledge; attach duplicate ignored) {0}" -f $full)
          $uploaded[$full] = $ticksNow
          $totalDupAttachOk++
          if ($uploadDelayMs -gt 0) { Start-Sleep -Milliseconds $uploadDelayMs }
          continue
        }
        $msg = if ($add.Detail) {
          Format-OpenWebUiFailureMessage -Stage Attach -FilePath $full -StatusCode $add.StatusCode -RawBody $null -TransportDetail $add.Detail
        } else {
          Format-OpenWebUiFailureMessage -Stage Attach -FilePath $full -StatusCode $add.StatusCode -RawBody $add.Content -TransportDetail $null
        }
        Write-Warning $msg
        $totalFail++
        if ($uploadDelayMs -gt 0) { Start-Sleep -Milliseconds $uploadDelayMs }
        continue
      }

      $uploaded[$full] = $ticksNow
      if ($hadPrior) { $totalChanged++ } else { $totalOk++ }
      Write-Host "  OK $full"
      if ($uploadDelayMs -gt 0) { Start-Sleep -Milliseconds $uploadDelayMs }
    }

    Save-UploadedState -TrackerPath $trackerPath -State $uploaded
  }

  Write-Host "Done. New uploads: $totalOk  Re-uploaded (changed): $totalChanged  Skipped (unchanged): $totalSkip  Dup attach OK: $totalDupAttachOk  Failed: $totalFail"
  if ($totalFail -gt 0) { exit 1 }
} finally {
  if ($null -ne $http.Client) { $http.Client.Dispose() }
  if ($null -ne $http.Handler) { $http.Handler.Dispose() }
}
