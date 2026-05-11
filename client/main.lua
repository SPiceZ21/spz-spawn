-- client/main.lua

local isSpawned = false
local isMenuOpen = false
local cam = nil

--- Handle new players (first-time setup)
local function HandleFirstTimeSetup()
    if LocalPlayer.state.firstTime and not isSpawned and not isMenuOpen then
        print("^2[spz-spawn] New player detected. Opening character creation...^7")
        
        -- Shutdown loading screen so UI is visible
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
        DoScreenFadeIn(500)

        -- Trigger the character creation UI
        TriggerEvent("SPZ:openCharacterCreation")
    end
end

-- Listen for the firstTime state bag to handle new players
AddStateBagChangeHandler("firstTime", ("player:%s"):format(GetPlayerServerId(PlayerId())), function(bagName, key, value)
    if value then HandleFirstTimeSetup() end
end)

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
    Wait(2000)
    
    -- Check immediately if we are a new player
    HandleFirstTimeSetup()
    
    -- Keep requesting until we either spawn or the menu opens
    while not isSpawned and not isMenuOpen do
        if not LocalPlayer.state.firstTime then
            print("^2[spz-spawn] Requesting play menu from server...^7")
            TriggerServerEvent("SPZ:requestPlayMenu")
        end
        Wait(5000) -- Retry every 5 seconds if still not spawned/menu open
    end
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
    isMenuOpen = false
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

    -- State synchronization (now handled by server statebags)
    isSpawned = true

    -- Trigger external systems (appearance, etc.)
    TriggerEvent("SPZ:applyOutfit")
    
    DoScreenFadeIn(1000)
end)

--- Shutdown loading screen after identity is ready and play menu is shown.
RegisterNetEvent("SPZ:showPlayMenu", function(playerData)
    if isSpawned or isMenuOpen then return end
    
    print("^2[spz-spawn] DEBUG: Client received showPlayMenu^7")
    isMenuOpen = true
    
    -- Force kill all loading screens
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    
    -- Ensure screen is clear
    DoScreenFadeIn(500)
    
    -- Activate cinematic mode
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true)
    DisplayHud(false)
    DisplayRadar(false)
    
    CreateCinematicCamera()
    
    -- Get info from statebags
    local state = Player(PlayerId()).state
    playerData.avatar       = state.avatarUrl or "https://i.imgur.com/8NzA8m8.png"
    playerData.crew         = state.crewTag or ""
    playerData.licenseClass = state.rank or "C-5"
    playerData.stateText    = state.state or "IDLE"

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
