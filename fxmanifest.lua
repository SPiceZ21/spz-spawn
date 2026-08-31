fx_version 'cerulean'
game 'gta5'

name 'spz-spawn'
description 'SPiceZ-Core â€” Standalone Spawning Manager'
version '2.1.0'
author 'SPiceZ-Core'

ui_page 'ui/dist/index.html'

shared_scripts {
    -- ox_lib was listed as a dependency but never actually loaded, so `lib` was
    -- nil in this resource. Anything reaching for it errored.
    '@ox_lib/init.lua',
    '@spz-core/config.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'ui/dist/**/*',
}

dependencies {
    'spawnmanager',
    'ox_lib',
    'spz-core',
    'spz-identity'
}

