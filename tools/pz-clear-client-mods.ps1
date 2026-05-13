param(
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$ConfirmClear,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Clear Client Mods" "pz-clear-client-mods"

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
$defaultPath = Join-Path $paths.ClientModsDir "default.txt"

$emptyContent = @"
VERSION = 1,

mods
{
}

maps
{
}
"@

Assert-PZTNoGameProcesses

if (-not (Test-Path -LiteralPath $paths.ClientModsDir)) {
    throw "Client mods directory not found: $($paths.ClientModsDir)"
}

$active = if (Test-Path -LiteralPath $defaultPath) {
    $matches = @(Select-String -LiteralPath $defaultPath -Pattern '^\s*mod\s*=' -AllMatches)
    ($matches | ForEach-Object { $_.Matches.Count } | Measure-Object -Sum).Sum
} else { 0 }

Write-PZTStep "Client global mod list: $defaultPath" "pz-clear-client-mods"
Write-PZTStep "Active mod lines detected: $active" "pz-clear-client-mods"
if ($WhatIf) { Write-PZTStep "WhatIf: no file will be changed." "pz-clear-client-mods"; exit 0 }
if (-not $ConfirmClear) {
    Write-PZTStep "Refusing real clear-client-mods without -ConfirmClear. Run with -WhatIf first, then add -ConfirmClear when the target file is correct." "pz-clear-client-mods"
    exit 1
}

$backupDir = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "client-default-mods"
if (Test-Path -LiteralPath $defaultPath) {
    Copy-Item -LiteralPath $defaultPath -Destination (Join-Path $backupDir "default.txt") -Force
}

Set-PZTTextNoBom -Path $defaultPath -Content $emptyContent
Write-PZTStep "Cleared client global mods. Hosted server profiles were not modified." "pz-clear-client-mods"
Write-PZTStep "Backup: $backupDir" "pz-clear-client-mods"
