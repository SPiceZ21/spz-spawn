-- client/main.lua

local isSpawned = false

--- Disable default spawnmanager as early as possible.
local function DisableSpawnManager()
    if GetResourceState("spawnmanager") == "started" then
        exports.spawnmanager:setAutoSpawn(false)
    end
end

DisableSpawnManager()
AddEventHandler("onClientMapStart", DisableSpawnManager)

--- Physical spawn logic.
--- @param data table Contains gender and optionally coords/heading.
RegisterNetEvent("SPZ:spawnPlayerTarget", function(data)
    local modelHash = data.gender == 1 and `mp_f_freemode_01` or `mp_m_freemode_01`

    DoScreenFadeOut(500)
    Wait(500)

    -- Model management
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do Wait(0) end
    SetPlayerModel(PlayerId(), modelHash)
    SetModelAsNoLongerNeeded(modelHash)

    -- Coordinate resolution (default to SafeZone if not provided)
    local coords  = data.coords or Config.SafeZone.coords
    local heading = data.heading or Config.SafeZone.heading

    -- Physical resurrect/teleport
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, true)

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    ClearPedBloodDamage(ped)
    RemoveAllPedWeapons(ped, true)

    -- State synchronization
    exports["spz-identity"]:SetPlayerState("FREEROAM")
    isSpawned = true

    -- Trigger external systems (appearance, etc.)
    TriggerEvent("SPZ:applyOutfit")
    
    DoScreenFadeIn(1000)
end)

--- Shutdown loading screen after identity is ready and play menu is shown.
RegisterNetEvent("SPZ:showPlayMenu", function()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end)

--- Generic teleport (formerly tpToSafeZone)
RegisterNetEvent("SPZ:teleportTo", function(coords, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    if heading then SetEntityHeading(ped, heading) end
end)

-- Note: Death monitor removed as per requirements.
