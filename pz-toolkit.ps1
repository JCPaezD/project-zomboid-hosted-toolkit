param(
    [Parameter(Position=0)]
    [string]$Command = "menu",

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $PSScriptRoot
$toolRoot = Join-Path $PSScriptRoot "tools"
. "$toolRoot\lib\PZToolkit.Common.ps1"

$commands = @{
    "audit" = "pz-audit.ps1"
    "backup-profile" = "pz-backup-profile.ps1"
    "clear-client-mods" = "pz-clear-client-mods.ps1"
    "compare-mods" = "pz-compare-mods.ps1"
    "compare-sandbox" = "pz-compare-sandbox.ps1"
    "copy-players" = "pz-copy-players.ps1"
    "copy-world" = "pz-copy-world.ps1"
    "errors" = "pz-find-latest-error.ps1"
    "export-profile" = "pz-export-profile.ps1"
    "health-check" = "pz-health-check.ps1"
    "inspect-profile" = "pz-inspect-profile.ps1"
    "inspect-blam" = "pz-inspect-blam.ps1"
    "quick-diagnosis" = "pz-quick-diagnosis.ps1"
    "repair-workshop" = "pz-repair-workshop-redownload.ps1"
    "restore-profile" = "pz-restore-profile.ps1"
    "reset-player" = "pz-reset-hosted-player.ps1"
    "reset-world" = "pz-reset-hosted-world.ps1"
    "verify-backup" = "pz-verify-backup.ps1"
}

function Show-Help {
    Write-Host "PZ Hosted Toolkit"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\pz-toolkit.ps1 <command> [script arguments]"
    Write-Host ""
    Write-Host "Commands:"
    $commands.GetEnumerator() |
        Sort-Object Name |
        ForEach-Object { Write-Host ("  {0,-18} -> tools\{1}" -f $_.Name, $_.Value) }
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\pz-toolkit.ps1 audit"
    Write-Host "  .\pz-toolkit.ps1 quick-diagnosis"
    Write-Host "  .\pz-toolkit.ps1 health-check -ProfileName `"MyHostedServer`""
    Write-Host "  .\pz-toolkit.ps1 errors -ServerOnly"
    Write-Host "  .\pz-toolkit.ps1 clear-client-mods -WhatIf"
    Write-Host "  .\pz-toolkit.ps1 backup-profile -ProfileName `"MyHostedServer`""
    Write-Host "  .\pz-toolkit.ps1 inspect-profile -ProfileName `"MyHostedServer`""
    Write-Host "  .\pz-toolkit.ps1 menu"
}

function Invoke-ToolkitCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string[]]$Args = @()
    )

    $script = Join-Path $toolRoot $commands[$Name]
    $powershell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $powershell) { $powershell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $powershell) { throw "Could not find powershell.exe or pwsh to dispatch command arguments safely." }

    & $powershell -NoProfile -ExecutionPolicy Bypass -File $script @Args
    $script:ToolkitLastExitCode = $LASTEXITCODE
}

function Read-ToolkitProfile {
    param([string]$Prompt)
    if (-not $Prompt) {
        $Prompt = if ((Get-PZTLanguage) -eq "es") { "Elige perfil alojado" } else { "Choose hosted profile" }
    }
    $paths = Get-PZTPaths
    $profiles = Get-PZTHostedProfileNames -ServerDir $paths.ServerDir
    return Read-PZTMenuChoice -Prompt $Prompt -Items $profiles -AllowCancel
}

function Read-ToolkitRequiredProfile {
    param([string]$Prompt)
    if (-not $Prompt) {
        $Prompt = if ((Get-PZTLanguage) -eq "es") { "Elige perfil alojado" } else { "Choose hosted profile" }
    }
    $profile = Read-ToolkitProfile -Prompt $Prompt
    if (-not $profile) { return $null }
    return $profile
}

function Read-ToolkitOutputDir {
    param([string]$DefaultName)
    $lang = Get-PZTLanguage
    $prompt = if ($lang -eq "es") {
        "Nombre de export bajo .\exports [$DefaultName]"
    }
    else {
        "Export name under .\exports [$DefaultName]"
    }
    $raw = Read-Host $prompt
    if ($raw) { return $raw }
    return $DefaultName
}

function Read-ToolkitBackupPath {
    $paths = Get-PZTPaths
    $dirs = Get-PZTBackupDirectories -BackupRoot $paths.BackupRoot -Limit 20
    if ($dirs.Count -eq 0) {
        return (Read-Host "Backup folder path")
    }

    $labels = @($dirs | ForEach-Object {
        "{0}  ({1}, {2:N2} MB)" -f $_.Name, $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), ((Get-PZTTreeSummary -Path $_.FullName).SizeMB)
    })
    $labels += "Type a backup path manually"
    if ((Get-PZTLanguage) -eq "es") {
        $labels[$labels.Count - 1] = "Escribir ruta de backup manualmente"
    }

    $choice = Read-PZTMenuChoice -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige carpeta de backup" } else { "Choose backup folder" }) -Items $labels -AllowCancel
    if (-not $choice) { return $null }
    if ($choice -eq "Type a backup path manually" -or $choice -eq "Escribir ruta de backup manualmente") {
        return (Read-Host $(if ((Get-PZTLanguage) -eq "es") { "Ruta de carpeta de backup" } else { "Backup folder path" }))
    }

    $index = [array]::IndexOf($labels, $choice)
    return $dirs[$index].FullName
}

function Get-ToolkitBackupSourceProfileName {
    param([Parameter(Mandatory=$true)][string]$BackupPath)

    $manifest = Join-Path $BackupPath "MANIFEST.txt"
    if (Test-Path -LiteralPath $manifest) {
        $line = Get-Content -LiteralPath $manifest | Where-Object { $_ -like "ProfileName:*" } | Select-Object -First 1
        if ($line) { return ($line -replace "^ProfileName:\s*", "").Trim() }
    }

    $serverDir = Join-Path $BackupPath "Server"
    $ini = Get-ChildItem -LiteralPath $serverDir -File -Filter *.ini -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ini) { return [System.IO.Path]::GetFileNameWithoutExtension($ini.Name) }
    return $null
}

function Test-ToolkitProfileTargetExists {
    param([Parameter(Mandatory=$true)][string]$ProfileName)

    $paths = Get-PZTPaths
    $targetFiles = Get-PZTProfileFilePaths -ServerDir $paths.ServerDir -ProfileName $ProfileName
    foreach ($file in $targetFiles) {
        if (Test-Path -LiteralPath $file) { return $true }
    }
    $saveName = Convert-PZTProfileNameToSaveName -ProfileName $ProfileName
    if (Test-Path -LiteralPath (Join-Path $paths.SavesDir $ProfileName)) { return $true }
    if (Test-Path -LiteralPath (Join-Path $paths.SavesDir $saveName)) { return $true }
    if (Test-Path -LiteralPath (Join-Path $paths.SavesDir "${ProfileName}_player")) { return $true }
    if (Test-Path -LiteralPath (Join-Path $paths.SavesDir "${saveName}_player")) { return $true }
    if (Test-Path -LiteralPath (Join-Path $paths.DbDir "$ProfileName.db")) { return $true }
    return $false
}

function Read-ToolkitActionChoice {
    param([switch]$Fresh)

    $lang = Get-PZTLanguage

    $actions = @(
        [pscustomobject]@{ Key = "1"; Group = "Inspect"; GroupEs = "Inspeccion"; Label = "Audit local PZ state"; LabelEs = "Auditar estado local de PZ"; Description = "Read-only overview of folders, profiles, mods, logs, and paths."; DescriptionEs = "Vista general solo lectura de carpetas, perfiles, mods, logs y rutas." },
        [pscustomobject]@{ Key = "2"; Group = "Inspect"; GroupEs = "Inspeccion"; Label = "Inspect a hosted profile"; LabelEs = "Inspeccionar perfil hosted"; Description = "Summarizes one hosted profile: files, save, counts, maps, and players."; DescriptionEs = "Resume un perfil hosted: archivos, save, conteos, mapas y jugadores." },
        [pscustomobject]@{ Key = "3"; Group = "Inspect"; GroupEs = "Inspeccion"; Label = "Health-check a hosted profile"; LabelEs = "Comprobar salud de perfil"; Description = "Checks one profile for missing files, BOM, save/db state, and obvious list issues."; DescriptionEs = "Revisa archivos ausentes, BOM, save/db y problemas evidentes en listas." },
        [pscustomobject]@{ Key = "4"; Group = "Inspect"; GroupEs = "Inspeccion"; Label = "Inspect blam / problem chunks"; LabelEs = "Inspeccionar blam/chunks"; Description = "Shows B42 blam/problem chunks without modifying the save."; DescriptionEs = "Muestra chunks problematicos/blam de B42 sin modificar el save." },
        [pscustomobject]@{ Key = "5"; Group = "Diagnose"; GroupEs = "Diagnostico"; Label = "Quick diagnosis"; LabelEs = "Diagnostico rapido"; Description = "Compact triage for common hosted-server problems and next checks."; DescriptionEs = "Triage compacto de problemas comunes y siguientes comprobaciones." },
        [pscustomobject]@{ Key = "6"; Group = "Diagnose"; GroupEs = "Diagnostico"; Label = "Find latest known errors"; LabelEs = "Ver ultimos errores"; Description = "Classifies recent logs into known categories with suggested next steps."; DescriptionEs = "Clasifica logs recientes y propone siguientes pasos." },
        [pscustomobject]@{ Key = "7"; Group = "Diagnose"; GroupEs = "Diagnostico"; Label = "Clear client global mods (WhatIf first)"; LabelEs = "Limpiar mods globales cliente"; Description = "Checks and optionally clears the single-player global mod preload list."; DescriptionEs = "Comprueba y puede limpiar la lista global de mods del cliente." },
        [pscustomobject]@{ Key = "8"; Group = "Diagnose"; GroupEs = "Diagnostico"; Label = "Repair Workshop redownload issue (WhatIf)"; LabelEs = "Reparar redownload Workshop"; Description = "Targets the narrow Workshop staged-download/locked-file repair case."; DescriptionEs = "Caso concreto de reparacion de Workshop staged-download/archivo bloqueado." },
        [pscustomobject]@{ Key = "9"; Group = "Compare"; GroupEs = "Comparar"; Label = "Compare sandbox profiles"; LabelEs = "Comparar sandbox"; Description = "Compares SandboxVars between two hosted profiles."; DescriptionEs = "Compara SandboxVars entre dos perfiles hosted." },
        [pscustomobject]@{ Key = "10"; Group = "Compare"; GroupEs = "Comparar"; Label = "Compare mods / workshop / maps"; LabelEs = "Comparar mods/workshop/mapas"; Description = "Compares Mods, WorkshopItems, and Map lists between profiles."; DescriptionEs = "Compara Mods, WorkshopItems y Map entre perfiles." },
        [pscustomobject]@{ Key = "11"; Group = "Backup / Restore"; GroupEs = "Backups"; Label = "Back up a hosted profile"; LabelEs = "Crear backup de perfil"; Description = "Copies profile files, save, player folder, and DB into a COMPLETE-marked backup."; DescriptionEs = "Copia perfil, save, carpeta player y DB a un backup marcado COMPLETE." },
        [pscustomobject]@{ Key = "12"; Group = "Backup / Restore"; GroupEs = "Backups"; Label = "Verify a backup folder"; LabelEs = "Verificar backup"; Description = "Checks backup status and expected files before relying on it."; DescriptionEs = "Comprueba estado y archivos esperados antes de confiar en un backup." },
        [pscustomobject]@{ Key = "13"; Group = "Backup / Restore"; GroupEs = "Backups"; Label = "Restore or copy a profile from backup"; LabelEs = "Restaurar/copiar backup"; Description = "Restores a backup or copies it into a new profile name."; DescriptionEs = "Restaura un backup o lo copia con un nombre de perfil nuevo." },
        [pscustomobject]@{ Key = "14"; Group = "Transfer"; GroupEs = "Transferir"; Label = "Copy world/save to another profile (WhatIf first)"; LabelEs = "Copiar mundo a otro perfil"; Description = "Transfers world/save data between existing profiles after showing impact."; DescriptionEs = "Transfiere mundo/save entre perfiles existentes mostrando impacto antes." },
        [pscustomobject]@{ Key = "15"; Group = "Transfer"; GroupEs = "Transferir"; Label = "Copy players to another profile (WhatIf first)"; LabelEs = "Copiar jugadores"; Description = "Transfers players.db and optional _player folder after showing player impact."; DescriptionEs = "Transfiere players.db y _player mostrando impacto de jugadores antes." },
        [pscustomobject]@{ Key = "16"; Group = "Export"; GroupEs = "Exportar"; Label = "Export profile mod/map lists"; LabelEs = "Exportar perfil"; Description = "Writes profile lists and summaries under exports for sharing or review."; DescriptionEs = "Genera listas y resumenes bajo exports para compartir o revisar." },
        [pscustomobject]@{ Key = "17"; Group = "Danger Zone"; GroupEs = "Zona peligrosa"; Label = "Reset selected profile world/map (WhatIf first)"; LabelEs = "Resetear mundo/mapa"; Description = "Moves world/save data aside so PZ creates a fresh world on next launch."; DescriptionEs = "Mueve el mundo/save para que PZ cree un mundo nuevo al lanzar." },
        [pscustomobject]@{ Key = "18"; Group = "Danger Zone"; GroupEs = "Zona peligrosa"; Label = "Reset one hosted player (WhatIf first)"; LabelEs = "Resetear jugador"; Description = "Deletes one hosted player row after backup and confirmation."; DescriptionEs = "Elimina una fila de jugador tras backup y confirmacion." },
        [pscustomobject]@{ Key = "H"; Group = "Help"; GroupEs = "Ayuda"; Label = "Show command help"; LabelEs = "Mostrar ayuda"; Description = "Shows command-mode usage and examples."; DescriptionEs = "Muestra uso por comandos y ejemplos." },
        [pscustomobject]@{ Key = "Q"; Group = "Help"; GroupEs = "Ayuda"; Label = "Quit"; LabelEs = "Salir"; Description = "Exit the toolkit."; DescriptionEs = "Salir del toolkit." }
    )

    $selected = 0
    $renderedLines = 0
    if ($Fresh) { Clear-Host }
    while ($true) {
        if ($renderedLines -gt 0 -and [Console]::CursorTop -ge $renderedLines) {
            [Console]::SetCursorPosition(0, [Console]::CursorTop - $renderedLines)
        }

        $startTop = [Console]::CursorTop
        $width = [Math]::Max(80, [Console]::WindowWidth - 1)
        function Write-ToolkitMenuLine {
            param(
                [string]$Text = "",
                [ConsoleColor]$Foreground = [ConsoleColor]::Gray,
                $Background = $null
            )
            $line = if ($Text.Length -gt ($width - 1)) { $Text.Substring(0, $width - 1) } else { $Text }
            $line = $line.PadRight($width)
            if ($null -ne $Background) {
                Write-Host $line -ForegroundColor $Foreground -BackgroundColor ([ConsoleColor]$Background)
            }
            else {
                Write-Host $line -ForegroundColor $Foreground
            }
        }

        Write-ToolkitMenuLine "========================================" ([ConsoleColor]::DarkCyan)
        Write-ToolkitMenuLine "PZ Hosted Toolkit" ([ConsoleColor]::Cyan)
        Write-ToolkitMenuLine "========================================" ([ConsoleColor]::DarkCyan)
        if ($lang -eq "es") {
            Write-ToolkitMenuLine "Herramientas seguras para diagnosticar y mantener servidores hosted de Project Zomboid." ([ConsoleColor]::DarkGray)
            Write-ToolkitMenuLine "Las acciones de escritura usan WhatIf o confirmacion antes de tocar archivos." ([ConsoleColor]::DarkGray)
        }
        else {
            Write-ToolkitMenuLine "Conservative tools for diagnosing and maintaining Project Zomboid hosted servers." ([ConsoleColor]::DarkGray)
            Write-ToolkitMenuLine "Write-capable actions use WhatIf or confirmation before touching files." ([ConsoleColor]::DarkGray)
        }

        Write-ToolkitMenuLine ""
        $leftActions = @($actions | Select-Object -First 10)
        $rightActions = @($actions | Select-Object -Skip 10)
        function New-ToolkitMenuRows {
            param($Items)
            $rows = New-Object System.Collections.Generic.List[object]
            $lastGroup = $null
            foreach ($item in $Items) {
                $group = if ($lang -eq "es") { $item.GroupEs } else { $item.Group }
                if ($group -ne $lastGroup) {
                    if ($rows.Count -gt 0) { $rows.Add([pscustomobject]@{ Kind = "Spacer"; Action = $null; Text = "" }) | Out-Null }
                    $rows.Add([pscustomobject]@{ Kind = "Header"; Action = $null; Text = ("[{0}]" -f $group) }) | Out-Null
                    $lastGroup = $group
                }
                $display = if ($lang -eq "es") { $item.LabelEs } else { $item.Label }
                $rows.Add([pscustomobject]@{ Kind = "Action"; Action = $item; Text = ("{0,2}. {1}" -f $item.Key, $display) }) | Out-Null
            }
            return @($rows.ToArray())
        }

        $left = @(New-ToolkitMenuRows -Items $leftActions)
        $right = @(New-ToolkitMenuRows -Items $rightActions)
        $rows = [Math]::Max($left.Count, $right.Count)
        $colWidth = [Math]::Max(38, [Math]::Floor(($width - 4) / 2))
        function Get-ToolkitActionIndex {
            param($Action)
            if (-not $Action) { return -1 }
            for ($n = 0; $n -lt $actions.Count; $n++) {
                if ($actions[$n].Key -eq $Action.Key) { return $n }
            }
            return -1
        }
        for ($i = 0; $i -lt $rows; $i++) {
            $parts = @()
            $indices = @()
            $kinds = @()
            $columns = New-Object System.Collections.Generic.List[object]
            $columns.Add($left) | Out-Null
            $columns.Add($right) | Out-Null
            foreach ($col in $columns) {
                if ($i -lt $col.Count) {
                    $row = $col[$i]
                    $text = $row.Text
                    if ($text.Length -gt ($colWidth - 2)) { $text = $text.Substring(0, $colWidth - 5) + "..." }
                    $parts += $text.PadRight($colWidth)
                    $kinds += $row.Kind
                    if ($row.Kind -eq "Action") {
                        $indices += (Get-ToolkitActionIndex -Action $row.Action)
                    }
                    else {
                        $indices += -1
                    }
                }
                else {
                    $parts += "".PadRight($colWidth)
                    $indices += -1
                    $kinds += "Empty"
                }
            }
            $leftIndex = $indices[0]
            $rightIndex = $indices[1]
            function Write-ToolkitMenuCell {
                param(
                    [string]$Text,
                    [string]$Kind,
                    [bool]$Selected,
                    [switch]$NoNewline
                )
                $fg = [ConsoleColor]::Gray
                $bg = $null
                if ($Kind -eq "Header") { $fg = [ConsoleColor]::Cyan }
                elseif ($Kind -eq "Spacer" -or $Kind -eq "Empty") { $fg = [ConsoleColor]::DarkGray }
                if ($Selected) {
                    $fg = [ConsoleColor]::Black
                    $bg = [ConsoleColor]::Gray
                }
                $prefix = if ($Selected) { "> " } else { "  " }
                $line = ($prefix + $Text)
                if ($null -ne $bg) {
                    Write-Host $line -ForegroundColor $fg -BackgroundColor $bg -NoNewline:$NoNewline
                }
                else {
                    Write-Host $line -ForegroundColor $fg -NoNewline:$NoNewline
                }
            }
            if ($selected -eq $leftIndex) {
                Write-ToolkitMenuCell -Text $parts[0] -Kind $kinds[0] -Selected $true -NoNewline
                Write-ToolkitMenuCell -Text $parts[1] -Kind $kinds[1] -Selected $false
            }
            elseif ($selected -eq $rightIndex -and $rightIndex -ge 0) {
                Write-ToolkitMenuCell -Text $parts[0] -Kind $kinds[0] -Selected $false -NoNewline
                Write-ToolkitMenuCell -Text $parts[1] -Kind $kinds[1] -Selected $true
            }
            else {
                Write-ToolkitMenuCell -Text $parts[0] -Kind $kinds[0] -Selected $false -NoNewline
                Write-ToolkitMenuCell -Text $parts[1] -Kind $kinds[1] -Selected $false
            }
        }

        Write-ToolkitMenuLine ""
        $selectedAction = $actions[$selected]
        $selectedDesc = if ($lang -eq "es") { $selectedAction.DescriptionEs } else { $selectedAction.Description }
        Write-ToolkitMenuLine ("[{0}] {1}" -f $selectedAction.Key, $selectedDesc) ([ConsoleColor]::DarkYellow)
        $arrows = "$([char]0x2191)/$([char]0x2193)"
        if ($lang -eq "es") {
            Write-ToolkitMenuLine "$arrows`: mover    ENTER: ejecutar    H: ayuda    Q: salir" ([ConsoleColor]::DarkGray)
        }
        else {
            Write-ToolkitMenuLine "$arrows`: move    ENTER: run selected    H: help    Q: quit" ([ConsoleColor]::DarkGray)
        }
        $renderedLines = [Console]::CursorTop - $startTop
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { if ($selected -gt 0) { $selected-- } else { $selected = $actions.Count - 1 } }
            "DownArrow" { if ($selected -lt ($actions.Count - 1)) { $selected++ } else { $selected = 0 } }
            "Home" { $selected = 0 }
            "End" { $selected = $actions.Count - 1 }
            "Enter" { return $actions[$selected].Label }
            default {
                if ($key.KeyChar -match '^[qQ]$') { return "Quit" }
                if ($key.KeyChar -match '^[hH]$') { return "Show command help" }
            }
        }
    }
}

function Show-Menu {
    function Get-ToolkitActionDisplay {
        param([string]$Choice)
        if ((Get-PZTLanguage) -ne "es") { return $Choice }
        $map = @{
            "Audit local PZ state" = "Auditar estado local de PZ"
            "Inspect a hosted profile" = "Inspeccionar perfil alojado"
            "Health-check a hosted profile" = "Comprobar salud de perfil"
            "Inspect blam / problem chunks" = "Inspeccionar blam/chunks"
            "Quick diagnosis" = "Diagnostico rapido"
            "Find latest known errors" = "Ver ultimos errores"
            "Clear client global mods (WhatIf first)" = "Limpiar mods globales cliente"
            "Repair Workshop redownload issue (WhatIf)" = "Reparar redownload Workshop"
            "Compare sandbox profiles" = "Comparar sandbox"
            "Compare mods / workshop / maps" = "Comparar mods/workshop/mapas"
            "Back up a hosted profile" = "Crear backup de perfil"
            "Verify a backup folder" = "Verificar backup"
            "Restore or copy a profile from backup" = "Restaurar/copiar backup"
            "Copy world/save to another profile (WhatIf first)" = "Copiar mundo a otro perfil"
            "Copy players to another profile (WhatIf first)" = "Copiar jugadores"
            "Export profile mod/map lists" = "Exportar perfil"
            "Reset selected profile world/map (WhatIf first)" = "Resetear mundo/mapa"
            "Reset one hosted player (WhatIf first)" = "Resetear jugador"
            "Show command help" = "Mostrar ayuda"
            "Quit" = "Salir"
        }
        if ($map.ContainsKey($Choice)) { return $map[$Choice] }
        return $Choice
    }

    $freshMenu = $true
    while ($true) {
        $choice = Read-ToolkitActionChoice -Fresh:$freshMenu
        $freshMenu = $true
        Clear-Host
        Write-Host "========================================" -ForegroundColor DarkCyan
        Write-Host "PZ Hosted Toolkit" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor DarkCyan
        if ((Get-PZTLanguage) -eq "es") {
            Write-Host ("Accion: {0}" -f (Get-ToolkitActionDisplay -Choice $choice)) -ForegroundColor DarkGray
        }
        else {
            Write-Host ("Action: {0}" -f $choice) -ForegroundColor DarkGray
        }
        Write-Host ""
        function Write-ToolkitPrepTitle {
            param([string]$English, [string]$Spanish)
            if ((Get-PZTLanguage) -eq "es") { Write-PZTTitle $Spanish "pz-toolkit" } else { Write-PZTTitle $English "pz-toolkit" }
        }
        switch ($choice) {
            "Audit local PZ state" {
                Write-ToolkitPrepTitle "Preparing - Audit local PZ state" "Preparando - Auditar estado local de PZ"
                Invoke-ToolkitCommand -Name "audit"
            }
            "Inspect a hosted profile" {
                Write-ToolkitPrepTitle "Preparing - Inspect hosted profile" "Preparando - Inspeccionar perfil hosted"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) { Invoke-ToolkitCommand -Name "inspect-profile" -Args @("-ProfileName", $profile) }
            }
            "Health-check a hosted profile" {
                Write-ToolkitPrepTitle "Preparing - Health-check hosted profile" "Preparando - Comprobar salud del perfil"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) { Invoke-ToolkitCommand -Name "health-check" -Args @("-ProfileName", $profile) }
            }
            "Inspect blam / problem chunks" {
                Write-ToolkitPrepTitle "Preparing - Inspect blam / problem chunks" "Preparando - Inspeccionar blam/chunks"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil, o cancela para escanear todos los saves" } else { "Choose profile, or cancel to scan all saves" })
                if ($profile) {
                    Invoke-ToolkitCommand -Name "inspect-blam" -Args @("-ProfileName", $profile)
                }
                else {
                    Invoke-ToolkitCommand -Name "inspect-blam"
                }
            }
            "Quick diagnosis" {
                Write-ToolkitPrepTitle "Preparing - Quick diagnosis" "Preparando - Diagnostico rapido"
                Invoke-ToolkitCommand -Name "quick-diagnosis"
            }
            "Find latest known errors" {
                Write-ToolkitPrepTitle "Preparing - Find latest known errors" "Preparando - Ver ultimos errores"
                Invoke-ToolkitCommand -Name "errors" -Args @("-ServerOnly", "-IncludeMapLogs")
            }
            "Clear client global mods (WhatIf first)" {
                Write-ToolkitPrepTitle "Preparing - Clear client global mods" "Preparando - Limpiar mods globales cliente"
                Invoke-ToolkitCommand -Name "clear-client-mods" -Args @("-WhatIf")
                $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora la limpieza real de mods globales?" } else { "Run the real clear-client-mods operation now?" }
                if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                    Invoke-ToolkitCommand -Name "clear-client-mods"
                }
            }
            "Repair Workshop redownload issue (WhatIf)" {
                Write-ToolkitPrepTitle "Preparing - Repair Workshop redownload issue" "Preparando - Reparar redownload Workshop"
                Invoke-ToolkitCommand -Name "repair-workshop" -Args @("-WhatIf")
            }
            "Compare sandbox profiles" {
                Write-ToolkitPrepTitle "Preparing - Compare sandbox profiles" "Preparando - Comparar sandbox"
                $left = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil base/izquierdo de sandbox" } else { "Choose left/base sandbox profile" })
                if (-not $left) { continue }
                $paths = Get-PZTPaths
                $profiles = @(Get-PZTHostedProfileNames -ServerDir $paths.ServerDir | Where-Object { $_ -ne $left })
                $right = Read-PZTMenuChoice -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil destino/derecho de sandbox" } else { "Choose right/target sandbox profile" }) -Items $profiles -AllowCancel
                if (-not $right) { continue }
                Invoke-ToolkitCommand -Name "compare-sandbox" -Args @("-LeftProfile", $left, "-RightProfile", $right)
            }
            "Compare mods / workshop / maps" {
                Write-ToolkitPrepTitle "Preparing - Compare mods / workshop / maps" "Preparando - Comparar mods/workshop/mapas"
                $left = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil base/izquierdo" } else { "Choose left/base profile" })
                if (-not $left) { continue }
                $paths = Get-PZTPaths
                $profiles = @(Get-PZTHostedProfileNames -ServerDir $paths.ServerDir | Where-Object { $_ -ne $left })
                $right = Read-PZTMenuChoice -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil destino/derecho" } else { "Choose right/target profile" }) -Items $profiles -AllowCancel
                if (-not $right) { continue }
                Invoke-ToolkitCommand -Name "compare-mods" -Args @("-LeftProfile", $left, "-RightProfile", $right)
            }
            "Copy world/save to another profile (WhatIf first)" {
                Write-ToolkitPrepTitle "Preparing - Copy world/save" "Preparando - Copiar mundo/save"
                $source = Read-ToolkitRequiredProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil origen" } else { "Choose source profile" })
                if (-not $source) { continue }
                $target = Read-ToolkitRequiredProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil destino" } else { "Choose target profile" })
                if (-not $target) { continue }
                $args = @("-SourceProfileName", $source, "-TargetProfileName", $target, "-WhatIf")
                Invoke-ToolkitCommand -Name "copy-world" -Args $args
                $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora la copia real de mundo? Los datos del destino pueden sobrescribirse con -Overwrite." } else { "Run the real copy-world operation now? Target world data may be overwritten with -Overwrite." }
                if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                    $realArgs = @("-SourceProfileName", $source, "-TargetProfileName", $target, "-Overwrite", "-ConfirmCopy")
                    Invoke-ToolkitCommand -Name "copy-world" -Args $realArgs
                }
            }
            "Copy players to another profile (WhatIf first)" {
                Write-ToolkitPrepTitle "Preparing - Copy players" "Preparando - Copiar jugadores"
                $source = Read-ToolkitRequiredProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil origen" } else { "Choose source profile" })
                if (-not $source) { continue }
                $target = Read-ToolkitRequiredProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil destino" } else { "Choose target profile" })
                if (-not $target) { continue }
                $args = @("-SourceProfileName", $source, "-TargetProfileName", $target, "-WhatIf")
                Invoke-ToolkitCommand -Name "copy-players" -Args $args
                $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora la copia real de jugadores? Si existe players.db en destino requiere overwrite." } else { "Run the real copy-players operation now? Existing target players.db requires overwrite." }
                if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                    $realArgs = @("-SourceProfileName", $source, "-TargetProfileName", $target, "-Overwrite", "-ConfirmCopy")
                    Invoke-ToolkitCommand -Name "copy-players" -Args $realArgs
                }
            }
            "Back up a hosted profile" {
                Write-ToolkitPrepTitle "Preparing - Back up hosted profile" "Preparando - Crear backup de perfil"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) { Invoke-ToolkitCommand -Name "backup-profile" -Args @("-ProfileName", $profile) }
            }
            "Verify a backup folder" {
                Write-ToolkitPrepTitle "Preparing - Verify backup folder" "Preparando - Verificar backup"
                $backup = Read-ToolkitBackupPath
                if ($backup) { Invoke-ToolkitCommand -Name "verify-backup" -Args @("-BackupPath", $backup) }
            }
            "Export profile mod/map lists" {
                Write-ToolkitPrepTitle "Preparing - Export profile lists" "Preparando - Exportar perfil"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) {
                    $out = Read-ToolkitOutputDir -DefaultName $profile
                    Invoke-ToolkitCommand -Name "export-profile" -Args @("-ProfileName", $profile, "-OutputDir", $out)
                }
            }
            "Restore or copy a profile from backup" {
                Write-ToolkitPrepTitle "Preparing - Restore or copy profile" "Preparando - Restaurar/copiar perfil"
                $backup = Read-ToolkitBackupPath
                if ($backup) {
                    $targetPrompt = if ((Get-PZTLanguage) -eq "es") { "Nombre de perfil destino (en blanco para restaurar nombre original)" } else { "Target profile name (leave blank to restore original name)" }
                    $target = Read-Host $targetPrompt
                    $sourceFromBackup = Get-ToolkitBackupSourceProfileName -BackupPath $backup
                    $effectiveTarget = if ($target) { $target } else { $sourceFromBackup }
                    $targetExists = if ($effectiveTarget) { Test-ToolkitProfileTargetExists -ProfileName $effectiveTarget } else { $true }
                    $allowOverwrite = $false
                    if ($targetExists) {
                        $prompt = if ((Get-PZTLanguage) -eq "es") { "El perfil destino '$effectiveTarget' ya existe. Permitir overwrite? Antes se crea backup de seguridad." } else { "Target profile '$effectiveTarget' already exists. Allow overwrite? A safety backup is created first." }
                        $allowOverwrite = Read-PZTYesNo -Prompt $prompt -Default $false
                    }
                    else {
                        if ((Get-PZTLanguage) -eq "es") { Write-PZTStep "El perfil destino '$effectiveTarget' no existe; no hace falta overwrite." "pz-toolkit" } else { Write-PZTStep "Target profile '$effectiveTarget' does not exist; overwrite is not needed." "pz-toolkit" }
                    }
                    $args = @("-BackupPath", $backup, "-WhatIf")
                    if ($target) { $args += @("-TargetProfileName", $target) }
                    if ($allowOverwrite) { $args += "-Overwrite" }
                    Invoke-ToolkitCommand -Name "restore-profile" -Args $args
                    $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora la restauracion/copia real?" } else { "Run the real restore/copy operation now?" }
                    if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                        $realArgs = @("-BackupPath", $backup, "-ConfirmRestore")
                        if ($target) { $realArgs += @("-TargetProfileName", $target) }
                        if ($allowOverwrite) { $realArgs += "-Overwrite" }
                        Invoke-ToolkitCommand -Name "restore-profile" -Args $realArgs
                    }
                }
            }
            "Reset selected profile world/map (WhatIf first)" {
                Write-ToolkitPrepTitle "Preparing - Reset selected profile world/map" "Preparando - Resetear mundo/mapa"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) {
                    Invoke-ToolkitCommand -Name "reset-world" -Args @("-ProfileName", $profile, "-WhatIf")
                    $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora el reset real del mundo?" } else { "Run the real reset-world operation now?" }
                    if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                        Invoke-ToolkitCommand -Name "reset-world" -Args @("-ProfileName", $profile, "-ConfirmReset")
                    }
                }
            }
            "Reset one hosted player (WhatIf first)" {
                Write-ToolkitPrepTitle "Preparing - Reset one hosted player" "Preparando - Resetear jugador"
                $profile = Read-ToolkitProfile -Prompt $(if ((Get-PZTLanguage) -eq "es") { "Elige perfil hosted" } else { "Choose hosted profile" })
                if ($profile) {
                    $usernamePrompt = if ((Get-PZTLanguage) -eq "es") { "Filtro Steam/usuario (en blanco si no estas seguro)" } else { "Steam/user name filter (leave blank if unsure)" }
                    $username = Read-Host $usernamePrompt
                    $args = @("-ProfileName", $profile, "-PlayerIndex", "0", "-WhatIf")
                    if ($username) { $args += @("-Username", $username) }
                    Invoke-ToolkitCommand -Name "reset-player" -Args $args
                    $prompt = if ((Get-PZTLanguage) -eq "es") { "Ejecutar ahora el reset real del jugador?" } else { "Run the real reset-player operation now?" }
                    if (Read-PZTYesNo -Prompt $prompt -Default $false) {
                        $realArgs = @("-ProfileName", $profile, "-PlayerIndex", "0", "-ConfirmReset")
                        if ($username) { $realArgs += @("-Username", $username) }
                        Invoke-ToolkitCommand -Name "reset-player" -Args $realArgs
                    }
                }
            }
            "Show command help" {
                Show-Help
            }
            "Quit" {
                return
            }
        }

        if ($choice -ne "Quit") {
            Write-Host ""
            Write-Host "----------------------------------------"
            if ((Get-PZTLanguage) -eq "es") {
                Write-Host "ENTER: volver al menu    Q/Esc: salir" -ForegroundColor DarkGray
            }
            else {
                Write-Host "ENTER: return to menu    Q/Esc: quit" -ForegroundColor DarkGray
            }
            while ($true) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Enter") { break }
                if ($key.Key -eq "Escape" -or $key.KeyChar -match '^[qQ]$') { return }
            }
            $freshMenu = $true
        }
    }
}

if ($Command -in @("help", "-h", "--help", "/?")) {
    Show-Help
    exit 0
}

if ($Command -in @("menu", "interactive")) {
    Show-Menu
    exit 0
}

if (-not $commands.ContainsKey($Command)) {
    Show-Help
    throw "Unknown command: $Command"
}

Invoke-ToolkitCommand -Name $Command -Args $RemainingArgs
exit $script:ToolkitLastExitCode
