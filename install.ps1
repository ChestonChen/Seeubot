param(
  [switch]$FromSource
)

$ErrorActionPreference = "Stop"

$Product = "Seeubot"
$Repo = "ChestonChen/Seeubot"
$InstallDir = Join-Path $env:LOCALAPPDATA $Product
$ExePath = Join-Path $InstallDir "Seeubot.exe"
$StartupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Seeubot.lnk"

function Step($message) {
  Write-Host "▸ $message"
}

function Require-Command($name, $help) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "$name not found. $help"
  }
}

function Install-Shortcut {
  Step "Creating startup shortcut"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($StartupShortcut)
  $shortcut.TargetPath = $ExePath
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.WindowStyle = 7
  $shortcut.Save()
}

function Install-ZipFromUrl($url, $name) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("seeubot-win-" + [Guid]::NewGuid())
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp $name
  Step "Downloading $name"
  Invoke-WebRequest -Uri $url -OutFile $zip
  Expand-Archive -Path $zip -DestinationPath $tmp -Force

  $exe = Get-ChildItem -Path $tmp -Filter "Seeubot.exe" -Recurse | Select-Object -First 1
  if (-not $exe) {
    throw "$name does not contain Seeubot.exe."
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -Path (Join-Path $exe.DirectoryName "*") -Destination $InstallDir -Recurse -Force
}

function Install-ZipAsset {
  Step "Looking for latest Windows release"
  try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "Seeubot-Installer" }
    $asset = $release.assets | Where-Object { $_.name -match "Seeubot.*Windows.*x64.*\.zip$|seeubot.*windows.*x64.*\.zip$" } | Select-Object -First 1
    if ($asset) {
      Install-ZipFromUrl $asset.browser_download_url $asset.name
      return
    }
  } catch {
    Write-Warning "No GitHub release package found yet."
  }

  $raw = "https://raw.githubusercontent.com/$Repo/main/apps/windows/release/Seeubot-Windows-x64.zip"
  Install-ZipFromUrl $raw "Seeubot-Windows-x64.zip"
}

function Install-FromSource {
  Step "Building from source"
  Require-Command "git" "Install Git for Windows or use a release package."
  Require-Command "node" "Install Node.js 22+."
  Require-Command "npm" "Install Node.js 22+."
  Require-Command "cargo" "Install Rust from https://rustup.rs/."

  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("seeubot-src-" + [Guid]::NewGuid())
  git clone --depth 1 "https://github.com/$Repo.git" $tmp | Out-Null
  Push-Location (Join-Path $tmp "apps/windows")
  try {
    npm install
    npm run tauri:build
    $built = Get-ChildItem -Path "src-tauri/target/release" -Filter "seeubot-windows.exe" -Recurse | Select-Object -First 1
    if (-not $built) {
      $built = Get-ChildItem -Path "src-tauri/target/release" -Filter "Seeubot.exe" -Recurse | Select-Object -First 1
    }
    if (-not $built) {
      throw "Could not find built Seeubot executable."
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -Path $built.FullName -Destination $ExePath -Force
  } finally {
    Pop-Location
  }
}

Step "Stopping existing Seeubot"
Stop-Process -Name "Seeubot" -ErrorAction SilentlyContinue
Stop-Process -Name "seeubot-windows" -ErrorAction SilentlyContinue
Remove-Item $StartupShortcut -ErrorAction SilentlyContinue

try {
  if ($FromSource) {
    Install-FromSource
  } else {
    Install-ZipAsset
  }
} catch {
  if ($FromSource) {
    throw
  }
  Write-Warning $_.Exception.Message
  Write-Warning "Falling back to source build. This requires Git, Node.js and Rust."
  Install-FromSource
}

if (-not (Test-Path $ExePath)) {
  $candidate = Get-ChildItem -Path $InstallDir -Filter "*.exe" -Recurse | Select-Object -First 1
  if ($candidate) {
    Copy-Item $candidate.FullName $ExePath -Force
  }
}

Install-Shortcut
Step "Launching Seeubot"
Start-Process $ExePath

Write-Host ""
Write-Host "✓ Seeubot for Windows is installed in $InstallDir"
Write-Host "Uninstall:"
Write-Host "powershell -ExecutionPolicy Bypass -Command `"Remove-Item '$StartupShortcut' -ErrorAction SilentlyContinue; Stop-Process -Name Seeubot -ErrorAction SilentlyContinue; Stop-Process -Name seeubot-windows -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force '$InstallDir'`""
