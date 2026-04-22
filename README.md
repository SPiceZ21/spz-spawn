<div align="center">

<img src="https://github.com/SPiceZ21/spz-core-media-kit/raw/main/Banner/Banner%232.png" alt="SPiceZ-Core Banner" width="100%"/>

<br/>

# spz-spawn

### Cinematic Player Entry & Location Selection

*Experience the world of SPiceZ Racing from the moment you join. Cinematic camera transitions and a premium UI set the stage for your journey.*

<br/>

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-orange.svg?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-orange?style=flat-square)](https://fivem.net)
[![Lua](https://img.shields.io/badge/Lua-5.4-blue?style=flat-square&logo=lua)](https://lua.org)
[![Status](https://img.shields.io/badge/Status-In%20Development-green?style=flat-square)]()

</div>

---

## Overview

`spz-spawn` manages the player's initial entry into the server. Instead of a generic spawn, it activates a scripted cinematic camera that focuses on the player character while presenting a high-fidelity NUI menu. Players can view their driver stats and choose their starting location from a curated list of spawn points.

---

## Features

- **Cinematic Showcase** — Scripted camera system that highlights the player's character upon joining.
- **Premium UI** — AAA-style spawn menu with glassmorphism, smooth animations, and driver information (Name, Playtime).
- **Location Selector** — Choose from multiple spawn locations (e.g., Legion Square, Paleto Bay, Motels) defined in `config.lua`.
- **Seamless Integration** — Works with `spz-identity` for profile data and `spz-core` for state management.
- **Automatic Cleanup** — Camera and UI are automatically destroyed once the player confirms their spawn.

---

## Dependencies

| Resource | Version | Role |
|---|---|---|
| `spz-lib` | 1.0.0+ | Shared utilities |
| `spz-core` | 1.0.0+ | Session and config management |
| `spz-identity` | 1.0.0+ | Player profile and playtime tracking |

---

## Installation

1. Ensure the resource folder is named `spz-spawn`.
2. Add to `server.cfg`:

```cfg
ensure spz-lib
ensure spz-core
ensure spz-identity
ensure spz-spawn
```

---

## Configuration

Spawn locations are defined in `config.lua`:

```lua
Config.Spawns = {
    {
        label = 'Legion Square',
        coords = vec4(195.17, -933.77, 29.7, 144.5)
    },
    -- ...
}
```

---

## Events

| Event | Direction | When |
|---|---|---|
| `SPZ:showPlayMenu` | Server → Client | Triggered when the player is ready to spawn |
| `SPZ:spawnPlayerTarget` | Server → Client | Triggered when the player confirms a spawn location |

---

<div align="center">

*Part of the [SPiceZ-Core](https://github.com/SPiceZ-Core) ecosystem*

**[Docs](https://github.com/SPiceZ-Core/spz-docs) · [Discord](https://discord.gg/) · [Issues](https://github.com/SPiceZ-Core/spz-spawn/issues)**

</div>
