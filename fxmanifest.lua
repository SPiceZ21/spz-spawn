fx_version 'cerulean'
game 'gta5'

name 'spz-spawn'
description 'SPiceZ-Core — Standalone Spawning Manager'
version '1.1.6'
author 'SPiceZ-Core'

ui_page 'ui/dist/index.html'

shared_scripts {
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
    'spz-lib',
    'spz-core',
    'spz-identity'
}
