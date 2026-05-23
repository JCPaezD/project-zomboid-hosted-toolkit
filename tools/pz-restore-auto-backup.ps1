param(
    [string]$BackupZip,
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$Overwrite,
    [switch]$ConfirmRestore,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Restore Auto Backup" "pz-restore-auto-backup"

function Read-AutoBackupZipForRestore {
    param(
        [Parameter(Mandatory=$true)][string]$ZomboidRoot,
        [string]$ProfileName
    )

    $items = @(Get-PZTAutoBackups -ZomboidRoot $ZomboidRoot -Limit 30 -ProgressScope "pz-restore-auto-backup")
    if ($ProfileName) { $items = @($items | Where-Object { $_.ServerName -eq $ProfileName }) }
    if ($items.Count -eq 0) {
        return (Read-Host (Get-PZTText "Auto-backup ZIP path" "Ruta del ZIP de backup automatico"))
    }

    $labels = @($items | ForEach-Object -Begin { $i = 0 } -Process {
        $i++
        "[{0}] {1,-7} {2,-12} {3,-16} {4,8:N2} MB  {5}" -f $i, $_.Type, $_.Name, (Format-PZTAutoBackupTime -BackupInfo $_), $_.SizeMB, $_.ServerName
    })
    $labels += (Get-PZTText "Type a ZIP path manually" "Escribir ruta de ZIP manualmente")
    $choice = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose native PZ auto backup to restore" "Elige backup automatico de PZ a restaurar") -Items $labels -AllowCancel
    if (-not $choice) { return $null }
    if ($choice -eq "Type a ZIP path manually" -or $choice -eq "Escribir ruta de ZIP manualmente") {
        return (Read-Host (Get-PZTText "ZIP path" "Ruta del ZIP"))
    }
    $index = [array]::IndexOf($labels, $choice)
    return $items[$index].Path
}

function Write-RestoreWarningBox {
    param([Parameter(Mandatory=$true)][string]$Message)

    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host (Get-PZTText "RESTORE IN PROGRESS - DO NOT CLOSE" "RESTAURACION EN CURSO - NO CIERRES") -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
    Write-Host (Get-PZTText `
        "Some steps can take several minutes and may look quiet while Windows copies or deletes many files." `
        "Algunos pasos pueden tardar varios minutos y parecer silenciosos mientras Windows copia o elimina muchos archivos.") -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host ""
}

function Copy-ZipEntryToFile {
    param(
        [Parameter(Mandatory=$true)]$Entry,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $inputStream = $Entry.Open()
    try {
        $outputStream = [System.IO.File]::Create($Destination)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    }
    finally {
        $inputStream.Dispose()
    }
}

function Get-ZipEntryNameNormalized {
    param([Parameter(Mandatory=$true)]$Entry)
    return ($Entry.FullName -replace '\\','/')
}

function Extract-ZipPrefix {
    param(
        [Parameter(Mandatory=$true)]$Zip,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )
    $count = 0
    foreach ($entry in $Zip.Entries) {
        $normalizedName = Get-ZipEntryNameNormalized -Entry $entry
        if (-not $normalizedName.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($normalizedName.EndsWith("/")) { continue }
        $relative = $normalizedName.Substring($Prefix.Length).TrimStart("/")
        if (-not $relative) { continue }
        if ($relative -match '(^|/)\.\.(/|$)') { throw "Unsafe zip entry path: $normalizedName" }
        $destination = Join-Path $DestinationRoot $relative
        Assert-PZTPathInside -Path $destination -Parent $DestinationRoot -Description "zip extraction target" | Out-Null
        Copy-ZipEntryToFile -Entry $entry -Destination $destination
        $count++
    }
    return $count
}

function Extract-ZipExactFile {
    param(
        [Parameter(Mandatory=$true)]$Zip,
        [Parameter(Mandatory=$true)][string]$EntryName,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry) {
        $entry = $Zip.Entries | Where-Object { (Get-ZipEntryNameNormalized -Entry $_) -ieq $EntryName } | Select-Object -First 1
    }
    if (-not $entry) { return $false }
    Copy-ZipEntryToFile -Entry $entry -Destination $Destination
    return $true
}

Assert-PZTNoGameProcesses

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
if (-not $BackupZip) {
    if (-not $ProfileName) {
        $profiles = Get-PZTHostedProfileNames -ServerDir $paths.ServerDir
        $ProfileName = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose hosted profile to restore in place" "Elige perfil hosted a restaurar in-place") -Items $profiles -AllowCancel
        if (-not $ProfileName) { Write-PZTStep "Cancelled." "pz-restore-auto-backup"; exit 0 }
    }
    $BackupZip = Read-AutoBackupZipForRestore -ZomboidRoot $paths.ZomboidRoot -ProfileName $ProfileName
    if (-not $BackupZip) { Write-PZTStep "Cancelled." "pz-restore-auto-backup"; exit 0 }
}

if (-not (Test-Path -LiteralPath $BackupZip)) { throw "Backup ZIP not found: $BackupZip" }
$resolvedZip = (Resolve-Path -LiteralPath $BackupZip).Path
$info = Get-PZTAutoBackupInfo -ZipPath $resolvedZip
if (-not $info.HasReadme -or -not $info.ServerName) {
    throw "Refusing restore because backup readme.txt is missing or does not include ServerName."
}

if (-not $ProfileName) { $ProfileName = $info.ServerName }
Assert-PZTProfileNameSafe -ProfileName $ProfileName
if ($ProfileName -ne $info.ServerName) {
    throw "Refusing restore to '$ProfileName' because backup ServerName is '$($info.ServerName)'. Native auto-backup restore is intentionally in-place only."
}

Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName

$targetSaveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$sourceSaveName = if ($info.ProfileEntries -and $info.ProfileEntries.SaveNameInZip) { $info.ProfileEntries.SaveNameInZip } else { $ProfileName }
$targetSaveDir = Join-Path $paths.SavesDir $targetSaveName
$targetDb = Join-Path $paths.DbDir "$ProfileName.db"
$targetServerFiles = Get-PZTProfileFilePaths -ServerDir $paths.ServerDir -ProfileName $ProfileName

Write-Host ""
Write-Host (Get-PZTText "=== Restore target ===" "=== Objetivo de restauracion ===") -ForegroundColor Cyan
Write-Host "  ZIP:       $resolvedZip"
Write-Host ("  " + (Get-PZTText "Type:      " "Tipo:      ") + $info.Type)
Write-Host "  Backup:    $($info.Readme.BackupTime)"
Write-Host "  Server:    $($info.ServerName)"
Write-Host ("  " + (Get-PZTText "Target:    " "Destino:   ") + $ProfileName)
if ($sourceSaveName -ne $ProfileName) { Write-Host "  ZIP save:  $sourceSaveName" }
if ($targetSaveName -ne $ProfileName) { Write-Host "  Save dir:  $targetSaveName" }
Write-Host ("  " + (Get-PZTText "Scope:     " "Alcance:   ") + (Get-PZTText "Server profile files, profile db, and hosted save folder only" "Archivos del perfil, db del perfil y carpeta save hosted"))
Write-Host ("  " + (Get-PZTText "Excluded:  " "Excluido:  ") + (Get-PZTText "global Lua/mods and unrelated Server/db entries" "Lua/mods globales y entradas Server/db no relacionadas"))

$missing = New-Object System.Collections.Generic.List[string]
if (-not $info.ProfileEntries -or $info.ProfileEntries.SaveEntries -eq 0) { $missing.Add("Saves/Multiplayer/$ProfileName/ or normalized save folder") | Out-Null }
if (-not $info.ProfileEntries -or $info.ProfileEntries.IniEntries -eq 0) { $missing.Add("Server/$ProfileName.ini") | Out-Null }
if (-not $info.ProfileEntries -or $info.ProfileEntries.SandboxEntries -eq 0) { $missing.Add("Server/${ProfileName}_SandboxVars.lua") | Out-Null }
if (-not $info.ProfileEntries -or $info.ProfileEntries.DbEntries -eq 0) { $missing.Add("db/$ProfileName.db") | Out-Null }
if ($missing.Count -gt 0) {
    throw "Backup is missing required profile content: $($missing -join ', ')"
}

$existingTargets = @()
$existingTargets += @($targetServerFiles | Where-Object { Test-Path -LiteralPath $_ })
if (Test-Path -LiteralPath $targetSaveDir) { $existingTargets += $targetSaveDir }
if (Test-Path -LiteralPath $targetDb) { $existingTargets += $targetDb }
if ($existingTargets.Count -gt 0 -and -not $Overwrite) {
    Write-PZTStep (Get-PZTText "Existing target paths: $($existingTargets.Count)" "Rutas de destino existentes: $($existingTargets.Count)") "pz-restore-auto-backup"
    Write-PZTStep (Get-PZTText `
        "Refusing to overwrite existing profile. Review -WhatIf output, then add -Overwrite and -ConfirmRestore." `
        "No se sobreescribe el perfil existente. Revisa la simulacion y despues usa -Overwrite y -ConfirmRestore.") "pz-restore-auto-backup"
    if (-not $WhatIf) { exit 1 }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host (Get-PZTText "=== Simulated restore ===" "=== Restauracion simulada ===") -ForegroundColor Yellow
    Write-Host ("  " + (Get-PZTText "No files will be copied, removed, or rewritten." "No se copiara, eliminara ni reescribira ningun archivo."))
    Write-Host ("  " + (Get-PZTText "Would create a toolkit safety backup of the current target first." "Primero crearia un backup de seguridad del perfil actual."))
    Write-Host ("  " + (Get-PZTText "Would replace:" "Reemplazaria:"))
    Write-Host "    - $targetSaveDir"
    Write-Host "    - $targetDb"
    foreach ($file in $targetServerFiles) { Write-Host "    - $file" }
    Write-Host ("  " + (Get-PZTText "Action log is not written for a simulation." "La simulacion no escribe en el log de acciones."))
    exit 0
}

if (-not $ConfirmRestore) {
    Write-PZTStep "Refusing real restore without -ConfirmRestore. Run with -WhatIf first, then add -Overwrite -ConfirmRestore." "pz-restore-auto-backup"
    exit 1
}
if (-not $Overwrite) {
    Write-PZTStep "Refusing real restore without -Overwrite. This action replaces current profile state." "pz-restore-auto-backup"
    exit 1
}

$warning = Get-PZTText `
    "Do not close this terminal during the restore. Closing it during the replacement step can leave a partial profile; the safety backup is there for recovery, but the operation should be allowed to finish." `
    "No cierres esta terminal durante la restauracion. Cerrarla durante el reemplazo puede dejar el perfil a medias; el backup de seguridad permite recuperar, pero la operacion debe terminar."
Write-RestoreWarningBox -Message $warning

$safetyScript = Join-Path $PSScriptRoot "pz-backup-profile.ps1"
Write-PZTStep (Get-PZTText `
    "Step 1/4: creating toolkit safety backup before restore. This can take several minutes on large saves..." `
    "Paso 1/4: creando backup de seguridad antes de restaurar. Puede tardar varios minutos en saves grandes...") "pz-restore-auto-backup"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $safetyScript -ProfileName $ProfileName -ZomboidRoot $paths.ZomboidRoot -BackupRoot $paths.BackupRoot
if ($LASTEXITCODE -ne 0) { throw "Safety backup failed; restore aborted." }
Write-PZTStep (Get-PZTText "Step 1/4 complete: safety backup created." "Paso 1/4 completado: backup de seguridad creado.") "pz-restore-auto-backup"

$tempRoot = Join-Path (Get-PZTToolkitRoot) "tmp\auto-restore-$ProfileName-$(Get-Date -Format yyyyMMdd-HHmmss)"
if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
Write-PZTStep (Get-PZTText `
    "Step 2/4: extracting selected profile content from ZIP to a temporary folder..." `
    "Paso 2/4: extrayendo el contenido seleccionado del ZIP a una carpeta temporal...") "pz-restore-auto-backup"
$zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
try {
    $tempServer = Join-Path $tempRoot "Server"
    $tempDb = Join-Path $tempRoot "db"
    $tempSave = Join-Path $tempRoot "save"
    New-Item -ItemType Directory -Path $tempServer,$tempDb,$tempSave -Force | Out-Null

    foreach ($leaf in @("$ProfileName.ini", "${ProfileName}_SandboxVars.lua", "${ProfileName}_spawnpoints.lua", "${ProfileName}_spawnregions.lua")) {
        [void](Extract-ZipExactFile -Zip $zip -EntryName "Server/$leaf" -Destination (Join-Path $tempServer $leaf))
    }
    [void](Extract-ZipExactFile -Zip $zip -EntryName "db/$ProfileName.db" -Destination (Join-Path $tempDb "$ProfileName.db"))
    $saveCount = Extract-ZipPrefix -Zip $zip -Prefix "Saves/Multiplayer/$sourceSaveName/" -DestinationRoot $tempSave
    if ($saveCount -eq 0) { throw "No save files extracted from backup." }
    Write-PZTStep (Get-PZTText "Extracted save files: $saveCount" "Archivos de save extraidos: $saveCount") "pz-restore-auto-backup"
}
finally {
    $zip.Dispose()
}
Write-PZTStep (Get-PZTText "Step 2/4 complete: ZIP content extracted." "Paso 2/4 completado: contenido extraido.") "pz-restore-auto-backup"

Write-RestoreWarningBox -Message $warning
Write-PZTStep (Get-PZTText `
    "Step 3/4: replacing current profile state. Deleting/copying the save folder can look quiet for several minutes..." `
    "Paso 3/4: reemplazando el estado actual del perfil. El borrado/copiado del save puede parecer silencioso durante varios minutos...") "pz-restore-auto-backup"
foreach ($sourceFile in Get-ChildItem -LiteralPath (Join-Path $tempRoot "Server") -File -Force) {
    $targetFile = Join-Path $paths.ServerDir $sourceFile.Name
    if (Test-Path -LiteralPath $targetFile) { Remove-Item -LiteralPath $targetFile -Force }
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetFile -Force
}
if (Test-Path -LiteralPath $targetDb) { Remove-Item -LiteralPath $targetDb -Force }
Copy-Item -LiteralPath (Join-Path $tempRoot "db\$ProfileName.db") -Destination $paths.DbDir -Force
if (Test-Path -LiteralPath $targetSaveDir) {
    Write-PZTStep (Get-PZTText "Deleting current save folder..." "Eliminando carpeta save actual...") "pz-restore-auto-backup"
    Remove-Item -LiteralPath $targetSaveDir -Recurse -Force
}
New-Item -ItemType Directory -Path (Split-Path -Parent $targetSaveDir) -Force | Out-Null
Write-PZTStep (Get-PZTText "Copying restored save folder into place..." "Copiando save restaurado a su ubicacion final...") "pz-restore-auto-backup"
Copy-Item -LiteralPath (Join-Path $tempRoot "save") -Destination $targetSaveDir -Recurse -Force
Write-PZTStep (Get-PZTText "Step 3/4 complete: profile state replaced." "Paso 3/4 completado: estado del perfil reemplazado.") "pz-restore-auto-backup"

Write-PZTStep (Get-PZTText "Cleaning temporary restore folder..." "Limpiando carpeta temporal de restauracion...") "pz-restore-auto-backup"
Remove-Item -LiteralPath $tempRoot -Recurse -Force

Write-PZTActionLog -Action "restore-auto-backup" -Status "Completed" -Data @{ ProfileName = $ProfileName; BackupZip = $resolvedZip; BackupTime = $info.Readme.BackupTime; BackupType = $info.Type }
Write-PZTStep (Get-PZTText "Selective auto-backup restore complete." "Restauracion selectiva del backup auto completada.") "pz-restore-auto-backup"

Write-PZTStep (Get-PZTText `
    "Step 4/4: running profile health-check now..." `
    "Paso 4/4: ejecutando health-check del perfil...") "pz-restore-auto-backup"
$healthScript = Join-Path $PSScriptRoot "pz-health-check.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $healthScript -ProfileName $ProfileName -ZomboidRoot $paths.ZomboidRoot
if ($LASTEXITCODE -ne 0) { throw "Health-check failed after restore. Review the output above before launching PZ." }
Write-PZTStep (Get-PZTText `
    "Restore flow complete. If health-check status is OK, launch PZ and test the save normally." `
    "Flujo de restauracion completado. Si el health-check esta OK, abre PZ y prueba la partida normalmente.") "pz-restore-auto-backup"
