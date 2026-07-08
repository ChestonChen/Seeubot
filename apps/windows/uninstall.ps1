$ErrorActionPreference = "SilentlyContinue"

$Product = "Seeubot"
$InstallDir = Join-Path $env:LOCALAPPDATA $Product
$StartupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Seeubot.lnk"

Remove-Item $StartupShortcut -Force
Stop-Process -Name "Seeubot" -Force
Stop-Process -Name "seeubot-windows" -Force
Remove-Item -Recurse -Force $InstallDir

Write-Host "✓ Seeubot for Windows has been removed."
