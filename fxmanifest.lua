fx_version 'cerulean'
game 'gta5'

name 'spz-spawn'
description 'SPiceZ-Core — Standalone Spawning Manager'
version '1.0.0'
author 'SPiceZ-Core'

shared_scripts {
    '@spz-lib/shared/main.lua',
    '@spz-core/config.lua', -- Use core config for SafeZone coords
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'spz-lib',
    'spz-core',
    'spz-identity'
}
