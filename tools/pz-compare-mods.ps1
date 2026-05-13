param(
    [Parameter(Mandatory=$true)][string]$LeftProfile,
    [Parameter(Mandatory=$true)][string]$RightProfile,
    [string]$ZomboidRoot,
    [string]$WorkshopRoot,
    [int]$MaxItems = 30,
    [switch]$ShowCommon,
    [switch]$Detailed,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

if (-not $Json) { Write-PZTTitle "PZ Hosted Toolkit - Compare Profile Mods" "pz-compare-mods" }

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot -WorkshopRoot $WorkshopRoot
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $LeftProfile
Assert-PZTProfilePathsContained -Paths $paths -ProfileName $RightProfile
$leftIni = Join-Path $paths.ServerDir "$LeftProfile.ini"
$rightIni = Join-Path $paths.ServerDir "$RightProfile.ini"
if (-not (Test-Path -LiteralPath $leftIni)) { throw "Left profile INI not found: $leftIni" }
if (-not (Test-Path -LiteralPath $rightIni)) { throw "Right profile INI not found: $rightIni" }

function Compare-PZTList {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][string[]]$Left,
        [AllowNull()][string[]]$Right
    )

    if ($null -eq $Left) { $Left = @() }
    if ($null -eq $Right) { $Right = @() }

    $leftOnly = @($Left | Where-Object { $_ -notin $Right })
    $rightOnly = @($Right | Where-Object { $_ -notin $Left })
    $common = @($Left | Where-Object { $_ -in $Right })
    [pscustomobject]@{
        Name = $Name
        LeftCount = $Left.Count
        RightCount = $Right.Count
        CommonCount = $common.Count
        LeftOnly = $leftOnly
        RightOnly = $rightOnly
        Common = $common
    }
}

function Resolve-PZTWorkshopNames {
    param([string[]]$Ids)
    $contentRoot = if ($paths.WorkshopRoot) { Join-Path $paths.WorkshopRoot "content\108600" } else { $null }
    foreach ($id in $Ids) {
        $names = @()
        if ($contentRoot) {
            $itemRoot = Join-Path $contentRoot $id
            if (Test-Path -LiteralPath $itemRoot) {
                Get-ChildItem -LiteralPath $itemRoot -Filter mod.info -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $line = Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match '^name=' } | Select-Object -First 1
                    if ($line) { $names += ($line -replace '^name=', '') }
                }
            }
        }
        [pscustomobject]@{
            WorkshopId = $id
            Url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$id"
            LocalNames = (($names | Select-Object -Unique) -join " | ")
        }
    }
}

$modsLeft = @(Read-PZTIniList -IniPath $leftIni -Key "Mods")
$modsRight = @(Read-PZTIniList -IniPath $rightIni -Key "Mods")
$workLeft = @(Read-PZTIniList -IniPath $leftIni -Key "WorkshopItems")
$workRight = @(Read-PZTIniList -IniPath $rightIni -Key "WorkshopItems")
$mapLeft = @(Read-PZTIniList -IniPath $leftIni -Key "Map")
$mapRight = @(Read-PZTIniList -IniPath $rightIni -Key "Map")

$result = [pscustomobject]@{
    LeftProfile = $LeftProfile
    RightProfile = $RightProfile
    Mods = Compare-PZTList -Name "Mods" -Left $modsLeft -Right $modsRight
    WorkshopItems = Compare-PZTList -Name "WorkshopItems" -Left $workLeft -Right $workRight
    Map = Compare-PZTList -Name "Map" -Left $mapLeft -Right $mapRight
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    exit 0
}

$showLimit = if ($Detailed) { [int]::MaxValue } else { $MaxItems }
if ($showLimit -lt 1) { $showLimit = 30 }

Write-PZTStep ((Get-PZTText "Left:  {0}" "Izquierda: {0}") -f $LeftProfile) "pz-compare-mods"
Write-PZTStep ((Get-PZTText "Right: {0}" "Derecha:   {0}") -f $RightProfile) "pz-compare-mods"

foreach ($section in @($result.Mods, $result.WorkshopItems, $result.Map)) {
    Write-Host ""
    Write-Host ("=== {0} ===" -f $section.Name)
    Write-Host ((Get-PZTText "Counts: left={0}, right={1}, common={2}, left-only={3}, right-only={4}" "Conteos: izquierda={0}, derecha={1}, comun={2}, solo-izquierda={3}, solo-derecha={4}") -f $section.LeftCount, $section.RightCount, $section.CommonCount, $section.LeftOnly.Count, $section.RightOnly.Count)

    if ($section.LeftOnly.Count -gt 0) {
        Write-Host ""
        Write-Host ((Get-PZTText "Only in {0}:" "Solo en {0}:") -f $LeftProfile)
        $section.LeftOnly | Select-Object -First $showLimit | ForEach-Object { Write-Host ("- {0}" -f $_) }
        if ($section.LeftOnly.Count -gt $showLimit) { Write-Host ((Get-PZTText "... {0} more. Rerun with -Detailed or -MaxItems N." "... {0} mas. Ejecuta de nuevo con -Detailed o -MaxItems N.") -f ($section.LeftOnly.Count - $showLimit)) }
    }

    if ($section.RightOnly.Count -gt 0) {
        Write-Host ""
        Write-Host ((Get-PZTText "Only in {0}:" "Solo en {0}:") -f $RightProfile)
        $section.RightOnly | Select-Object -First $showLimit | ForEach-Object { Write-Host ("- {0}" -f $_) }
        if ($section.RightOnly.Count -gt $showLimit) { Write-Host ((Get-PZTText "... {0} more. Rerun with -Detailed or -MaxItems N." "... {0} mas. Ejecuta de nuevo con -Detailed o -MaxItems N.") -f ($section.RightOnly.Count - $showLimit)) }
    }

    if ($ShowCommon -and $section.Common.Count -gt 0) {
        Write-Host ""
        Write-Host (Get-PZTText "Common:" "Comun:")
        $section.Common | Select-Object -First $showLimit | ForEach-Object { Write-Host ("- {0}" -f $_) }
        if ($section.Common.Count -gt $showLimit) { Write-Host ((Get-PZTText "... {0} more. Rerun with -Detailed or -MaxItems N." "... {0} mas. Ejecuta de nuevo con -Detailed o -MaxItems N.") -f ($section.Common.Count - $showLimit)) }
    }
}

$workshopChanges = @($result.WorkshopItems.LeftOnly + $result.WorkshopItems.RightOnly)
if ($workshopChanges.Count -gt 0) {
    Write-Host ""
    if ($Detailed -or $workshopChanges.Count -le $MaxItems) {
        Write-Host (Get-PZTText "=== Workshop item details for changed IDs ===" "=== Detalles Workshop de IDs cambiados ===")
        Resolve-PZTWorkshopNames -Ids $workshopChanges | Format-Table WorkshopId, LocalNames, Url -AutoSize -Wrap
    }
    else {
        Write-Host ((Get-PZTText "Workshop details skipped by default because {0} Workshop IDs changed." "Detalles Workshop omitidos por defecto porque han cambiado {0} IDs Workshop.") -f $workshopChanges.Count)
        Write-Host (Get-PZTText "Rerun with -Detailed to resolve and print local names/URLs for all changed IDs." "Ejecuta de nuevo con -Detailed para resolver e imprimir nombres locales/URLs de todos los IDs cambiados.")
    }
}

Write-Host ""
Write-Host (Get-PZTText "Notes:" "Notas:")
Write-Host (Get-PZTText "- Mods and WorkshopItems are separate because one Workshop item can expose multiple mod IDs." "- Mods y WorkshopItems estan separados porque un item de Workshop puede exponer varios mod IDs.")
Write-Host (Get-PZTText "- Removing a mod mid-save can leave saved objects or systems behind. Back up before changing active gameplay profiles." "- Quitar un mod a mitad de save puede dejar objetos o sistemas guardados. Haz backup antes de cambiar perfiles de partida activos.")
Write-Host (Get-PZTText "- Use -Detailed for full lists, -MaxItems N for a larger compact summary, and -ShowCommon to include shared entries." "- Usa -Detailed para listas completas, -MaxItems N para un resumen compacto mas grande, y -ShowCommon para incluir entradas compartidas.")
