param(
    [string]$ZomboidRoot,
    [ValidateSet("startup","version","period")]
    [string]$Type,
    [string]$ProfileName,
    [int]$Limit = 20,
    [switch]$Details,
    [switch]$AllProfiles,
    [switch]$NoCache,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) {
    Write-PZTTitle "PZ Hosted Toolkit - Inspect Auto Backups" "pz-inspect-auto-backups"
}

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot
$lang = Get-PZTLanguage
if (-not $Json -and -not $ProfileName -and -not $AllProfiles) {
    $profiles = @(Get-PZTHostedProfileNames -ServerDir $paths.ServerDir)
    $allLabel = Get-PZTText "All profiles" "Todos los perfiles"
    $choice = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose profile to inspect auto-backups" "Elige perfil para inspeccionar backups auto") -Items @($profiles + $allLabel) -AllowCancel
    if (-not $choice) { Write-PZTStep (Get-PZTText "Cancelled." "Cancelado.") "pz-inspect-auto-backups"; exit 0 }
    if ($choice -ne $allLabel) { $ProfileName = $choice }
}
if (-not $Json) {
    Write-PZTStep ($(if ($lang -eq "es") { "Raiz Zomboid: $($paths.ZomboidRoot)" } else { "Zomboid root: $($paths.ZomboidRoot)" })) "pz-inspect-auto-backups"
    if ($Type) { Write-PZTStep ($(if ($lang -eq "es") { "Tipo: $Type" } else { "Type: $Type" })) "pz-inspect-auto-backups" }
    if ($ProfileName) { Write-PZTStep ($(if ($lang -eq "es") { "Filtro de perfil: $ProfileName" } else { "Profile filter: $ProfileName" })) "pz-inspect-auto-backups" }
    Write-PZTStep ($(if ($lang -eq "es") { "Leyendo ZIPs de backups automaticos..." } else { "Reading native auto-backup ZIPs..." })) "pz-inspect-auto-backups"
}
$items = @(Get-PZTAutoBackups -ZomboidRoot $paths.ZomboidRoot -Type $Type -Limit $Limit -ProgressScope $(if ($Json) { $null } else { "pz-inspect-auto-backups" }) -NoCache:$NoCache)
if ($ProfileName) {
    $items = @($items | Where-Object { $_.ServerName -eq $ProfileName })
}
$indexedItems = @()
for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items[$i]
    $item | Add-Member -NotePropertyName "Index" -NotePropertyValue ($i + 1) -Force
    $indexedItems += $item
}
$items = $indexedItems

if ($Json) {
    $items | ConvertTo-Json -Depth 12
    exit 0
}

Write-PZTStep ($(if ($lang -eq "es") { "Backups encontrados: $($items.Count)" } else { "Backups found: $($items.Count)" })) "pz-inspect-auto-backups"

if ($items.Count -eq 0) {
    Write-PZTStep ($(if ($lang -eq "es") { "No se encontraron backups automaticos de PZ." } else { "No native PZ auto backups were found." })) "pz-inspect-auto-backups"
    exit 0
}

Write-Host ""
Write-Host (Get-PZTText "=== Auto backups ===" "=== Backups auto ===")
$rows = @($items | ForEach-Object {
    $profileEntries = $_.ProfileEntries
    $zipTime = try { ([datetime]$_.LastWriteTime).ToString("yyyy-MM-dd HH:mm") } catch { [string]$_.LastWriteTime }
    [pscustomobject]@{
        Id = $_.Index
        Type = $_.Type
        File = $_.Name
        BackupTime = Format-PZTAutoBackupTime -BackupInfo $_
        ZipTime = $zipTime
        ServerName = $_.ServerName
        SizeMB = $_.SizeMB
        SaveFiles = if ($profileEntries) { $profileEntries.SaveEntries } else { "" }
        ServerFiles = if ($profileEntries) { $profileEntries.ServerEntries } else { "" }
        DbFiles = if ($profileEntries) { $profileEntries.DbEntries } else { "" }
    }
})
$rows | Format-Table -AutoSize

Write-Host ""
Write-Host (Get-PZTText "=== Notes ===" "=== Notas ===")
Write-PZTStep ($(if ($lang -eq "es") { "Estos ZIP pueden contener estado global (Server/db/Lua/mods). El toolkit no recomienda extraerlos completos en entornos hosted locales." } else { "These ZIPs may contain global state (Server/db/Lua/mods). The toolkit does not recommend full extraction in local hosted environments." })) "pz-inspect-auto-backups"
Write-PZTStep ($(if ($lang -eq "es") { "Para rollback de un perfil, usa restauracion selectiva del ServerName del readme." } else { "For profile rollback, use selective restore for the readme ServerName." })) "pz-inspect-auto-backups"

Write-Host ""
Write-Host (Get-PZTText "=== Comparison ===" "=== Comparativa ===")
$baseline = $items | Select-Object -First 1
$diffs = New-Object System.Collections.Generic.List[string]
foreach ($item in $items | Select-Object -Skip 1) {
    $baselineReadme = if ($baseline -and $baseline.Readme) { $baseline.Readme } else { [pscustomobject]@{} }
    $itemReadme = if ($item -and $item.Readme) { $item.Readme } else { [pscustomobject]@{} }
    $baselineProfile = if ($baseline -and $baseline.ProfileEntries) { $baseline.ProfileEntries } else { [pscustomobject]@{} }
    $itemProfile = if ($item -and $item.ProfileEntries) { $item.ProfileEntries } else { [pscustomobject]@{} }
    $baselineCounts = if ($baseline -and $baseline.EntryCounts) { $baseline.EntryCounts } else { [pscustomobject]@{} }
    $itemCounts = if ($item -and $item.EntryCounts) { $item.EntryCounts } else { [pscustomobject]@{} }
    foreach ($field in @(
        @{Name="ServerVersion"; A=$(if ($baselineReadme.PSObject.Properties.Match("CurrentServerVersion").Count -gt 0) { $baselineReadme.CurrentServerVersion } else { $null }); B=$(if ($itemReadme.PSObject.Properties.Match("CurrentServerVersion").Count -gt 0) { $itemReadme.CurrentServerVersion } else { $null })},
        @{Name="WorldVersion"; A=$(if ($baselineReadme.PSObject.Properties.Match("BackupWorldVersion").Count -gt 0) { $baselineReadme.BackupWorldVersion } else { $null }); B=$(if ($itemReadme.PSObject.Properties.Match("BackupWorldVersion").Count -gt 0) { $itemReadme.BackupWorldVersion } else { $null })},
        @{Name="SaveName"; A=$(if ($baselineProfile.PSObject.Properties.Match("SaveNameInZip").Count -gt 0) { $baselineProfile.SaveNameInZip } else { $null }); B=$(if ($itemProfile.PSObject.Properties.Match("SaveNameInZip").Count -gt 0) { $itemProfile.SaveNameInZip } else { $null })},
        @{Name="ServerFiles"; A=$(if ($baselineProfile.PSObject.Properties.Match("ServerEntries").Count -gt 0) { $baselineProfile.ServerEntries } else { $null }); B=$(if ($itemProfile.PSObject.Properties.Match("ServerEntries").Count -gt 0) { $itemProfile.ServerEntries } else { $null })},
        @{Name="DbFiles"; A=$(if ($baselineProfile.PSObject.Properties.Match("DbEntries").Count -gt 0) { $baselineProfile.DbEntries } else { $null }); B=$(if ($itemProfile.PSObject.Properties.Match("DbEntries").Count -gt 0) { $itemProfile.DbEntries } else { $null })},
        @{Name="PlayerFiles"; A=$(if ($baselineProfile.PSObject.Properties.Match("PlayerEntries").Count -gt 0) { $baselineProfile.PlayerEntries } else { $null }); B=$(if ($itemProfile.PSObject.Properties.Match("PlayerEntries").Count -gt 0) { $itemProfile.PlayerEntries } else { $null })},
        @{Name="GlobalServerEntries"; A=$(if ($baselineCounts.PSObject.Properties.Match("Server").Count -gt 0) { $baselineCounts.Server } else { $null }); B=$(if ($itemCounts.PSObject.Properties.Match("Server").Count -gt 0) { $itemCounts.Server } else { $null })},
        @{Name="GlobalDbEntries"; A=$(if ($baselineCounts.PSObject.Properties.Match("Db").Count -gt 0) { $baselineCounts.Db } else { $null }); B=$(if ($itemCounts.PSObject.Properties.Match("Db").Count -gt 0) { $itemCounts.Db } else { $null })},
        @{Name="LuaEntries"; A=$(if ($baselineCounts.PSObject.Properties.Match("Lua").Count -gt 0) { $baselineCounts.Lua } else { $null }); B=$(if ($itemCounts.PSObject.Properties.Match("Lua").Count -gt 0) { $itemCounts.Lua } else { $null })},
        @{Name="ModsEntries"; A=$(if ($baselineCounts.PSObject.Properties.Match("Mods").Count -gt 0) { $baselineCounts.Mods } else { $null }); B=$(if ($itemCounts.PSObject.Properties.Match("Mods").Count -gt 0) { $itemCounts.Mods } else { $null })}
    )) {
        if ("$($field.A)" -ne "$($field.B)") {
            $diffs.Add("[1] vs [$($item.Index)] $($field.Name): '$($field.A)' -> '$($field.B)'") | Out-Null
        }
    }
}
if ($diffs.Count -eq 0) {
    Write-PZTStep (Get-PZTText "No metadata differences found besides time, size, file counts, and ID/order." "No hay diferencias de metadatos salvo hora, tamano, conteos de archivos e ID/orden.") "pz-inspect-auto-backups"
}
else {
    $diffs | ForEach-Object { Write-Host "- $_" }
}

if ($Details) {
    foreach ($item in $items) {
        Write-Host ""
        Write-Host ("=== [{0}] {1}\{2} ===" -f $item.Index, $item.Type, $item.Name) -ForegroundColor Cyan
        Write-Host "  Path:       $($item.Path)"
        Write-Host "  ServerName: $($item.ServerName)"
        if ($item.Readme) {
            Write-Host "  Backup:    $($item.Readme.BackupTime)"
            Write-Host "  PZ/world:  server=$($item.Readme.CurrentServerVersion), world=$($item.Readme.BackupWorldVersion)"
        }
        if ($item.EntryCounts) {
            Write-Host "  ZIP:       total=$($item.EntryCounts.Total), Saves=$($item.EntryCounts.Saves), Server=$($item.EntryCounts.Server), db=$($item.EntryCounts.Db), Lua=$($item.EntryCounts.Lua), mods=$($item.EntryCounts.Mods)"
        }
        if ($item.ProfileEntries) {
            Write-Host "  Profile:   saveName=$($item.ProfileEntries.SaveNameInZip), saveFiles=$($item.ProfileEntries.SaveEntries), playerFiles=$($item.ProfileEntries.PlayerEntries), serverFiles=$($item.ProfileEntries.ServerEntries), dbFiles=$($item.ProfileEntries.DbEntries)"
        }
    }
}

