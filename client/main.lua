-- client/main.lua

local isSpawned = false
local cam = nil

--- Disable default spawnmanager aggressively.
local function DisableSpawnManager()
    pcall(function()
        exports.spawnmanager:setAutoSpawn(false)
        exports.spawnmanager:forceGameState('MANUAL')
    end)
end

-- Run immediately and on start
DisableSpawnManager()

AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    DisableSpawnManager()
end)

-- Backup loop for 5 seconds
CreateThread(function()
    for i = 1, 50 do
        DisableSpawnManager()
        Wait(100)
    end
end)

AddEventHandler("onClientMapStart", DisableSpawnManager)

CreateThread(function()
    -- Wait for the game to settle and loading screen to fade (usually takes a few seconds)
    Wait(2500)
    print("^2[spz-spawn] Client ready: requesting play menu from server.^7")
    TriggerServerEvent("SPZ:requestPlayMenu")
end)

--- Cinematic Camera System
local function CreateCinematicCamera()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    
    -- Position camera in front of the player, slightly up
    local camCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 1.0)
    
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(cam, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtEntity(cam, ped, 0.0, 0.0, 0.0, true)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, true)
    
    -- Optional: DOF or smooth movement could be added here
    SetCamFov(cam, 50.0)
end


local function DestroyCinematicCamera()
    if cam then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

--- Physical spawn logic.
--- @param data table Contains gender and optionally coords/heading.
RegisterNetEvent("SPZ:spawnPlayerTarget", function(data)
    local modelHash = data.gender == 1 and `mp_f_freemode_01` or `mp_m_freemode_01`

    DoScreenFadeOut(500)
    Wait(500)

    -- Cleanup UI & Camera
    SendNUIMessage({ type = 'hide' })
    SetNuiFocus(false, false)
    DestroyCinematicCamera()
    FreezeEntityPosition(PlayerPedId(), false)
    DisplayHud(true)
    DisplayRadar(true)

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
RegisterNetEvent("SPZ:showPlayMenu", function(playerData)
    print("^2[spz-spawn] DEBUG: Client received showPlayMenu^7")
    
    -- Force kill all loading screens
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    
    -- Ensure screen is clear
    DoScreenFadeIn(0)
    
    -- Activate cinematic mode
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true)
    DisplayHud(false)
    DisplayRadar(false)
    
    CreateCinematicCamera()
    
    -- Show NUI
    print("^2[spz-spawn] DEBUG: Opening NUI menu^7")
    SendNUIMessage({
        type = 'show',
        playerData = playerData,
        spawns = Config.Spawns
    })
    SetNuiFocus(true, true)
end)

print("^2[spz-spawn] Client script initialized.^7")

--- NUI Callbacks
RegisterNUICallback('startSpawn', function(data, cb)
    print("^2[spz-spawn] NUI callback: startSpawn index " .. tostring(data.index) .. "^7")
    TriggerServerEvent("SPZ:requestSpawn", data.index)
    cb('ok')
end)

--- Debug Command
RegisterCommand("testspawn", function()
    print("^2[spz-spawn] Manual test: triggering showPlayMenu^7")
    TriggerEvent("SPZ:showPlayMenu", {
        name = "Tester",
        rank = "Developer",
        tier = 3,
        gender = 1
    })
end, false)

--- Generic teleport
RegisterNetEvent("SPZ:teleportTo", function(coords, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    if heading then SetEntityHeading(ped, heading) end
end)
