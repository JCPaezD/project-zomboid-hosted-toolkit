param(
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$IncludeDb = $true,
    [switch]$IncludePlayerFolder = $true,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Reset Hosted World" "pz-reset-hosted-world"

Assert-PZTNoGameProcesses
$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName

$saveDir = Join-Path $paths.SavesDir $saveName
$playerDir = Join-Path $paths.SavesDir "${saveName}_player"
$dbFile = Join-Path $paths.DbDir "$ProfileName.db"

Write-PZTStep "Profile: $ProfileName" "pz-reset-hosted-world"
Write-PZTStep "Save:    $saveDir" "pz-reset-hosted-world"
Write-PZTStep "Player:  $playerDir" "pz-reset-hosted-world"
Write-PZTStep "DB:      $dbFile" "pz-reset-hosted-world"
$playersDb = Join-Path $saveDir "players.db"
$players = @(Get-PZTPlayersInfo -PlayersDb $playersDb)
Write-Host ""
Write-Host "=== Data that would be moved/reset ==="
$saveSummary = Get-PZTTreeSummary -Path $saveDir
$playerSummary = Get-PZTTreeSummary -Path $playerDir
Write-Host ("Save folder:   exists={0}, files={1}, sizeMB={2}, lastWrite={3}" -f $saveSummary.Exists, $saveSummary.Files, $saveSummary.SizeMB, $saveSummary.LastWrite)
Write-Host ("Player folder: exists={0}, files={1}, sizeMB={2}, lastWrite={3}" -f $playerSummary.Exists, $playerSummary.Files, $playerSummary.SizeMB, $playerSummary.LastWrite)
Write-Host ("Players rows:  {0}" -f $players.Count)
if ($players.Count -gt 0) { $players | Select-Object username, playerIndex, name, steamid, isDead, x, y, z | Format-Table -AutoSize }

if ($WhatIf) {
    Write-PZTStep "WhatIf: no files will be moved." "pz-reset-hosted-world"
    exit 0
}

$backupDir = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$ProfileName-world-before-reset"
New-Item -ItemType Directory -Path (Join-Path $backupDir "Saves\Multiplayer") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupDir "db") -Force | Out-Null

if (Test-Path -LiteralPath $saveDir) {
    Move-Item -LiteralPath $saveDir -Destination (Join-Path $backupDir "Saves\Multiplayer") -Force
}
if ($IncludePlayerFolder -and (Test-Path -LiteralPath $playerDir)) {
    Move-Item -LiteralPath $playerDir -Destination (Join-Path $backupDir "Saves\Multiplayer") -Force
}
if ($IncludeDb -and (Test-Path -LiteralPath $dbFile)) {
    Move-Item -LiteralPath $dbFile -Destination (Join-Path $backupDir "db") -Force
}

$summary = Get-PZTTreeSummary -Path $backupDir
Write-PZTStep "World reset complete. Moved $($summary.Files) files, $($summary.SizeMB) MB." "pz-reset-hosted-world"
Write-PZTStep "Backup: $backupDir" "pz-reset-hosted-world"
Write-PZTStep "Next launch should create a fresh world for this profile." "pz-reset-hosted-world"
