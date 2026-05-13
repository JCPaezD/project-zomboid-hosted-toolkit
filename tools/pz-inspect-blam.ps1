param(
    [string]$ProfileName,
    [string]$ZomboidRoot,
    [int]$RecentDays = 14,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Inspect Problem Chunks" "pz-inspect-blam"

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot
if (-not (Test-Path -LiteralPath $paths.SavesDir)) { throw ((Get-PZTText "Saves directory not found: {0}" "Directorio de saves no encontrado: {0}") -f $paths.SavesDir) }

function Get-PZTBlamEntries {
    param(
        [Parameter(Mandatory=$true)][string]$SavePath,
        [Parameter(Mandatory=$true)][string]$Profile
    )

    $blamRoot = Join-Path $SavePath "blam"
    if (-not (Test-Path -LiteralPath $blamRoot)) { return @() }

    Get-ChildItem -LiteralPath $blamRoot -Recurse -File -Filter "*_error.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            $rel = $_.FullName.Substring($blamRoot.Length).TrimStart("\")
            $parts = $rel -split "\\"
            $wx = if ($parts.Count -ge 2) { $parts[0] } else { "" }
            $wy = if ($parts.Count -ge 2) { $parts[1] -replace "_error\.txt$", "" } else { "" }
            $errorText = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
            $activeMap = Join-Path $SavePath ("map\{0}\{1}.bin" -f $wx, $wy)
            $blamChunk = Join-Path $SavePath ("blam\{0}\{1}.bin" -f $wx, $wy)
            $activeInfo = if (Test-Path -LiteralPath $activeMap) { Get-Item -LiteralPath $activeMap } else { $null }
            $blamInfo = if (Test-Path -LiteralPath $blamChunk) { Get-Item -LiteralPath $blamChunk } else { $null }

            [pscustomobject]@{
                Profile = $Profile
                SavePath = $SavePath
                Wx = $wx
                Wy = $wy
                ErrorFile = $_.FullName
                ErrorLastWriteTime = $_.LastWriteTime
                ActiveMapExists = [bool]$activeInfo
                ActiveMapLastWriteTime = if ($activeInfo) { $activeInfo.LastWriteTime } else { $null }
                ActiveMapSize = if ($activeInfo) { $activeInfo.Length } else { 0 }
                BlamChunkExists = [bool]$blamInfo
                BlamChunkSize = if ($blamInfo) { $blamInfo.Length } else { 0 }
                Summary = (($errorText -split "`r?`n" | Where-Object { $_ } | Select-Object -First 3) -join " | ")
            }
        }
}

$profiles = if ($ProfileName) {
    @($ProfileName)
}
else {
    @(Get-ChildItem -LiteralPath $paths.SavesDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*_player" } |
        ForEach-Object { $_.Name })
}

$cutoff = (Get-Date).AddDays(-1 * $RecentDays)
$entries = New-Object System.Collections.Generic.List[object]
foreach ($profile in $profiles) {
    $saveName = Get-PZTProfileSaveName -SavesDir $paths.SavesDir -ProfileName $profile
    $savePath = Join-Path $paths.SavesDir $saveName
    if (Test-Path -LiteralPath $savePath) {
        Get-PZTBlamEntries -SavePath $savePath -Profile $profile |
            Where-Object { $_.ErrorLastWriteTime -ge $cutoff } |
            ForEach-Object { $entries.Add($_) }
    }
}

if ($Json) {
    $entries | ConvertTo-Json -Depth 5
    exit 0
}

if ($entries.Count -eq 0) {
    Write-PZTStep ((Get-PZTText "No blam error files found in the selected scope from the last {0} days." "No se han encontrado archivos de error blam en el ambito seleccionado de los ultimos {0} dias.") -f $RecentDays) "pz-inspect-blam"
    exit 0
}

Write-Host ""
Write-Host (Get-PZTText "=== Problem chunks found ===" "=== Chunks problematicos encontrados ===")
$entries |
    Select-Object Profile, Wx, Wy, ErrorLastWriteTime, ActiveMapExists, ActiveMapLastWriteTime, ActiveMapSize, BlamChunkSize |
    Format-Table -AutoSize

Write-Host ""
Write-Host (Get-PZTText "=== What this usually means ===" "=== Que suele significar ===")
Write-Host (Get-PZTText "- PZ moved or copied a chunk that failed to load into the save's blam folder." "- PZ movio o copio a la carpeta blam del save un chunk que fallo al cargar.")
Write-Host (Get-PZTText "- If an active map\\wx\\wy.bin exists and is newer, the game may have recovered enough to continue." "- Si existe un map\\wx\\wy.bin activo y es mas reciente, puede que el juego se haya recuperado lo suficiente para continuar.")
Write-Host (Get-PZTText "- Do not delete or restore chunks directly on a valuable save. Back up first and test repairs in a copied profile." "- No borres ni restaures chunks directamente en un save valioso. Haz backup primero y prueba reparaciones en un perfil copiado.")

Write-Host ""
Write-Host (Get-PZTText "=== Next checks ===" "=== Siguientes comprobaciones ===")
Write-Host (Get-PZTText "- Search Logs\\*_map.txt for the same wx,wy coordinates." "- Busca las mismas coordenadas wx,wy en Logs\\*_map.txt.")
Write-Host (Get-PZTText "- Search DebugLog files around that time for InventoryItem, IsoObject.load, BufferUnderflowException, IndexOutOfBoundsException, apop, BaseAnimalBehavior, or OutOfMemoryError." "- Busca en los DebugLog de ese momento InventoryItem, IsoObject.load, BufferUnderflowException, IndexOutOfBoundsException, apop, BaseAnimalBehavior u OutOfMemoryError.")
Write-Host (Get-PZTText "- If the same coordinates repeat and the zone is unplayable, create a lab copy before attempting chunk repair." "- Si se repiten las mismas coordenadas y la zona es injugable, crea una copia de laboratorio antes de intentar reparar chunks.")
