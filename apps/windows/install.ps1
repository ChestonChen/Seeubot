param(
  [switch]$FromSource
)

$Root = Resolve-Path (Join-Path $PSScriptRoot "../..")
& (Join-Path $Root "install.ps1") -FromSource:$FromSource
