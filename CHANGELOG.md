# Changelog

## 0.1.0-alpha - 2026-05-13

- Added `pz-inspect-blam.ps1` to inspect B42 `blam` chunk-load failures safely.
- Added `pz-compare-mods.ps1` to compare `Mods`, `WorkshopItems`, and `Map` lists between hosted profiles.
- Added `pz-health-check.ps1` for one-profile consistency checks.
- Added `pz-quick-diagnosis.ps1` for read-only OK/Warning/Needs attention triage.
- Improved `pz-find-latest-error.ps1` with `-IncludeMapLogs`, key findings, and clearer known-pattern explanations.
- Improved `pz-compare-mods.ps1` with compact defaults plus `-Detailed` and `-MaxItems`.
- Added classifications for problem chunks, object mod-data, receive mod-data, memory pressure, animal population/apop, and noisy NetChecksum null-path errors.
- Reworked the interactive toolkit menu toward a lightweight TUI: grouped actions, color, cursor navigation, `H` help, and `Q` quit.
- Updated profile and backup pickers to use the same cursor-based interaction style.
- Extended smoke tests for mod diffs, empty lists, profile names with spaces, health checks, quick diagnosis, `blam` inspection, and map-log error detection.
- Added first-run, publishing, and contribution guidance for a public v0.1 release.
- Improved Workshop redownload repair so missing staged downloads are reported as a non-fatal "nothing to swap" state, and embedded PZ Workshop folders from logs are considered.
- Improved quick diagnosis so Workshop update locks are identified directly, including the likely Workshop ID, staged-download state, and next action.
- Added `scripts\toolkit-es.cmd` and an initial Spanish interactive layer for the guided menu and quick diagnosis suggestions.
- Compactified the TUI menu into two columns and changed post-action handling so Enter returns to the menu while Q/Esc quits.
- Polished the TUI menu with clearer header/footer separation, per-column header coloring, and more Spanish prompts in interactive mode.
- Added selected-action descriptions to the TUI and expanded Spanish localization for common prompts/titles in interactive flows.
- Moved copy-players impact output before overwrite refusal so `-WhatIf` review shows source/target players even when target data exists.
- Added timestamps/time markers to latest-error summaries.
- Added Spanish headings, tips, and suggested next checks to latest-error when `PZTK_LANGUAGE=es`.
- Added player/save impact summaries before world/player copy or reset operations.
- Expanded profile export with server settings, sandbox copy, and players CSV when available.
- Normalized profile exports so simple custom names are stored under `exports\<name>` instead of creating loose toolkit-root folders.
- Improved backup progress messages with file counts for long folder copies.

## 0.1.0-prototype

- Added audit, backup, export, client-mod clearing, player reset, log search, and Workshop redownload repair scripts.
- Added profile inspector for one-profile summaries.
- Added conservative `copy-world` and `copy-players` transfer tools.
- Added hosted test-world reset and sandbox comparison scripts.
- Added a root `pz-toolkit.ps1` command hub with interactive menu and command dispatch modes.
- Added interactive profile selection to sandbox comparison.
- Added profile restore/copy from toolkit backups.
- Added backup verification and explicit backup completion status files.
- Changed backup manifests to avoid slow SHA256 hashing by default; use `-HashManifest` when full hashes are worth the wait.
- Added script title banners for clearer interactive execution.
- Improved the interactive menu with clearer top-level screen, preparation banners, and footer hints.
- Reorganized the interactive menu into functional groups.
- Added save-folder name resolution for profiles whose visible name differs from the save directory.
- Updated `scripts\toolkit.cmd` so normal Quit can close without an extra pause while errors still pause.
- Improved restore/copy so overwrite is only requested interactively when the target exists, and `PublicName` is updated when it matches the source profile name.
- Improved sandbox comparison default output with section summary, output limit, and `-All`.
- Improved sandbox comparison again by separating shared settings from profile-only/mod sections.
- Added suggested next checks to latest-error summaries.
- Added interactive backup selection for restore/copy.
- Renamed interactive reset wording to avoid implying the selected world is automatically disposable.
- Added fixture-based smoke tests under `tests\`.
- Improved latest-error output with category summaries and a detailed mode.
- Made Workshop repair report "nothing to repair" without a stack trace when no matching log pattern exists.
- Added English documentation for hosted profile layout, safe operations, troubleshooting, and scope/safety boundaries.
- Added simple `.cmd` wrappers for common read-only or `-WhatIf` flows.
