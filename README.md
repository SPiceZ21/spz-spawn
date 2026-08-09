# spz-spawn

> Play menu, spawn points, world entry · `v2.1.0`

## Overview

`spz-spawn` takes the player from the loading screen into the world. Returning players get
a cinematic play menu with their stats and a spawn-point picker; first-time players go
through `spz-identity` character creation first and only see the menu once the profile is
complete.

## Structure

| Side | File | Purpose |
|---|---|---|
| Shared | `@spz-core/config.lua` | Imported core configuration |
| Shared | `config.lua` | Spawn points and menu options |
| Client | `client/main.lua` | NUI bridge, camera, model set, teleport |
| Server | `server/main.lua` | Spawn authority, profile gating |

## First-time handling

- **Server** — ignores play-menu requests while `profile.first_time == 1`.
- **Client** — shuts the loading screen down, fades the world in, waits for
  `SPZ:characterReady`, then requests the menu.

## Events

| Event | Purpose |
|---|---|
| `SPZ:showPlayMenu` | Open the menu with player metadata |
| `SPZ:spawnPlayerTarget` | Perform the physical spawn (model, teleport, resurrect) |

```lua
TriggerEvent('SPZ:showPlayMenu', { name = 'RacerX', rank = 'C-5', tier = 0, gender = 0 })
```

## Configuration

```lua
Config.Spawns = {
    [1] = { label = 'Safe Zone', coords = vector4(x, y, z, w) },
}
```

## NUI

Vite · Preact · TypeScript on the [spz-ui](../spz-ui/README.md) component set.

```bash
cd ui && npm install && npm run build   # → ui/dist/index.html
```

## Commands

`/testspawn` · `/testcreation` (development helpers)

## Dependencies

`spawnmanager` · `ox_lib` · `spz-core` · `spz-identity`

---

Part of [SPiceZ-Core](../README.md) · GPL-3.0
