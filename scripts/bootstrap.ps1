# Repo-local shim. Keep short and pinned to a module version.
# Repo: BernardinD/flutter-bootstrap-tools

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = '1.0.0'
$Repo    = 'BernardinD/flutter-bootstrap-tools'

$assetName = "flutter-bootstrap-tools_$Version.zip"
$download  = "https://github.com/$Repo/releases/download/v$Version/$assetName"

$tempZip = Join-Path $env:TEMP $assetName
$extract = Join-Path $env:TEMP ("flutter-bootstrap-tools_" + $Version)

if (Test-Path -LiteralPath $extract) { Remove-Item -Recurse -Force $extract }
Invoke-WebRequest -UseBasicParsing -Uri $download -OutFile $tempZip
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extract)

$modulePath = Join-Path $extract 'src\BootstrapTools.psm1'
Import-Module $modulePath -Force

$cfgPath = Join-Path $PSScriptRoot '..\.bootstrap.psd1'
Invoke-FlutterBootstrap -ConfigPath $cfgPath
