-- client/main.lua

local isSpawned  = false
local isMenuOpen = false
local cam        = nil
local isNewCharacter = false

-- forward declarations (defined in the camera section below)
local CreateCinematicCamera, DestroyCinematicCamera

-- ── Loading screen kill ───────────────────────────────────────────────────────

local loadingKilled = false
local function KillLoadingScreen()
    if loadingKilled then return end
    loadingKilled = true
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end

-- Hard failsafe: if nothing calls KillLoadingScreen in 20 s, do it anyway.
CreateThread(function()
    Wait(20000)
    if not loadingKilled then
        print("^3[spz-spawn] WARNING: Loading screen timeout — force-killing after 20s^7")
        KillLoadingScreen()
        -- If identity still hasn't responded, keep polling for play menu
    end
end)

-- ── New-player flow ────────────────────────────────────────────────────────────

local function HandleFirstTimeSetup()
    if LocalPlayer.state.firstTime and not isSpawned and not isMenuOpen then
        TriggerEvent("SPZ:openCharacterCreation")
    end
end

RegisterNetEvent("SPZ:openCharacterCreation", function()
    if isSpawned or isMenuOpen then return end
    print("^2[spz-spawn] Opening character creation^7")
    KillLoadingScreen()
    isMenuOpen     = true
    isNewCharacter = true

    -- Place the (invisible) ped at the fixed preview scene so the UI has a
    -- real backdrop instead of the unstreamed void (black screen).
    local pv = Config.PreviewLocation or Config.SafeZone
    local c  = pv.coords
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, pv.heading, true, true)

    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(c.x, c.y, c.z)

    CreateCinematicCamera()
    DisplayHud(false)
    DisplayRadar(false)

    -- Give the world a moment to stream in before revealing
    CreateThread(function()
        Wait(600)
        DoScreenFadeIn(500)
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "showCharacterCreation" })
    end)
end)

AddStateBagChangeHandler("firstTime", nil, function(bagName, key, value)
    local targetSource = tonumber(bagName:match("player:(%d+)"))
    if targetSource ~= GetPlayerServerId(PlayerId()) then return end
    if value then HandleFirstTimeSetup() end
end)

-- ── Spawnmanager suppression ──────────────────────────────────────────────────

local function DisableSpawnManager()
    pcall(function()
        exports.spawnmanager:setAutoSpawn(false)
        exports.spawnmanager:forceGameState('MANUAL')
    end)
end

DisableSpawnManager()
AddEventHandler('onClientResourceStart', function(r) if GetCurrentResourceName() == r then DisableSpawnManager() end end)
AddEventHandler("onClientMapStart", DisableSpawnManager)
CreateThread(function() for i = 1,50 do DisableSpawnManager() Wait(100) end end)

-- ── Play menu request ─────────────────────────────────────────────────────────

local function RequestPlayMenu()
    if isSpawned or isMenuOpen then return end
    if LocalPlayer.state.firstTime then return end
    print("^2[spz-spawn] Requesting play menu^7")
    TriggerServerEvent("SPZ:requestPlayMenu")
end

-- Triggered by spz-identity when profile is fully loaded & synced
RegisterNetEvent("SPZ:identityReady", function()
    print("^2[spz-spawn] Identity ready — requesting play menu^7")
    Wait(200) -- one frame buffer
    RequestPlayMenu()
end)

-- Polling fallback (in case identityReady was missed)
CreateThread(function()
    Wait(3000) -- shorter initial wait
    HandleFirstTimeSetup()
    while not isSpawned and not isMenuOpen do
        RequestPlayMenu()
        Wait(3000)
    end
end)

-- ── Cinematic camera ──────────────────────────────────────────────────────────

-- Slow orbit around the ped with gentle height drift and shallow
-- depth-of-field — character-select feel instead of a static shot.
local camOrbitActive = false

CreateCinematicCamera = function()
    if cam then return end
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamFov(cam, 45.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, true)

    -- Subtle DOF: ped sharp, background only lightly softened
    SetCamUseShallowDofMode(cam, true)
    SetCamNearDof(cam, 1.5)
    SetCamFarDof(cam, 10.0)
    SetCamDofStrength(cam, 0.3)

    -- Golden-hour backdrop while in the menus
    NetworkOverrideClockTime(18, 30, 0)

    camOrbitActive = true
    CreateThread(function()
        -- Start behind-right of the ped, drift slowly counter-clockwise
        local angle  = (Config.PreviewLocation and Config.PreviewLocation.heading or 0.0) + 210.0
        local radius = 3.4
        while camOrbitActive and cam do
            local ped = PlayerPedId()
            local pc  = GetEntityCoords(ped)

            angle = angle + 0.05   -- ~3°/s at 60 fps → full orbit ≈ 2 min
            local rad = math.rad(angle)
            SetCamCoord(cam,
                pc.x + math.cos(rad) * radius,
                pc.y + math.sin(rad) * radius,
                pc.z + 0.55 + math.sin(rad * 0.5) * 0.18)   -- gentle rise/fall
            PointCamAtCoord(cam, pc.x, pc.y, pc.z + 0.45)

            SetUseHiDof()   -- must be asserted every frame for DOF to render
            Wait(0)
        end
    end)
end

DestroyCinematicCamera = function()
    camOrbitActive = false
    if cam then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
end

-- Relaxed idle pose while showcased in the menu
local IDLE_DICT = "anim@heists@heist_corona@team_idles@male_a"
local IDLE_ANIM = "idle"

local function PlayMenuIdle()
    CreateThread(function()
        local ped = PlayerPedId()
        RequestAnimDict(IDLE_DICT)
        local tries = 0
        while not HasAnimDictLoaded(IDLE_DICT) and tries < 100 do
            Wait(50)
            tries = tries + 1
        end
        if HasAnimDictLoaded(IDLE_DICT) then
            -- flag 1 = loop
            TaskPlayAnim(ped, IDLE_DICT, IDLE_ANIM, 2.0, 2.0, -1, 1, 0.0, false, false, false)
        else
            TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
        end
    end)
end

-- ── Physical spawn ────────────────────────────────────────────────────────────

RegisterNetEvent("SPZ:spawnPlayerTarget", function(data)
    -- gender: 0 = male (mp_m_freemode_01), 1 = female (mp_f_freemode_01)
    local modelHash = data.gender == 1 and `mp_f_freemode_01` or `mp_m_freemode_01`

    DoScreenFadeOut(500)
    Wait(500)

    SendNUIMessage({ type = 'hide' })
    SetNuiFocus(false, false)
    isMenuOpen = false
    DestroyCinematicCamera()
    FreezeEntityPosition(PlayerPedId(), false)
    DisplayHud(true)
    DisplayRadar(true)

    -- Set model
    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) do
        Wait(0)
        timeout = timeout + 1
        if timeout > 300 then break end -- 5s hard timeout
    end
    SetPlayerModel(PlayerId(), modelHash)
    SetModelAsNoLongerNeeded(modelHash)

    -- Teleport / resurrect
    local coords  = data.coords  or Config.SafeZone.coords
    local heading = data.heading or Config.SafeZone.heading
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, true)

    -- Back to server-synced time (menu forced golden hour)
    pcall(function() NetworkClearClockTimeOverride() end)

    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)   -- drop the menu idle pose
    -- A freshly swapped freemode model has uninitialised component state;
    -- without defaults fivem-appearance's settings builder returns undefined and its
    -- UI crashes ("reading 'masks'/'hats'").
    SetPedDefaultComponentVariation(ped)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    ClearPedBloodDamage(ped)
    RemoveAllPedWeapons(ped, true)

    isSpawned = true

    -- Wait for ped model to fully apply before triggering outfit
    -- (SetPlayerModel resets appearance; applyOutfit must run after)
    Wait(300)
    TriggerEvent("SPZ:applyOutfit")

    -- Guarantee full control after the outfit apply — an appearance model swap
    -- can otherwise leave the player ghosted / frozen.
    CreateThread(function()
        Wait(800)
        local p = PlayerPedId()
        SetLocalPlayerAsGhost(false)
        SetEntityCollision(p, true, true)
        FreezeEntityPosition(p, false)
        SetPlayerControl(PlayerId(), true, 0)
    end)

    DoScreenFadeIn(1000)
end)

-- ── Show play menu ────────────────────────────────────────────────────────────

RegisterNetEvent("SPZ:showPlayMenu", function(playerData)
    if isSpawned or isMenuOpen then return end

    print("^2[spz-spawn] Showing play menu^7")
    isMenuOpen = true

    KillLoadingScreen()

    -- Fixed showcase scene: always preview from the same spot instead of
    -- wherever the ped happens to be.
    local pv = Config.PreviewLocation or Config.SafeZone
    NetworkResurrectLocalPlayer(pv.coords.x, pv.coords.y, pv.coords.z, pv.heading, true, true)
    RequestCollisionAtCoord(pv.coords.x, pv.coords.y, pv.coords.z)

    local ped = PlayerPedId()
    SetEntityCoords(ped, pv.coords.x, pv.coords.y, pv.coords.z, false, false, false, true)
    SetEntityHeading(ped, pv.heading)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, true)
    SetEntityInvincible(ped, true)
    DisplayHud(false)
    DisplayRadar(false)

    PlayMenuIdle()
    CreateCinematicCamera()

    -- Let the area stream in before revealing
    CreateThread(function()
        Wait(400)
        DoScreenFadeIn(500)
    end)

    -- Enrich with statebag data
    local state = LocalPlayer.state
    playerData.avatar       = state.avatarUrl    or "https://i.imgur.com/8NzA8m8.png"
    playerData.crew         = state.crewTag      or ""
    playerData.licenseClass = state.rank         or "C-5"
    playerData.stateText    = state.state        or "IDLE"

    SendNUIMessage({ type = 'show', playerData = playerData, spawns = Config.Spawns })
    SetNuiFocus(true, true)
end)

-- ── NUI callbacks ─────────────────────────────────────────────────────────────

RegisterNUICallback('startSpawn', function(data, cb)
    TriggerServerEvent("SPZ:requestSpawn", data.index)
    cb('ok')
end)

local pendingGender = 0

RegisterNUICallback('submitCharacterCreation', function(data, cb)
    pendingGender = tonumber(data.gender) or 0
    TriggerServerEvent("SPZ:characterCreated", data.gender, data.name, data.nation, data.raceNumber)
    cb('ok')
end)

-- ── Character creation response ────────────────────────────────────────────────
-- New-character flow: creation UI → fivem-appearance dress-up → play menu → spawn.

RegisterNetEvent("SPZ:characterCreateCompleted", function(success, message)
    if not success then
        SendNUIMessage({ type = "characterCreationError", message = message or "Unknown error." })
        return
    end

    SetNuiFocus(false, false)
    SendNUIMessage({ type = "hide" })
    DestroyCinematicCamera()
    -- Keep isMenuOpen = true: blocks the play-menu poll + the server's
    -- characterReady-triggered showPlayMenu while fivem-appearance is on screen.

    CreateThread(function()
        -- Swap to the chosen gender's freemode model at the preview scene
        local modelHash = pendingGender == 1 and `mp_f_freemode_01` or `mp_m_freemode_01`
        RequestModel(modelHash)
        local t = 0
        while not HasModelLoaded(modelHash) and t < 300 do Wait(10) t = t + 1 end
        SetPlayerModel(PlayerId(), modelHash)
        SetModelAsNoLongerNeeded(modelHash)
        Wait(150)

        local ped = PlayerPedId()
        SetPedDefaultComponentVariation(ped)   -- fivem-appearance needs initialised components
        SetEntityVisible(ped, true, false)
        FreezeEntityPosition(ped, false)
        Wait(250)

        print("^2[spz-spawn] Creation complete — opening appearance customization^7")
        TriggerEvent("SPZ:openAppearanceCustomization")
    end)
end)

-- fivem-appearance finished (saved or cancelled) → now show the play menu
AddEventHandler("SPZ:appearanceCustomizationDone", function()
    print("^2[spz-spawn] Customization done — requesting play menu^7")
    isMenuOpen = false
    TriggerServerEvent("SPZ:requestPlayMenu")
end)

-- ── Utilities ─────────────────────────────────────────────────────────────────

RegisterNetEvent("SPZ:teleportTo", function(coords, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
    if heading then SetEntityHeading(ped, heading) end
end)

RegisterCommand("testspawn", function()
    isSpawned = false
    isMenuOpen = false
    TriggerEvent("SPZ:showPlayMenu", { name = "Tester", rank = "Developer", tier = 3, gender = 0 })
end, false)

RegisterCommand("testcreation", function()
    isSpawned = false
    isMenuOpen = false
    TriggerEvent("SPZ:openCharacterCreation")
end, false)

print("^2[spz-spawn] Client initialized^7")
