fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'BPCrime'
description 'BPCrime: parking meters (Tumbler lockpick)'
author 'CBaraUK on GitHub'
version '2.2.0'

shared_scripts {
    'config.lua',
}

client_scripts {
    'features/parkingmeters/client.lua',
}

server_scripts {
    'features/parkingmeters/server.lua',
}

ui_page 'html/index.html'
files { 'html/index.html' }

dependencies {
    'qb-core',
    'qb-target',
}
