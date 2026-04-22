-- config.lua
Config = Config or {}

-- Spawn locations
Config.Spawns = {
    {
        label = 'Legion Square',
        coords = vec4(195.17, -933.77, 29.7, 144.5)
    },
    {
        label = 'Paleto Bay',
        coords = vec4(80.35, 6424.12, 31.67, 45.5),
    },
    {
        label = 'Motels',
        coords = vec4(327.56, -205.08, 53.08, 163.5),
    },
}

-- Default fallback if no selection is made (SafeZone)
Config.SafeZone = {
    coords = vec3(195.17, -933.77, 29.7),
    heading = 144.5
}
