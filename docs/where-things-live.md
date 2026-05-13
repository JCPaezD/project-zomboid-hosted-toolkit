# Where Things Live

Project Zomboid hosted multiplayer uses several independent file locations. Knowing which piece does what prevents accidental rollbacks or partial restores.

## Hosted Server Profile

```text
%USERPROFILE%\Zomboid\Server\<profile>.ini
%USERPROFILE%\Zomboid\Server\<profile>_SandboxVars.lua
%USERPROFILE%\Zomboid\Server\<profile>_spawnpoints.lua
%USERPROFILE%\Zomboid\Server\<profile>_spawnregions.lua
```

Important fields in `<profile>.ini`:

```text
Mods=
WorkshopItems=
Map=
PublicName=
```

The host profile is what tells clients which Workshop items and mod IDs are required.

## Save / World Data

```text
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>\
```

This contains map chunks, world metadata, vehicles, and `players.db`.

## Hosted Player Data

```text
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>\players.db
```

For hosted multiplayer, player rows are commonly stored in the `networkPlayers` table. A row includes:

```text
world
username
playerIndex
name
steamid
x, y, z
data
isDead
```

If you rename a profile and keep the save, `networkPlayers.world` may need to match the new profile name.

## Local Player Folder

```text
%USERPROFILE%\Zomboid\Saves\Multiplayer\<profile>_player\
```

Hosted games can create this folder for local/connection state. Do not assume it is the only player state.

## Server Database

```text
%USERPROFILE%\Zomboid\db\<profile>.db
```

Contains server-side user/admin tables such as `whitelist`. This is not the same as `players.db`.

## Client Global Mods

```text
%USERPROFILE%\Zomboid\mods\default.txt
```

This is the active client-side mod list from the Mods menu. For hosted-server work, it is often safer to keep it empty and let the server profile load mods.

## Logs

```text
%USERPROFILE%\Zomboid\Logs\
%USERPROFILE%\Zomboid\console.txt
```

Useful logs include:

```text
*DebugLog.txt
*DebugLog-server.txt
```

## Steam Workshop Cache

```text
<SteamLibrary>\steamapps\workshop\content\108600\<WorkshopID>\
<SteamLibrary>\steamapps\workshop\downloads\108600\<WorkshopID>\
```

`content` is installed Workshop content. `downloads` can contain a prepared update that PZ failed to apply.
