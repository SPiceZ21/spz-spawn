# spz-spawn

> Spawn flow: character creation, play menu and cinematic world entry.

![version](https://img.shields.io/badge/version-1.9.1-ff6200) ![SPiceZ-Core](https://img.shields.io/badge/SPiceZ--Core-beta-18181b)

## Overview

Takes the player from the loading screen to the world: new players go through character creation (fivem-appearance), everyone lands on the play menu, and the entry is covered by a transition so the world never pops in.

## Features

- First-join character creation
- Play menu with cinematic camera
- Loading-screen progress stages (with spz-loading)
- Transition cover over every spawn

## Requirements

| Resource | Type |
|---|---|
| `spawnmanager` | third-party |
| `ox_lib` | third-party |
| `spz-core` | SPiceZ module |
| `spz-identity` | SPiceZ module |

## Installation

Included in the [txAdmin recipe](https://github.com/SPiceZ21/spz-txrecipe). Manual install:

1. Download `spz-spawn` from GitHub (latest release, or the repository) into your `resources` folder.
2. Add to `server.cfg`, after its requirements:

```cfg
ensure spz-spawn
```

## Configuration

- `config.lua`

See the file for every option.

---

Part of **SPiceZ-Core** — [documentation](https://github.com/SPiceZ21/Docs) · [all modules](https://github.com/SPiceZ21/Docs/blob/main/modules/README.md)
