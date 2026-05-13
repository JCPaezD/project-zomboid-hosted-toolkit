param(
    [Parameter(Mandatory=$true)][string]$ProfileName,
    [string]$ZomboidRoot,
    [string]$BackupRoot,
    [switch]$IncludeSave = $true,
    [switch]$IncludePlayerFolder = $true,
    [switch]$IncludeDb = $true,
    [switch]$HashManifest,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Backup Profile" "pz-backup-profile"

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -BackupRoot $BackupRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $ProfileName
$saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $ProfileName
$backupDir = Join-Path $paths.BackupRoot ("profile-$ProfileName-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$lang = Get-PZTLanguage

Write-PZTStep ($(if ($lang -eq "es") { "Perfil: $ProfileName" } else { "Profile: $ProfileName" })) "pz-backup-profile"
Write-PZTStep "Backup:  $backupDir" "pz-backup-profile"
if ($HashManifest) {
    Write-PZTStep ($(if ($lang -eq "es") { "HashManifest activado: la verificacion SHA256 puede tardar mucho en saves grandes." } else { "HashManifest enabled: SHA256 verification can take a long time on large saves." })) "pz-backup-profile"
}
if ($WhatIf) { Write-PZTStep ($(if ($lang -eq "es") { "WhatIf: no se copiara ningun archivo." } else { "WhatIf: no files will be copied." })) "pz-backup-profile"; exit 0 }

New-Item -ItemType Directory -Path (Join-Path $backupDir "Server") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupDir "Saves\Multiplayer") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $backupDir "db") -Force | Out-Null
Set-PZTTextNoBom -Path (Join-Path $backupDir "BACKUP_STATUS.txt") -Content "INCOMPLETE`nStarted: $(Get-Date -Format o)"

Write-PZTStep ($(if ($lang -eq "es") { "Copiando archivos del perfil..." } else { "Copying server profile files..." })) "pz-backup-profile"
foreach ($file in Get-PZTProfileFilePaths -ServerDir $paths.ServerDir -ProfileName $ProfileName) {
    Copy-PZTFileIfExists -Path $file -Destination (Join-Path $backupDir "Server") | Out-Null
}

if ($IncludeSave) {
    Write-PZTStep ($(if ($lang -eq "es") { "Copiando carpeta de save..." } else { "Copying save folder..." })) "pz-backup-profile"
    Copy-PZTDirectoryWithProgress -Source (Join-Path $paths.SavesDir $saveName) -DestinationParent (Join-Path $backupDir "Saves\Multiplayer") -Scope "pz-backup-profile" | Out-Null
}
if ($IncludePlayerFolder) {
    Write-PZTStep ($(if ($lang -eq "es") { "Copiando carpeta player opcional..." } else { "Copying optional player folder..." })) "pz-backup-profile"
    Copy-PZTDirectoryWithProgress -Source (Join-Path $paths.SavesDir "${saveName}_player") -DestinationParent (Join-Path $backupDir "Saves\Multiplayer") -Scope "pz-backup-profile" | Out-Null
}
if ($IncludeDb) {
    Write-PZTStep ($(if ($lang -eq "es") { "Copiando base de datos del perfil..." } else { "Copying profile database..." })) "pz-backup-profile"
    Copy-PZTFileIfExists -Path (Join-Path $paths.DbDir "$ProfileName.db") -Destination (Join-Path $backupDir "db") | Out-Null
}

Write-PZTStep ($(if ($lang -eq "es") { "Escribiendo manifest..." } else { "Writing manifest..." })) "pz-backup-profile"
$manifest = @()
$manifest += "ProfileName: $ProfileName"
$manifest += "SaveName: $saveName"
$manifest += "Created: $(Get-Date -Format o)"
$manifest += "ZomboidRoot: $($paths.ZomboidRoot)"
$manifest += "HashManifest: $($HashManifest.IsPresent)"
$manifest += ""
$manifest += "Files:"
Get-ChildItem -LiteralPath $backupDir -Recurse -File -Force | ForEach-Object {
    if ($_.Name -eq "MANIFEST.txt") { return }
    $relative = $_.FullName.Substring($backupDir.Length + 1)
    if ($HashManifest) {
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        $manifest += "$($hash.Hash)  $relative"
    }
    else {
        $manifest += "$($_.Length)  $relative"
    }
}
Set-PZTTextNoBom -Path (Join-Path $backupDir "MANIFEST.txt") -Content ($manifest -join [Environment]::NewLine)
Set-PZTTextNoBom -Path (Join-Path $backupDir "BACKUP_STATUS.txt") -Content "COMPLETE`nCompleted: $(Get-Date -Format o)"

$summary = Get-PZTTreeSummary -Path $backupDir
Write-PZTStep ($(if ($lang -eq "es") { "Backup completo: $($summary.Files) archivos, $($summary.SizeMB) MB" } else { "Backup complete: $($summary.Files) files, $($summary.SizeMB) MB" })) "pz-backup-profile"
