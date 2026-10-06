<#
.SYNOPSIS
  opencode-parakeet installer - local speech-to-text for OpenCode voice input.

.DESCRIPTION
  Downloads the Parakeet server runtime (parakeet.cpp builds mirrored in this
  repository's Releases) and a Parakeet TDT 0.6B v3 GGUF model (Hugging Face),
  verifies checksums, generates a serve.ps1 launcher, installs an OpenCode
  plugin that starts the server automatically with OpenCode, and optionally
  configures OpenCode to use it.

  Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
  irm https://raw.githubusercontent.com/moesuito/opencode-parakeet/main/install.ps1 | iex

.EXAMPLE
  $s = irm https://raw.githubusercontent.com/moesuito/opencode-parakeet/main/install.ps1
  & ([scriptblock]::Create($s)) -Backend cpu -Model q8_0 -Configure
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "",
  [ValidateSet("vulkan", "cpu")][string]$Backend = "vulkan",
  [ValidateSet("f16", "q8_0", "q6_k", "q5_k", "q4_k")][string]$Model = "f16",
  [int]$Port = 8797,
  [string]$ConfigDir = "",
  [switch]$NoModel,
  [switch]$NoVerify,
  [switch]$NoPlugin,
  [switch]$Configure,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$ReleaseBase = "https://github.com/moesuito/opencode-parakeet/releases/latest/download"
$ModelBase   = "https://huggingface.co/mudler/parakeet-cpp-gguf/resolve/main"

$ModelFiles = @{
  "f16"  = @{ file = "tdt-0.6b-v3-f16.gguf";  bytes = 1441046400 }
  "q8_0" = @{ file = "tdt-0.6b-v3-q8_0.gguf"; bytes = 940663680 }
  "q6_k" = @{ file = "tdt-0.6b-v3-q6_k.gguf"; bytes = 812700512 }
  "q5_k" = @{ file = "tdt-0.6b-v3-q5_k.gguf"; bytes = 741867360 }
  "q4_k" = @{ file = "tdt-0.6b-v3-q4_k.gguf"; bytes = 675200864 }
}

function Write-Info([string]$message) { Write-Host "==> $message" -ForegroundColor Cyan }
function Write-Ok([string]$message) { Write-Host "    $message" -ForegroundColor Green }
function Write-Warn([string]$message) { Write-Host "    ! $message" -ForegroundColor Yellow }
function Fail([string]$message) { throw "opencode-parakeet: $message" }

function Get-RemoteFile([string]$Url, [string]$Dest, [switch]$Resume) {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    $curlArgs = @("-L", "--fail", "--retry", "3", "-o", $Dest)
    if ($Resume -and (Test-Path $Dest)) { $curlArgs = @("-L", "--fail", "--retry", "3", "-C", "-", "-o", $Dest) }
    & curl.exe @curlArgs $Url
    if ($LASTEXITCODE -ne 0) { Fail "download failed (curl exit $LASTEXITCODE): $Url" }
    return
  }
  if ($Resume -and (Test-Path $Dest)) { Remove-Item -LiteralPath $Dest -Force }
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

function Get-RemoteText([string]$Url) {
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) { return ((& curl.exe -sL --fail --retry 3 $Url) -join "`n") }
  $ProgressPreference = "SilentlyContinue"
  return (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-ExpectedHash([string]$SumsPath, [string]$FileName) {
  if (-not (Test-Path $SumsPath)) { return $null }
  foreach ($line in (Get-Content -Path $SumsPath)) {
    if ($line -match "^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$") {
      if ($Matches[2] -eq $FileName) { return $Matches[1].ToLower() }
    }
  }
  return $null
}

function Get-RemoteSha256([string]$Url) {
  # Hugging Face exposes the content sha256 as "X-Linked-ETag" on the resolve
  # response. The CDN's own ETag (after the redirect) is NOT the file hash, so
  # read the first response (or scan the redirect chain) with curl.exe.
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    foreach ($argSet in @(@("-sI", $Url), @("-sIL", $Url))) {
      $lines = & curl.exe @argSet 2>$null
      foreach ($line in $lines) {
        if ($line -match "(?i)^\s*x-linked-etag:\s*(.+)$") {
          $match = [regex]::Match($Matches[1], "[0-9a-fA-F]{64}")
          if ($match.Success) { return $match.Value.ToLower() }
        }
      }
    }
  } else {
    try {
      $head = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -TimeoutSec 30 -UseBasicParsing
      $value = $head.Headers["X-Linked-Etag"]
      if ($value) {
        $match = [regex]::Match([string]$value, "[0-9a-fA-F]{64}")
        if ($match.Success) { return $match.Value.ToLower() }
      }
    } catch { }
  }
  return $null
}

function Set-VoiceConfig([string]$Path, [string]$Url) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  if ((Test-Path $Path) -and (Get-Item -LiteralPath $Path).Length -gt 0) {
    $raw = Get-Content -Path $Path -Raw
    try { $obj = $raw | ConvertFrom-Json } catch {
      Write-Warn "not valid JSON, skipping: $Path"
      return $false
    }
    Copy-Item -LiteralPath $Path -Destination ("$Path.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")) -Force
  } else {
    $obj = New-Object psobject
  }

  if (-not ($obj.PSObject.Properties.Name -contains "voice")) {
    $obj | Add-Member -MemberType NoteProperty -Name voice -Value (New-Object psobject)
  }
  $obj.voice | Add-Member -MemberType NoteProperty -Name url   -Value $Url -Force
  $obj.voice | Add-Member -MemberType NoteProperty -Name model -Value "parakeet" -Force

  $json = $obj | ConvertTo-Json -Depth 64
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $json, $utf8)
  return $true
}

# ---------------------------------------------------------------- main

Write-Host ""
Write-Host "opencode-parakeet installer" -ForegroundColor White
Write-Host "Local OpenAI-compatible speech-to-text for OpenCode voice input" -ForegroundColor DarkGray
Write-Host ""

if (-not $InstallDir) {
  if ($env:LOCALAPPDATA) { $InstallDir = Join-Path $env:LOCALAPPDATA "opencode-parakeet" }
  else { $InstallDir = Join-Path $HOME ".opencode-parakeet" }
}
if (-not $ConfigDir) { $ConfigDir = Join-Path $HOME ".config/opencode" }

Write-Info "PowerShell $($PSVersionTable.PSVersion)"
if (-not [Environment]::Is64BitOperatingSystem) { Fail "64-bit Windows is required." }

$asset     = "parakeet-server-win-x64-$Backend.zip"
$zipPath   = Join-Path $InstallDir $asset
$sumsPath  = Join-Path $InstallDir "SHA256SUMS"
$serverExe = Join-Path $InstallDir "parakeet-server.exe"

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Info "Install directory: $InstallDir"

if ($Force -or -not (Test-Path $serverExe)) {
  Write-Info "Downloading server runtime ($Backend): $asset"
  Get-RemoteFile "$ReleaseBase/$asset" $zipPath

  if (-not $NoVerify) {
    Get-RemoteFile "$ReleaseBase/SHA256SUMS" $sumsPath
    $expected = Get-ExpectedHash $sumsPath $asset
    if (-not $expected) { Fail "no checksum for $asset in SHA256SUMS" }
    $actual = Get-Sha256 $zipPath
    if ($actual -ne $expected) { Fail "checksum mismatch for $asset (got $actual)" }
    Write-Ok "checksum verified"
  }

  Write-Info "Extracting"
  Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
  Remove-Item -LiteralPath $zipPath -Force

  if (-not (Test-Path $serverExe)) {
    $sub = Get-ChildItem $InstallDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "parakeet-server.exe") } | Select-Object -First 1
    if ($sub) {
      Get-ChildItem -LiteralPath $sub.FullName -Force | ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $InstallDir -Force }
      Remove-Item -LiteralPath $sub.FullName -Recurse -Force
    }
  }
  if (-not (Test-Path $serverExe)) { Fail "parakeet-server.exe not found after extraction" }
  Write-Ok "server installed"
} else {
  Write-Ok "server already installed (use -Force to reinstall)"
}

$modelInfo = $ModelFiles[$Model]
$modelPath = Join-Path $InstallDir $modelInfo.file

if ($NoModel) {
  Write-Warn "model download skipped (-NoModel). Add $($modelInfo.file) to the install directory later."
} else {
  $sizeOk = $false
  if ((Test-Path $modelPath) -and -not $Force) {
    $length = (Get-Item -LiteralPath $modelPath).Length
    if ($length -eq $modelInfo.bytes) { $sizeOk = $true }
    elseif ($length -gt 0) { Write-Warn "partial model found, resuming download" }
  }

  if ($sizeOk) {
    Write-Ok "model already present: $($modelInfo.file)"
  } else {
    $mb = [math]::Round($modelInfo.bytes / 1MB)
    Write-Info "Downloading model: $($modelInfo.file) ($mb MB, from Hugging Face)"
    Get-RemoteFile "$ModelBase/$($modelInfo.file)" $modelPath -Resume

    $length = (Get-Item -LiteralPath $modelPath).Length
    if ($length -ne $modelInfo.bytes) { Fail "model size mismatch: got $length bytes, expected $($modelInfo.bytes)" }
    Write-Ok "size verified"

    if (-not $NoVerify) {
      $remoteSha = Get-RemoteSha256 "$ModelBase/$($modelInfo.file)"
      if ($remoteSha) {
        Write-Info "Verifying model checksum (large file, this takes a moment)"
        if ((Get-Sha256 $modelPath) -ne $remoteSha) { Fail "model checksum mismatch" }
        Write-Ok "checksum verified"
      } else {
        Write-Warn "could not fetch remote checksum; verification skipped"
      }
    }
  }
}

$voiceUrl = "http://127.0.0.1:$Port/v1/audio/transcriptions"

$serveTemplate = @'
param([int]$Port = __PORT__)
$server = Join-Path $PSScriptRoot "parakeet-server.exe"
$model  = Join-Path $PSScriptRoot "__MODEL__"
if (-not (Test-Path $server)) { Write-Error "parakeet-server.exe not found next to this script."; exit 1 }
if (-not (Test-Path $model)) { Write-Error "model not found: $model"; exit 1 }
Write-Host "Serving Parakeet on http://127.0.0.1:$Port (OpenAI-compatible /v1/audio/transcriptions)"
& $server --model $model --port $Port
'@
$serve = $serveTemplate.Replace("__PORT__", [string]$Port).Replace("__MODEL__", $modelInfo.file)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$servePath = Join-Path $InstallDir "serve.ps1"
[IO.File]::WriteAllText($servePath, $serve, $utf8)
Write-Ok "launcher ready: $servePath"

if (-not $NoPlugin) {
  # OpenCode plugin: starts the server automatically when OpenCode boots,
  # unless one is already listening.
  $pluginDir = Join-Path $ConfigDir "plugins"
  $pluginPath = Join-Path $pluginDir "opencode-parakeet.ts"
  New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
  Write-Info "Installing the OpenCode plugin (auto-start on boot)"
  $pluginSource = Get-RemoteText "https://raw.githubusercontent.com/moesuito/opencode-parakeet/main/plugin/opencode-parakeet.ts"
  if (-not $pluginSource) {
    Write-Warn "could not download the plugin; skipping (copy it manually from the repository)"
  } else {
    $pluginSource = $pluginSource.Replace('dir: "__PARAKEET_DIR__"', 'dir: "' + $InstallDir.Replace("\", "/") + '"')
    $pluginSource = $pluginSource.Replace("port: 8797", "port: $Port")
    $pluginSource = $pluginSource.Replace('model: "tdt-0.6b-v3-f16.gguf"', 'model: "' + $modelInfo.file + '"')
    [IO.File]::WriteAllText($pluginPath, $pluginSource, $utf8)
    Write-Ok "plugin installed: $pluginPath"
  }
}

if ($Configure) {
  Write-Info "Updating OpenCode config (backups are created next to each file)"
  foreach ($target in @((Join-Path $ConfigDir "cli.json"), (Join-Path $ConfigDir "opencode.json"))) {
    if (Set-VoiceConfig -Path $target -Url $voiceUrl) { Write-Ok "updated $target" }
  }
}

Write-Host ""
Write-Host "All set. Next steps:" -ForegroundColor White
Write-Host ""
if ($NoPlugin) {
  Write-Host "  1) Start the server:"
  Write-Host "       & `"$servePath`""
} else {
  Write-Host "  1) The server now starts automatically when OpenCode boots."
  Write-Host "     To start it manually instead: & `"$servePath`""
}
Write-Host ""
Write-Host "  2) Point OpenCode's voice input at it"
if ($Configure) {
  Write-Host "       (already done by -Configure)"
} else {
  Write-Host "       Add to " -NoNewline
  Write-Host "$ConfigDir\cli.json" -NoNewline -ForegroundColor Cyan
  Write-Host " (TUI) and " -NoNewline
  Write-Host "$ConfigDir\opencode.json" -NoNewline -ForegroundColor Cyan
  Write-Host " (web/desktop):"
  Write-Host ""
  Write-Host "       {"
  Write-Host "         `"voice`": {"
  Write-Host "           `"url`": `"$voiceUrl`","
  Write-Host "           `"model`": `"parakeet`""
  Write-Host "         }"
  Write-Host "       }"
  Write-Host ""
  Write-Host "       Tip: re-run with -Configure to apply this automatically."
}
Write-Host ""
Write-Host "  3) Use it: TUI Ctrl+Y starts/stops recording and sends; Alt+Y inserts without sending."
Write-Host "     Web/desktop: click the mic in the composer."
Write-Host ""
Write-Host "Docs: https://github.com/moesuito/opencode-parakeet" -ForegroundColor DarkGray
Write-Host "Note: the Vulkan build needs a Vulkan-capable GPU + drivers. No Vulkan? Re-run with -Backend cpu." -ForegroundColor DarkGray
