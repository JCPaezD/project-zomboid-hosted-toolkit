param(
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) { Write-PZTTitle "PZ Hosted Toolkit - Profile Health Check" "pz-health-check" }

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot
if (-not $ProfileName) {
    $ProfileName = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose hosted profile to health-check" "Elige perfil hosted para comprobar salud") -Items (Get-PZTHostedProfileNames -ServerDir $paths.ServerDir) -AllowCancel
    if (-not $ProfileName) { exit 0 }
}

$health = Get-PZTProfileHealth -Paths $paths -ProfileName $ProfileName

if ($Json) {
    $health | ConvertTo-Json -Depth 6
    exit 0
}

Write-PZTStep ((Get-PZTText "Profile: {0}" "Perfil: {0}") -f $health.Profile) "pz-health-check"
$displayStatus = switch ($health.Status) {
    "OK" { "OK" }
    "Warning" { Get-PZTText "Warning" "Aviso" }
    "Needs attention" { Get-PZTText "Needs attention" "Requiere atencion" }
    default { $health.Status }
}
Write-PZTStep ((Get-PZTText "Status:  {0}" "Estado:  {0}") -f $displayStatus) "pz-health-check"
Write-PZTStep "PublicName: $($health.PublicName)" "pz-health-check"
if ($health.Profile -ne $health.SaveName) { Write-PZTStep ((Get-PZTText "Save folder name: {0}" "Nombre de carpeta de save: {0}") -f $health.SaveName) "pz-health-check" }

Write-Host ""
Write-Host (Get-PZTText "=== Counts ===" "=== Conteos ===")
Write-Host ("Mods:           {0}" -f $health.Counts.Mods)
Write-Host ("Workshop items: {0}" -f $health.Counts.WorkshopItems)
Write-Host ((Get-PZTText "Map entries:    {0}" "Entradas de mapa: {0}") -f $health.Counts.Maps)

Write-Host ""
Write-Host (Get-PZTText "=== Files ===" "=== Archivos ===")
$health.Exists.PSObject.Properties | ForEach-Object {
    Write-Host ("{0,-12} {1}" -f $_.Name, $(if ($_.Value) { "OK" } else { (Get-PZTText "missing" "falta") }))
}

Write-Host ""
Write-Host (Get-PZTText "=== Findings ===" "=== Hallazgos ===")
    if (@($health.Issues).Count -eq 0) {
    Write-Host (Get-PZTText "- OK: no obvious profile consistency issues found." "- OK: no se han encontrado problemas obvios de consistencia del perfil.")
}
else {
    $health.Issues | ForEach-Object {
        Write-Host ("- {0}: {1} - {2}" -f $_.Severity, $_.Code, $_.Message)
    }
}

Write-Host ""
Write-Host (Get-PZTText "Notes:" "Notas:")
Write-Host (Get-PZTText "- This checks profile file consistency; it does not prove that every mod is compatible or that a save is safe." "- Esto comprueba consistencia de archivos del perfil; no demuestra que todos los mods sean compatibles ni que el save sea seguro.")
Write-Host (Get-PZTText "- Back up before changing active gameplay profiles." "- Haz backup antes de cambiar perfiles de partida activos.")
