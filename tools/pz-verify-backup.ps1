param(
    [Parameter(Mandatory=$true)][string]$BackupPath
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Verify Backup" "pz-verify-backup"

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-PZTStep "Backup folder not found: $BackupPath" "pz-verify-backup"
    exit 1
}

$backup = (Resolve-Path -LiteralPath $BackupPath).Path
$manifest = Join-Path $backup "MANIFEST.txt"
$statusFile = Join-Path $backup "BACKUP_STATUS.txt"
$serverDir = Join-Path $backup "Server"
$savesDir = Join-Path $backup "Saves\Multiplayer"
$dbDir = Join-Path $backup "db"

$status = if (Test-Path -LiteralPath $statusFile) {
    (Get-Content -LiteralPath $statusFile -First 1)
}
elseif (Test-Path -LiteralPath $manifest) {
    "UNKNOWN-OLD-BACKUP"
}
else {
    "INCOMPLETE-OR-LEGACY"
}

$serverFiles = @(Get-ChildItem -LiteralPath $serverDir -File -Force -ErrorAction SilentlyContinue)
$saveProfiles = @(Get-ChildItem -LiteralPath $savesDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*_player" })
$playerFolders = @(Get-ChildItem -LiteralPath $savesDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*_player" })
$dbFiles = @(Get-ChildItem -LiteralPath $dbDir -File -Filter *.db -Force -ErrorAction SilentlyContinue)
$summary = Get-PZTTreeSummary -Path $backup

Write-PZTStep "Backup: $backup" "pz-verify-backup"
Write-PZTStep "Status: $status" "pz-verify-backup"
$manifestStatus = if (Test-Path -LiteralPath $manifest) { "present" } else { "missing" }
Write-PZTStep "Manifest: $manifestStatus" "pz-verify-backup"
Write-PZTStep "Files: $($summary.Files), SizeMB: $($summary.SizeMB)" "pz-verify-backup"
Write-Host ""
Write-Host "=== Contents ==="
Write-Host ("Server files:   {0}" -f $serverFiles.Count)
Write-Host ("Save folders:   {0} ({1})" -f $saveProfiles.Count, (($saveProfiles.Name) -join ", "))
Write-Host ("Player folders: {0} ({1})" -f $playerFolders.Count, (($playerFolders.Name) -join ", "))
Write-Host ("DB files:       {0} ({1})" -f $dbFiles.Count, (($dbFiles.Name) -join ", "))

if ($status -ne "COMPLETE") {
    Write-Host ""
    Write-PZTStep "This backup is not marked COMPLETE. Do not rely on it as a verified restore point." "pz-verify-backup"
    exit 2
}
