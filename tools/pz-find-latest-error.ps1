param(
    [string]$ZomboidRoot,
    [int]$Tail = 80,
    [int]$MaxItems = 20,
    [switch]$ServerOnly,
    [switch]$IncludeMapLogs,
    [switch]$Detailed,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot
if (-not (Test-Path -LiteralPath $paths.LogsDir)) { throw "Logs directory not found: $($paths.LogsDir)" }

$filter = if ($ServerOnly) { "*DebugLog-server.txt" } else { "*DebugLog*.txt" }
$latest = Get-ChildItem -LiteralPath $paths.LogsDir -Filter $filter -Recurse -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $latest) { throw "No log found with filter $filter under $($paths.LogsDir)" }

$mapLatest = $null
if ($IncludeMapLogs) {
    $mapLatest = Get-ChildItem -LiteralPath $paths.LogsDir -Filter "*_map.txt" -Recurse -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-PZTLogCategory {
    param([Parameter(Mandatory=$true)][string]$Line)

    if ($Line -match "Installed\|NeedsUpdate|Workshop DownloadPending|GetItemState") { return "WorkshopUpdate" }
    if ($Line -match "FileSystemException|being used by another process|AccessDeniedException") { return "LockedFile" }
    if ($Line -match "UI_ServerStatus_Terminated|NormalTermination|Exiting due to errors|server terminated") { return "Termination" }
    if ($Line -match "CRC mismatch|SANITY CHECK FAIL|Error loading chunk") { return "ProblemChunk" }
    if ($Line -match "OutOfMemoryError|Java heap space|Core\.TakeScreenshot") { return "MemoryPressure" }
    if ($Line -match "BaseAnimalBehavior|\bapop\b|\\apop\\") { return "AnimalPopulation" }
    if ($Line -match "NetChecksum|absPath:null") { return "NetChecksumNullPath" }
    if ($Line -match "ReceiveModData|ReceiveModDataPacket") { return "ReceiveModData" }
    if ($Line -match "ObjectModDataPacket\.parse|movingObject.*object is null") { return "ObjectModData" }
    if ($Line -match "InventoryItem|IsoObject\.load|IsoGridSquare\.load|BufferUnderflowException|IndexOutOfBoundsException|item == null|removed=true") { return "SavedObjectLoad" }
    if ($Line -match "NullPointerException|java\.lang\.|Exception in thread|StackTrace") { return "JavaException" }
    if ($Line -match "LuaManager|Callframe|LuaEventManager|Kahlua|ExceptionLogger\.logException") { return "LuaException" }
    if ($Line -match "Fluid not found|Missing fluid") { return "MissingFluid" }
    if ($Line -match "ItemPicker.*SuburbsDistributions.*broken|SuburbsDistributions.*is broken") { return "BrokenDistribution" }
    if ($Line -match "MalformedInputException|Input length =|UTF-8|BOM") { return "EncodingLoadError" }
    if ($Line -match "ERROR|Exception|result=33") { return "GenericError" }
    return $null
}

function Get-PZTShortMessage {
    param([Parameter(Mandatory=$true)][string]$Line)
    $message = ($Line -replace "^\s*\[[^\]]+\]\s*", "").Trim()
    if ($message.Length -gt 180) { return ($message.Substring(0, 177) + "...") }
    return $message
}

function Get-PZTLogTimestamp {
    param(
        [Parameter(Mandatory=$true)][string]$Line,
        [datetime]$Fallback
    )

    if ($Line -match '^\s*\[([^\]]+)\]') { return $matches[1] }
    if ($Line -match '^\s*(LOG|WARN|ERROR)\s*:\s+[^>]*\s+f:\d+\s+st:([0-9\.]+)') { return ("st:{0}" -f $matches[2]) }
    if ($Fallback) { return $Fallback.ToString("yyyy-MM-dd HH:mm:ss") }
    return "unknown"
}

$patterns = @(
    "ERROR",
    "Exception",
    "NullPointerException",
    "OutOfMemoryError",
    "Java heap space",
    "Core\.TakeScreenshot",
    "CRC mismatch",
    "SANITY CHECK FAIL",
    "Error loading chunk",
    "InventoryItem",
    "IsoObject\.load",
    "IsoGridSquare\.load",
    "BufferUnderflowException",
    "IndexOutOfBoundsException",
    "BaseAnimalBehavior",
    "\bapop\b",
    "\\apop\\",
    "NetChecksum",
    "absPath:null",
    "ReceiveModData",
    "ReceiveModDataPacket",
    "ObjectModDataPacket\.parse",
    "Installed\|NeedsUpdate",
    "result=33",
    "FileSystemException",
    "Fluid not found",
    "Exiting due to errors",
    "UI_ServerStatus_Terminated",
    "Workshop DownloadPending",
    "NormalTermination",
    "SuburbsDistributions.*broken",
    "MalformedInputException"
)

function Get-PZTLogItems {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Kind
    )

    @(Select-String -LiteralPath $Path -Pattern $patterns | ForEach-Object {
        $category = Get-PZTLogCategory -Line $_.Line
        if ($category) {
            [pscustomobject]@{
                LogKind = $Kind
                LogPath = $Path
                LineNumber = $_.LineNumber
                Time = Get-PZTLogTimestamp -Line $_.Line -Fallback (Get-Item -LiteralPath $Path).LastWriteTime
                Category = $category
                Message = Get-PZTShortMessage -Line $_.Line
            }
        }
    })
}

$matches = @(Get-PZTLogItems -Path $latest.FullName -Kind "Debug")
if ($mapLatest) { $matches += @(Get-PZTLogItems -Path $mapLatest.FullName -Kind "Map") }
$items = foreach ($match in $matches) {
    $match
}

$summary = [pscustomobject]@{
    LogPath = $latest.FullName
    MapLogPath = if ($mapLatest) { $mapLatest.FullName } else { $null }
    LastWriteTime = $latest.LastWriteTime
    MatchCount = @($items).Count
    Categories = @($items | Group-Object Category | Sort-Object Count -Descending | ForEach-Object {
        [pscustomobject]@{ Category = $_.Name; Count = $_.Count }
    })
    LatestItems = @($items | Select-Object -Last $MaxItems)
}

function Get-PZTRecommendations {
    param(
        [Parameter(Mandatory=$true)]$Categories,
        [string]$Language = "en"
    )

    $names = @($Categories | ForEach-Object { $_.Category })
    $recommendations = New-Object System.Collections.Generic.List[string]
    $es = ($Language -eq "es")

    if ($names -contains "WorkshopUpdate") {
        if ($es) { $recommendations.Add("Se han encontrado senales de actualizacion/cache de Workshop. Revisa primero los mods globales del cliente; usa repair-workshop solo si el log contiene Installed|NeedsUpdate y Steam preparo carpeta downloads.") }
        else { $recommendations.Add("Workshop update/cache signals were found. Check client global mods first, then use repair-workshop only if the log contains Installed|NeedsUpdate and Steam prepared a downloads folder.") }
    }
    if ($names -contains "LockedFile") {
        if ($es) { $recommendations.Add("Se han encontrado archivos bloqueados. Cierra PZ, ZombieBuddy y procesos Java antes de reintentar o reparar archivos Workshop.") }
        else { $recommendations.Add("Locked file signals were found. Close PZ, ZombieBuddy, and Java-related processes before retrying or repairing Workshop files.") }
    }
    if ($names -contains "EncodingLoadError") {
        if ($es) { $recommendations.Add("Se han encontrado senales de codificacion/carga. Revisa BOM UTF-8 o reescrituras accidentales antes de editar mas.") }
        else { $recommendations.Add("Encoding/load signals were found. Audit profile files for UTF-8 BOM or accidental rewrites before editing further.") }
    }
    if ($names -contains "MissingFluid") {
        if ($es) { $recommendations.Add("Faltan definiciones de fluid/item. Suele apuntar a orden de mods, dependencias ausentes o version incompatible de algun mod.") }
        else { $recommendations.Add("Missing fluid/item definition signals were found. This usually points to mod load order, missing dependencies, or an incompatible mod version.") }
    }
    if ($names -contains "BrokenDistribution") {
        if ($es) { $recommendations.Add("Hay warnings de distribuciones/loot tables. A menudo son ruido de mods salvo que vayan seguidos de termination o exceptions.") }
        else { $recommendations.Add("Broken distribution warnings were found. These are often mod loot-table issues; they may be noisy warnings unless followed by termination or exceptions.") }
    }
    if ($names -contains "ProblemChunk") {
        if ($es) { $recommendations.Add("Hay senales de problem chunk / CRC. Inspecciona blam y coordenadas del map log. No borres chunks en un save valioso; haz backup y prueba en una copia.") }
        else { $recommendations.Add("Problem chunk / CRC signals were found. Inspect the save's blam folder and map log coordinates. Do not delete chunks on a valuable save; back up and use a copied profile for repair tests.") }
    }
    if ($names -contains "SavedObjectLoad") {
        if ($es) { $recommendations.Add("Hay senales de carga de objetos guardados. Puede ocurrir si un item/objeto guardado ya no encaja con scripts o mods actuales. Compara cambios recientes de mods y ProblemChunk cercanos.") }
        else { $recommendations.Add("Saved object load signals were found. This can happen when a saved item/object no longer matches current scripts or mods. Compare recent mod changes and inspect nearby ProblemChunk entries.") }
    }
    if ($names -contains "MemoryPressure") {
        if ($es) { $recommendations.Add("Hay senales de presion de memoria. Trata la RAM como sintoma hasta descartar chunks/objetos guardados; zonas densas, screenshots/thumbnails, cadaveres y packs grandes lo amplifican.") }
        else { $recommendations.Add("Memory pressure signals were found. Treat RAM as a symptom until logs rule out bad chunks or saved objects; very dense areas, screenshots/thumbnails, corpses, and large mod packs can amplify it.") }
    }
    if ($names -contains "AnimalPopulation") {
        if ($es) { $recommendations.Add("Hay senales de animal population/apop. Investiga apop solo tras backup; resetearlo puede eliminar estado de poblacion animal en una zona.") }
        else { $recommendations.Add("Animal population/apop signals were found. Investigate the save's apop files only after backup; resetting apop can remove animal population state in an area.") }
    }
    if ($names -contains "ObjectModData") {
        if ($es) { $recommendations.Add("Hay warnings de object mod-data. Pueden aparecer si server/cliente referencia objetos del mundo ausentes o no cargados; revisa si se agrupan en una coordenada o tras quitar mods.") }
        else { $recommendations.Add("Object mod-data warnings were found. These can appear when the server/client references world objects that are missing or no longer loaded; check whether they cluster around one coordinate or recent mod removals.") }
    }
    if ($names -contains "ReceiveModData") {
        if ($es) { $recommendations.Add("Hay errores ReceiveModData. Apuntan a sincronizacion server/cliente de objetos del mundo, a menudo cerca de una zona cargada. Si se repiten, compara con ObjectModData y cambios recientes de mods.") }
        else { $recommendations.Add("ReceiveModData errors were found. These point at server/client world-object synchronization, often near a loaded area. If they repeat, compare with nearby ObjectModData coordinates and recent mod removals.") }
    }
    if ($names -contains "NetChecksumNullPath") {
        if ($es) { $recommendations.Add("Hay errores NetChecksum null-path. En packs grandes puede ser ruido de carga de scripts; prioridad baja salvo que haya termination o errores de archivo/mod ausente.") }
        else { $recommendations.Add("NetChecksum null-path errors were found. In large mod packs this can be noisy during script loading; treat it as lower priority unless followed by termination or missing-file/mod errors.") }
    }
    if ($names -contains "JavaException" -or $names -contains "LuaException") {
        if ($es) { $recommendations.Add("Hay exceptions. Revisa primero las lineas relevantes recientes; relanza con -Detailed si el resumen compacto no muestra mod/funcion origen.") }
        else { $recommendations.Add("Exceptions were found. Inspect the latest relevant lines first, then rerun with -Detailed if the compact summary does not show the source mod/function.") }
    }
    if ($names -contains "Termination") {
        if ($es) { $recommendations.Add("Hay senales de termination. Usa las categorias anteriores para buscar la causa; termination suele ser consecuencia, no causa raiz.") }
        else { $recommendations.Add("Termination signals were found. Use the categories above to find the cause; termination itself is usually the result, not the root cause.") }
    }

    return @($recommendations)
}

$lang = Get-PZTLanguage
$recommendations = Get-PZTRecommendations -Categories $summary.Categories -Language $lang

if ($Json) {
    $summary | ConvertTo-Json -Depth 5
    exit 0
}

Write-PZTTitle "PZ Hosted Toolkit - Find Latest Errors" "pz-find-latest-error"
Write-PZTStep "Latest log: $($latest.FullName)" "pz-find-latest-error"
if ($mapLatest) { Write-PZTStep "Latest map log: $($mapLatest.FullName)" "pz-find-latest-error" }

if ($Detailed) {
    $detailPaths = @($latest.FullName)
    if ($mapLatest) { $detailPaths += $mapLatest.FullName }
    $detailedMatches = Select-String -LiteralPath $detailPaths -Pattern $patterns -Context 2,4
    if ($detailedMatches) {
        $detailedMatches | Select-Object -Last $Tail
    }
    else {
        Write-PZTStep "No known error patterns found. Showing tail." "pz-find-latest-error"
        Get-Content -LiteralPath $latest.FullName -Tail $Tail
    }
    exit 0
}

if ($summary.MatchCount -eq 0) {
    Write-PZTStep "No known error patterns found. Showing last $Tail lines." "pz-find-latest-error"
    Get-Content -LiteralPath $latest.FullName -Tail $Tail
    exit 0
}

Write-Host ""
if ($lang -eq "es") { Write-Host "=== Hallazgos clave ===" } else { Write-Host "=== Key findings ===" }
$priority = @("Termination","WorkshopUpdate","LockedFile","ProblemChunk","SavedObjectLoad","MemoryPressure","AnimalPopulation","ReceiveModData","ObjectModData","EncodingLoadError","MissingFluid","LuaException","JavaException","BrokenDistribution","NetChecksumNullPath","GenericError")
foreach ($name in $priority) {
    $cat = $summary.Categories | Where-Object { $_.Category -eq $name } | Select-Object -First 1
    if ($cat) {
        switch ($name) {
            "ProblemChunk" { Write-Host ("- ProblemChunk ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "problema de carga/CRC de chunk; inspecciona blam y map logs primero." } else { "chunk load/CRC issue; inspect blam and map logs first." })) }
            "MemoryPressure" { Write-Host ("- MemoryPressure ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "senal RAM/OOM; revisa si lo disparan chunks malos o zonas densas." } else { "RAM/OOM signal; check whether bad chunks or dense areas triggered it." })) }
            "ReceiveModData" { Write-Host ("- ReceiveModData ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "errores de sincronizacion de objetos; puede haber coordenadas cerca en el log." } else { "world-object sync errors; useful coordinates may be nearby in the log." })) }
            "ObjectModData" { Write-Host ("- ObjectModData ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "referencias a objetos ausentes/null; puede agruparse alrededor de una zona." } else { "object references missing/null; may cluster around one area." })) }
            "NetChecksumNullPath" { Write-Host ("- NetChecksumNullPath ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "ruido frecuente en packs grandes; baja prioridad salvo fallo de arranque." } else { "noisy mod-pack script checksum issue; lower priority unless launch fails." })) }
            "BrokenDistribution" { Write-Host ("- BrokenDistribution ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "warnings de loot table; a menudo ruido salvo que vayan con fallo." } else { "loot table warnings; often noisy unless paired with failure." })) }
            "GenericError" { Write-Host ("- GenericError ({0}): {1}" -f $cat.Count, $(if ($lang -eq "es") { "lineas sin clasificar; usa -Detailed si los hallazgos no explican el fallo." } else { "uncategorized lines; rerun with -Detailed if key findings do not explain the failure." })) }
            default { Write-Host ("- {0} ({1})" -f $name, $cat.Count) }
        }
    }
}

Write-Host ""
if ($lang -eq "es") { Write-Host "=== Resumen ===" } else { Write-Host "=== Summary ===" }
$summary.Categories | Format-Table Category, Count -AutoSize

Write-Host ""
if ($lang -eq "es") { Write-Host "=== Ultimas lineas relevantes ===" } else { Write-Host "=== Latest relevant lines ===" }
$summary.LatestItems | Format-Table LogKind, LineNumber, Time, Category, Message -AutoSize -Wrap

if ($recommendations.Count -gt 0) {
    Write-Host ""
    if ($lang -eq "es") { Write-Host "=== Siguientes comprobaciones sugeridas ===" } else { Write-Host "=== Suggested next checks ===" }
    foreach ($rec in $recommendations) {
        Write-Host ("- {0}" -f $rec)
    }
}

Write-Host ""
if ($lang -eq "es") {
    Write-PZTStep "Tip: anade -IncludeMapLogs para logs de chunks/CRC, -Detailed para contexto crudo, -Json para salida procesable, o -MaxItems N para ver mas lineas." "pz-find-latest-error"
}
else {
    Write-PZTStep "Tip: add -IncludeMapLogs for chunk/CRC logs, -Detailed for raw context, -Json for machine-readable output, or -MaxItems N to show more lines." "pz-find-latest-error"
}
