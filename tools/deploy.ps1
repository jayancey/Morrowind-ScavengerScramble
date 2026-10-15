<#
.SYNOPSIS
  Copies the Scavenger Scramble mod into a TES3MP server's custom scripts folder.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\deploy.ps1
  powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -ServerRoot "D:\tes3mp"

  The first run moves any existing scripts\custom\scavenger-scramble* folders to
  scripts\custom\backup\<timestamp>\ so the old prototype is kept.
#>
param(
    [string]$ServerRoot = "F:\tes3mp.Win64.release.0.8.1",
    [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo "scavenger-scramble"
$customDir = Join-Path $ServerRoot "server\scripts\custom"
$target = Join-Path $customDir "scavenger-scramble"

if (-not (Test-Path $customDir)) {
    throw "Custom scripts folder not found: $customDir"
}
if (-not (Test-Path (Join-Path $source "data\locations\index.lua"))) {
    throw "Generated data missing. Run: python tools\gen_data.py first."
}

if (-not $SkipBackup) {
    $old = Get-ChildItem -Path $customDir -Directory | Where-Object { $_.Name -like "scavenger-scramble*" }
    if ($old) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupDir = Join-Path $customDir "backup\$stamp"
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        foreach ($dir in $old) {
            Write-Host "Backing up $($dir.FullName) -> $backupDir"
            Move-Item -Path $dir.FullName -Destination $backupDir
        }
    }
}

$dataCustom = Join-Path $ServerRoot "server\data\custom"
if (-not (Test-Path $dataCustom)) {
    New-Item -ItemType Directory -Force -Path $dataCustom | Out-Null
    Write-Host "Created $dataCustom for the mod's state files"
}

Write-Host "Deploying $source -> $target"
& robocopy $source $target /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }

$customScripts = Join-Path $ServerRoot "server\scripts\customScripts.lua"
$requireLine = 'require("custom.scavenger-scramble.main")'
$content = Get-Content $customScripts -Raw
if ($content -notmatch "scavenger-scramble") {
    Add-Content -Path $customScripts -Value "`n$requireLine" -Encoding utf8
    Write-Host "Added require line to customScripts.lua"
} else {
    Write-Host "customScripts.lua already loads the mod"
}

Write-Host "Done. Restart tes3mp-server.exe to load the new version."
