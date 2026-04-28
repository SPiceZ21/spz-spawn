<div align="center">

<img src="https://github.com/SPiceZ21/spz-core-media-kit/raw/main/Banner/Banner%232.png" alt="SPiceZ-Core Banner" width="100%"/>

<br/>

# spz-spawn
> Standalone Spawning Manager · `v1.1.6`

## Scripts

| Side   | File                   | Purpose                                           |
| ------ | ---------------------- | ------------------------------------------------- |
| Shared | `@spz-core/config.lua` | Imported core configuration                       |
| Shared | `config.lua`           | Spawn point and options configuration             |
| Client | `client/main.lua`      | Spawn screen NUI bridge, character placement      |
| Server | `server/main.lua`      | Spawn authority, player identity validation       |

## NUI

**Stack:** Vite · Preact · TypeScript · spz-ui

```
ui/
├── src/
│   ├── app.tsx
│   ├── components/       # spz-ui components
│   └── styles/
└── dist/                 # built output (served by FiveM)
    └── index.html
```

Build: `cd ui && npm run build`

## Dependencies
- spawnmanager
- spz-lib
- spz-core
- spz-identity

## CI
Built and released via `.github/workflows/release.yml` on push to `main`.
