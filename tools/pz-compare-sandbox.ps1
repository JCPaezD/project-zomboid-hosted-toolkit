param(
    [string]$LeftProfile,
    [string]$RightProfile,
    [string]$ZomboidRoot,
    [string]$OutputCsv,
    [int]$MaxItems = 40,
    [switch]$IncludeProfileOnlyDetails,
    [switch]$All
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\PZToolkit.Common.ps1"

Write-PZTTitle "PZ Hosted Toolkit - Compare Sandbox" "pz-compare-sandbox"

function Read-SandboxVars {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "SandboxVars file not found: $Path" }

    $result = @{}
    $stack = New-Object System.Collections.Generic.List[string]

    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = ($raw -replace "--.*$", "").Trim()
        if (-not $line) { continue }

        if ($line -match '^([A-Za-z0-9_]+)\s*=\s*\{\s*$') {
            $stack.Add($matches[1])
            continue
        }
        if ($line -match '^\},?\s*$') {
            if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
            continue
        }
        if ($line -match '^([A-Za-z0-9_]+)\s*=\s*(.+?),?\s*$') {
            $key = $matches[1]
            $value = $matches[2].Trim()
            $pathParts = @($stack.ToArray()) + @($key)
            $result[($pathParts -join ".")] = $value
        }
    }

    return $result
}

function Get-SandboxSection {
    param([Parameter(Mandatory=$true)][string]$Key)
    $parts = $Key -split "\."
    if ($parts.Count -ge 2) { return $parts[1] }
    return $parts[0]
}

$paths = Get-PZTPaths -ZomboidRoot $ZomboidRoot

if (-not $LeftProfile -or -not $RightProfile) {
    $profiles = Get-PZTHostedProfileNames -ServerDir $paths.ServerDir
    if (-not $LeftProfile) {
        $LeftProfile = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose left/base sandbox profile" "Elige perfil sandbox izquierdo/base") -Items $profiles -AllowCancel
        if (-not $LeftProfile) { exit 0 }
    }
    $rightChoices = @($profiles | Where-Object { $_ -ne $LeftProfile })
    if (-not $RightProfile) {
        $RightProfile = Read-PZTMenuChoice -Prompt (Get-PZTText "Choose right/target sandbox profile" "Elige perfil sandbox derecho/objetivo") -Items $rightChoices -AllowCancel
        if (-not $RightProfile) { exit 0 }
    }
}

$leftPath = Join-Path $paths.ServerDir "${LeftProfile}_SandboxVars.lua"
$rightPath = Join-Path $paths.ServerDir "${RightProfile}_SandboxVars.lua"

$left = Read-SandboxVars -Path $leftPath
$right = Read-SandboxVars -Path $rightPath
$leftSections = @($left.Keys | ForEach-Object { Get-SandboxSection -Key $_ } | Sort-Object -Unique)
$rightSections = @($right.Keys | ForEach-Object { Get-SandboxSection -Key $_ } | Sort-Object -Unique)
$commonSections = @($leftSections | Where-Object { $rightSections -contains $_ })

$keys = @($left.Keys + $right.Keys | Sort-Object -Unique)
$diffs = foreach ($key in $keys) {
    $lv = if ($left.ContainsKey($key)) { $left[$key] } else { $null }
    $rv = if ($right.ContainsKey($key)) { $right[$key] } else { $null }
    if ($lv -ne $rv) {
        [pscustomobject]@{
            Key = $key
            Section = Get-SandboxSection -Key $key
            Scope = if ($commonSections -contains (Get-SandboxSection -Key $key)) { "CommonSection" } else { "ProfileOnlySection" }
            LeftProfile = $LeftProfile
            LeftValue = $lv
            RightProfile = $RightProfile
            RightValue = $rv
        }
    }
}

if ($OutputCsv) {
    $diffs | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-PZTStep ((Get-PZTText "Wrote sandbox diff: {0}" "Diferencias de sandbox escritas en: {0}") -f $OutputCsv) "pz-compare-sandbox"
}
else {
    Write-PZTStep ((Get-PZTText "Comparing '{0}' -> '{1}'" "Comparando '{0}' -> '{1}'") -f $LeftProfile, $RightProfile) "pz-compare-sandbox"
    $diffCount = @($diffs).Count
    if ($diffCount -eq 0) {
        Write-PZTStep (Get-PZTText "No sandbox differences found." "No se han encontrado diferencias de sandbox.") "pz-compare-sandbox"
    }
    else {
        Write-PZTStep ((Get-PZTText "{0} differences found." "{0} diferencias encontradas.") -f $diffCount) "pz-compare-sandbox"
        $commonDiffs = @($diffs | Where-Object { $_.Scope -eq "CommonSection" })
        $profileOnlyDiffs = @($diffs | Where-Object { $_.Scope -eq "ProfileOnlySection" })
        Write-Host ""
        Write-Host (Get-PZTText "=== Differences by section ===" "=== Diferencias por seccion ===")
        $sectionCounts = @($commonDiffs |
            Group-Object Section |
            Sort-Object Count -Descending)
        if ($sectionCounts.Count -eq 0) {
            Write-Host (Get-PZTText "  No differences in sections shared by both profiles." "  No hay diferencias en secciones compartidas por ambos perfiles.")
        }
        else {
            foreach ($group in $sectionCounts) {
                Write-Host ("  {0}: {1}" -f $group.Name, $group.Count)
            }
        }

        if ($profileOnlyDiffs.Count -gt 0) {
            Write-Host ""
            Write-Host (Get-PZTText "=== Profile-only / mod sections ===" "=== Secciones solo de perfil / mod ===")
            $profileOnlyRows = @($profileOnlyDiffs |
                Group-Object Section |
                Sort-Object Count -Descending |
                ForEach-Object {
                    $leftCount = @($_.Group | Where-Object { $null -ne $_.LeftValue }).Count
                    $rightCount = @($_.Group | Where-Object { $null -ne $_.RightValue }).Count
                    $side = if ($leftCount -gt 0 -and $rightCount -eq 0) {
                        $LeftProfile
                    }
                    elseif ($rightCount -gt 0 -and $leftCount -eq 0) {
                        $RightProfile
                    }
                    else {
                        (Get-PZTText "both/different" "ambos/diferente")
                    }
                    [pscustomobject]@{
                        Section = $_.Name
                        OnlyIn = $side
                        Settings = $_.Count
                        LeftValues = $leftCount
                        RightValues = $rightCount
                    }
                })
            $shownProfileOnlyRows = if ($All) { $profileOnlyRows } else { $profileOnlyRows | Select-Object -First $MaxItems }
            $shownProfileOnlyRows | Format-Table Section, OnlyIn, Settings, LeftValues, RightValues -AutoSize
            if (-not $All -and $profileOnlyRows.Count -gt $MaxItems) {
                Write-PZTStep ((Get-PZTText "Showing first {0} profile-only sections. Add -All to print every summarized section." "Mostrando primeras {0} secciones solo de perfil. Anade -All para imprimir todas las secciones resumidas.") -f $MaxItems) "pz-compare-sandbox"
            }
            if (-not $IncludeProfileOnlyDetails -and -not $All) {
                Write-PZTStep (Get-PZTText "Profile-only sections are summarized to keep vanilla/shared sandbox changes readable. Add -IncludeProfileOnlyDetails or -All for their values." "Las secciones solo de perfil se resumen para que los cambios vanilla/compartidos sean legibles. Anade -IncludeProfileOnlyDetails o -All para ver sus valores.") "pz-compare-sandbox"
            }
        }

        $detailDiffs = if ($All) {
            $diffs
        }
        elseif ($IncludeProfileOnlyDetails) {
            $diffs
        }
        else {
            $commonDiffs
        }
        $shown = if ($All) { $detailDiffs } else { $detailDiffs | Select-Object -First $MaxItems }
        Write-Host ""
        Write-Host (Get-PZTText "=== Changed values in shared sections ===" "=== Valores cambiados en secciones compartidas ===")
        if (@($shown).Count -eq 0) {
            Write-Host (Get-PZTText "  No changed values to show in shared sections." "  No hay valores cambiados que mostrar en secciones compartidas.")
        }
        else {
            foreach ($diff in $shown) {
                Write-Host ("- {0}" -f $diff.Key)
                Write-Host ("  {0}: {1}" -f $LeftProfile, $diff.LeftValue)
                Write-Host ("  {0}: {1}" -f $RightProfile, $diff.RightValue)
            }
        }

        if (-not $All -and @($detailDiffs).Count -gt $MaxItems) {
            Write-Host ""
            Write-PZTStep ((Get-PZTText "Showing first {0} value differences. Add -All to print every difference, or -OutputCsv <path> for a full CSV." "Mostrando primeras {0} diferencias de valores. Anade -All para imprimir todas, o -OutputCsv <ruta> para un CSV completo.") -f $MaxItems) "pz-compare-sandbox"
        }
    }
}
