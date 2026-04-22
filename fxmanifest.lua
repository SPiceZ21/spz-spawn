fx_version 'cerulean'
game 'gta5'

name 'spz-spawn'
description 'SPiceZ-Core — Standalone Spawning Manager'
version '1.0.0'
author 'SPiceZ-Core'

ui_page 'ui/index.html'

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
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
    'ui/public/logo.png',
    'ui/public/fonts/*.ttf'
}

dependencies {
    'spawnmanager',
    'spz-lib',
    'spz-core',
    'spz-identity'
}
