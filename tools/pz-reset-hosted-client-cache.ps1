param(
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$ConfirmReset,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Reset Hosted Client Cache" "pz-reset-hosted-client-cache"

Assert-PZTNoGameProcesses
$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
if (-not $ProfileName) {
    $ProfileName = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose hosted profile to reset client cache" "Elige perfil hosted para resetear cache cliente") -Items (Get-PZTHostedProfileNames -ServerDir $paths.ServerDir) -AllowCancel
    if (-not $ProfileName) { Write-PZTStep (Get-PZTText "Cancelled." "Cancelado.") "pz-reset-hosted-client-cache"; exit 0 }
}
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$playerDir = Join-Path $paths.SavesDir "${saveName}_player"

Write-PZTStep ((Get-PZTText "Profile: {0}" "Perfil: {0}") -f $ProfileName) "pz-reset-hosted-client-cache"
if ($saveName -ne $ProfileName) {
    Write-PZTStep ((Get-PZTText "Save folder name: {0}" "Nombre de carpeta de save: {0}") -f $saveName) "pz-reset-hosted-client-cache"
}
Write-PZTStep ((Get-PZTText "Hosted client cache: {0}" "Cache cliente hosted: {0}") -f $playerDir) "pz-reset-hosted-client-cache"

$summary = Get-PZTTreeSummary -Path $playerDir
Write-Host ""
Write-Host (Get-PZTText "=== Hosted client cache state ===" "=== Estado de cache cliente hosted ===") -ForegroundColor Cyan
Write-Host ("Exists:    {0}" -f $summary.Exists)
Write-Host ("Files:     {0}" -f $summary.Files)
Write-Host ("Size MB:   {0}" -f $summary.SizeMB)
Write-Host ("LastWrite: {0}" -f $summary.LastWrite)
Write-Host ""
Write-Host (Get-PZTText `
    "This folder is local hosted-client state, not the server save restored by native PZ auto-backups." `
    "Esta carpeta es estado local del cliente hosted, no el save servidor restaurado por los backups automaticos nativos de PZ.")
Write-Host (Get-PZTText `
    "Reset it only for map/chunk download hangs, stale client cache after restore, or client-local map/cache issues." `
    "Reseteala solo para bloqueos de descarga de mapa/chunks, cache cliente obsoleta tras restore, o problemas locales de mapa/cache.")
Write-Host (Get-PZTText `
    "The operation moves the folder into a toolkit backup; it does not delete the server world or players.db." `
    "La operacion mueve la carpeta a un backup del toolkit; no borra el mundo servidor ni players.db.")

if (-not $summary.Exists) {
    Write-PZTStep (Get-PZTText "No hosted client cache folder exists; nothing to reset." "No existe carpeta de cache cliente hosted; no hay nada que resetear.") "pz-reset-hosted-client-cache"
    exit 0
}

if ($WhatIf) {
    Write-Host ""
    Write-Host (Get-PZTText "=== Simulated reset ===" "=== Reset simulado ===") -ForegroundColor Yellow
    Write-Host ((Get-PZTText "Would move: {0}" "Moveria: {0}") -f $playerDir)
    Write-Host (Get-PZTText "Would create a toolkit backup first and write an action-log entry only during the real reset." "Crearia primero un backup del toolkit y escribiria log de accion solo durante el reset real.")
    exit 0
}

if (-not $ConfirmReset) {
    Write-PZTStep (Get-PZTText `
        "Refusing real client-cache reset without -ConfirmReset. Run with -WhatIf first, then add -ConfirmReset if this is the intended cache." `
        "No se ejecuta el reset real de cache cliente sin -ConfirmReset. Ejecuta primero -WhatIf y despues anade -ConfirmReset si esta es la cache correcta.") "pz-reset-hosted-client-cache"
    exit 1
}

$backupDir = New-PZTBackupDir -BackupRoot $paths.BackupRoot -Name "$ProfileName-client-cache-before-reset"
$backupSaves = Join-Path $backupDir "Saves\Multiplayer"
New-Item -ItemType Directory -Path $backupSaves -Force | Out-Null

Write-PZTStep (Get-PZTText "Moving hosted client cache into toolkit backup..." "Moviendo cache cliente hosted al backup del toolkit...") "pz-reset-hosted-client-cache"
Move-Item -LiteralPath $playerDir -Destination $backupSaves -Force

$backupSummary = Get-PZTTreeSummary -Path $backupDir
Set-PZTTextNoBom -Path (Join-Path $backupDir "BACKUP_STATUS.txt") -Content "COMPLETE`nCompleted: $(Get-Date -Format o)`nType: hosted-client-cache-reset`nProfileName: $ProfileName`nSaveName: $saveName"
Write-PZTActionLog -Action "reset-hosted-client-cache" -Status "Completed" -Data @{
    ProfileName = $ProfileName
    SaveName = $saveName
    SourcePath = $playerDir
    BackupPath = $backupDir
    Files = $summary.Files
    SizeMB = $summary.SizeMB
}

Write-PZTStep ((Get-PZTText "Client cache reset complete. Moved {0} files, {1} MB." "Reset de cache cliente completado. Movidos {0} archivos, {1} MB.") -f $summary.Files, $summary.SizeMB) "pz-reset-hosted-client-cache"
Write-PZTStep ((Get-PZTText "Backup: {0}" "Backup: {0}") -f $backupDir) "pz-reset-hosted-client-cache"
Write-PZTStep (Get-PZTText "Next PZ launch should recreate the hosted client cache for this profile." "El proximo arranque de PZ deberia recrear la cache cliente hosted de este perfil.") "pz-reset-hosted-client-cache"
