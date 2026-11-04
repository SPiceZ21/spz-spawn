fx_version 'cerulean'
game 'gta5'

name 'spz-spawn'
description 'SPiceZ-Core â€” Standalone Spawning Manager'
version '1.9.3'
author 'SPiceZ-Core'

-- ui_page 'ui/dist/index.html'  -- drawn by spz-hud now (web/public/apps/spz-spawn); uncomment + drop the shim to roll back

shared_scripts {
    -- ox_lib was listed as a dependency but never actually loaded, so `lib` was
    -- nil in this resource. Anything reaching for it errored.
    '@ox_lib/init.lua',
    '@spz-core/config.lua',
    'config.lua'
}

client_scripts {
    '@spz-hud/shim.lua',   -- NUI goes through spz-hud
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

-- UI files are not shipped from here: spz-hud serves this resource's page
-- (synced from ui/ by spz-hud/tools/sync-apps.mjs).

dependencies {
    'spz-hud',
    'spawnmanager',
    'ox_lib',
    'spz-core',
    'spz-identity'
}

