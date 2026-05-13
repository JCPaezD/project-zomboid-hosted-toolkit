# Scope And Safety

This document defines the intended scope, safety model, and design boundaries for PZ Hosted Toolkit.

## Target Scope

- Primary target: Windows hosted/co-op multiplayer launched through Project Zomboid's in-game **Host** menu.
- Primary use case: modded hosted/co-op profiles where Steam Workshop updates, profile files, saves, logs, and players are hard to reason about from the game UI alone.
- Primary tested game version: Project Zomboid Build 42.
- Default PZ user folder: `%USERPROFILE%\Zomboid`.
- Steam Workshop app ID for Project Zomboid: `108600`.
- PowerShell is the primary runtime.
- Python is used only for controlled SQLite operations when reading or modifying `players.db`.

## Out Of Scope For v0.1

- Dedicated server panels or full dedicated-server administration.
- Docker or commercial hosting panel management.
- Linux/macOS support guarantees.
- Steam login, Steam API automation, or Workshop subscription management.
- Automatic mod compatibility scoring.
- Automatic modpack fixing.
- Editing Project Zomboid saves while the game is running.
- Replacing real backups.

## Safety Model

- Prefer read-only diagnosis before repair.
- Prefer `-WhatIf` before write operations.
- Create backups before destructive or hard-to-reverse changes.
- Touch the smallest possible file set.
- Refuse or warn when Project Zomboid, Java, ZombieBuddy, or related processes may be using files.
- Use structured APIs for SQLite data instead of editing databases as text.
- Avoid rewriting encoding-sensitive `.lua` and `.ini` files unless a specific operation requires it.
- Keep generated backups and exports outside source-controlled project files.

## Design Decisions

- The root `pz-toolkit.ps1` is the preferred entrypoint for both interactive and command use.
- The terminal UI is a lightweight human-friendly layer, not a full GUI framework.
- Direct scripts under `tools\` remain usable for repeatable commands, tests, and advanced users.
- The initial public documentation is English-first.
- An initial Spanish interactive layer is available for the guided menu and common human-facing prompts.
- Hosted profile names and save folder names can differ; tools resolve the active save folder when world/player operations need it.
- Restore/copy from backup is supported for toolkit-created backup folders. Backups from other layouts may need manual inspection.
- Sandbox comparison favors readability by summarizing sections that only exist in one profile. Full detail is still available through flags or CSV export.
- Backup manifests list file sizes by default for speed. SHA256 hashes are optional through `-HashManifest` because large PZ saves can contain many thousands of files.
- MIT is the default license for public reuse.

## Known Limitations

- Build 41 may share many paths and concepts, but it is not the primary test target for v0.1.
- Modded saves can become unstable when mods are added, removed, or updated. The toolkit can help inspect and back up state, but it cannot guarantee mod compatibility.
- Chunk/world operations are inherently risky. Copying or resetting world data should always be preceded by a verified backup.
- Workshop update failures can have multiple causes. The repair script intentionally handles only a narrow staged-download case.
- The toolkit does not know whether a Steam collection contains abandoned, incompatible, or conflicting mods.

## Future Work Candidates

- Improve diagnostics for common Workshop/update failure patterns.
- Add more automated tests and representative fixtures.
- Improve support/debug exports for issue reports.
- Add a safe hosted profile rename flow if repeated real-world cases justify it.
- Polish documentation from hosted/co-op troubleshooting cases.
