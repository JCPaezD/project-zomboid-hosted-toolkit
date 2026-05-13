# First-run guide

This guide is for users who are not comfortable with PowerShell yet.

## 1. Start with the menu

Open the toolkit folder and double-click:

```text
scripts\toolkit.cmd
```

Use the arrow keys to move, Enter to run the selected action, and `Q` to quit.

## 2. Run a read-only diagnosis first

Choose:

```text
Quick diagnosis
```

This does not edit your Project Zomboid files. It checks the common places where hosted-server problems show up:

- hosted profiles;
- client global mods;
- recent server log errors;
- problem chunks;
- profile file consistency.

## 3. Back up before changing anything

Before changing mods, restoring a profile, copying players, resetting a world, or trying repairs, choose:

```text
Back up a hosted profile
```

Then choose:

```text
Verify a backup folder
```

Do not rely on a backup until it verifies as complete.

## 4. Use WhatIf first

Actions that can move, clear, restore, or delete data are designed to show a preview first. If the menu asks whether to run the real operation after a `WhatIf`, only say yes if the preview matches what you intended.

## 5. Close the game before write-capable operations

Project Zomboid, ZombieBuddy, and Java-related helper processes can keep files locked. Close the game before running tools that change files.

Read-only inspection tools can run while the game is closed or open, but logs and saves are easier to reason about when the game is closed.

## 6. Recommended first workflow

1. Quick diagnosis.
2. Inspect the hosted profile you care about.
3. Health-check that profile.
4. Back up that profile.
5. Verify the backup.
6. Only then run any repair, copy, restore, reset, or mod-list cleanup.

## 7. When in doubt

Do not manually delete save chunks, profile databases, or player rows from a valuable save. Create a copied profile first and test there.

