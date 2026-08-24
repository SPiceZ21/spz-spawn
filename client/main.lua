-- client/main.lua

-- Base theme (server.cfg spz_theme_* convars via spz-core).
local function pushSpawnTheme(theme)
    if theme and next(theme) then
        SendNUIMessage({ type = 'theme', theme = theme })
    end
end
CreateThread(function()
    local ok, theme = pcall(function() return exports['spz-core']:GetTheme() end)
    if ok then pushSpawnTheme(theme) end
end)
AddEventHandler('SPZ:themeUpdated', function(theme) pushSpawnTheme(theme) end)

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
    -- Raise the branded cover BEFORE killing the loading screen, so the raw
    -- world streaming / ped placement is never visible — feels like one screen.
    SendNUIMessage({ type = "showCover" })
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

    -- Reveal as soon as the area is actually streamed (preloaded in the
    -- background), not after a blind fixed wait.
    CreateThread(function()
        AwaitCollision(c, 1500)
        DoScreenFadeIn(400)
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "showCharacterCreation" })
        Wait(900)                                   -- hold the cover a touch, let the menu mount
        SendNUIMessage({ type = "hideCover" })      -- fade the cover away → reveal
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
        -- no-op autospawn callback: even if something flips autospawn on, it can't
        -- drop the ped at a random spawnpoint. spz-spawn is the only spawner.
        exports.spawnmanager:setAutoSpawnCallback(function() end)
    end)
end

DisableSpawnManager()
AddEventHandler('onClientResourceStart', function(r) if GetCurrentResourceName() == r then DisableSpawnManager() end end)
AddEventHandler("onClientMapStart", DisableSpawnManager)
CreateThread(function() for i = 1,50 do DisableSpawnManager() Wait(100) end end)

-- ── Showcase preloader ────────────────────────────────────────────────────────
-- The showcase location is FIXED (Config.PreviewLocation), so stream it in the
-- background WHILE the loading screen / identity load is still going, instead of
-- discovering it and blocking when the menu opens. SetFocusPosAndVel forces the
-- engine to stream that area even though the player ped isn't there yet. Also
-- preloads both freemode peds + the idle anim so nothing loads lazily at reveal.

local PREVIEW_IDLE_DICT = "anim@heists@heist_corona@team_idles@male_a"
local previewReady = false

-- Wait until collision is actually streamed around an entity (or a cap), instead
-- of a blind fixed sleep. Returns as soon as it's ready → usually much faster.
local function AwaitCollision(c, capMs)
    local ped = PlayerPedId()
    local deadline = GetGameTimer() + (capMs or 1500)
    while GetGameTimer() < deadline do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        if HasCollisionLoadedAroundEntity(ped) then return true end
        Wait(0)
    end
    return false
end

CreateThread(function()
    local pv = Config.PreviewLocation or Config.SafeZone
    if not pv or not pv.coords then return end
    local c = pv.coords

    RequestModel('mp_m_freemode_01')
    RequestModel('mp_f_freemode_01')
    RequestAnimDict(PREVIEW_IDLE_DICT)

    -- Hold streaming focus on the showcase spot until the player actually spawns
    -- into the world (their ped presence then holds it).
    while not isSpawned do
        SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(c.x, c.y, c.z)
        if HasAnimDictLoaded(PREVIEW_IDLE_DICT) then previewReady = true end
        Wait(200)
    end
end)

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
    Wait(1000) -- shorter initial wait; identityReady is the fast path
    HandleFirstTimeSetup()
    while not isSpawned and not isMenuOpen do
        RequestPlayMenu()
        Wait(1500)
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

    -- Time is owned by spz-core (GlobalState envTime, re-asserted every frame).
    -- Overriding it here made the menu flicker between the two clocks — set
    -- Config.Environment.hour in spz-core to change the backdrop instead.

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
    local modelHash = data.gender == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'

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

    -- ── HOLD the ped in place while the map streams in underneath ─────────────
    -- Without this the player is dropped at the coords before the terrain
    -- collision has loaded and falls through the world. Freeze + pin the exact
    -- position, force-stream collision there, and don't release / fade in until
    -- the ground is actually loaded.
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)

    ClearPedTasksImmediately(ped)   -- drop the menu idle pose
    -- A freshly swapped freemode model has uninitialised component state;
    -- without defaults fivem-appearance's settings builder returns undefined and its
    -- UI crashes ("reading 'masks'/'hats'").
    SetPedDefaultComponentVariation(ped)
    SetEntityVisible(ped, true, false)
    ClearPedBloodDamage(ped)
    RemoveAllPedWeapons(ped, true)

    isSpawned = true

    -- Force-stream the world under the spawn. The reliable signal that the
    -- terrain is actually loaded is that GetGroundZ SUCCEEDS — HasCollisionLoaded
    -- can report true too early on a frozen ped, leaving us at a raw config Z
    -- that's embedded in / under the mesh. So we spin until the ground is
    -- queryable (cast from ABOVE the surface), pinning the ped each iteration.
    local x, y, z = coords.x, coords.y, coords.z
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)

    local gok, groundZ = false, z
    local tries = 0
    while tries < 300 do   -- up to ~6s
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        FreezeEntityPosition(ped, true)
        gok, groundZ = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
        if gok and HasCollisionLoadedAroundEntity(ped) then break end
        Wait(20)
        tries = tries + 1
    end
    ClearFocus()

    -- Land the ped exactly on the mesh surface (or, if the ground never
    -- resolved, keep the config Z as a fallback).
    if gok then z = groundZ + 1.0 end
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)
    print(("^3[spz-spawn] collision tries=%d gok=%s groundZ=%.2f finalZ=%.2f^7")
        :format(tries, tostring(gok), groundZ, z))

    Wait(150)
    TriggerEvent("SPZ:applyOutfit")

    CreateThread(function()
        Wait(600)
        local p = PlayerPedId()
        SetLocalPlayerAsGhost(false)
        SetEntityCollision(p, true, true)
        FreezeEntityPosition(p, false)     -- unfreeze only now that land exists
        SetEntityInvincible(p, false)
        SetPlayerControl(PlayerId(), true, 0)

        -- Safety net: if something teleports the ped right after spawn (e.g. an
        -- appearance model swap dropping it at the origin), snap it back to the
        -- spawn point. A real walk can't cover >25m in this window.
        for _ = 1, 10 do
            Wait(150)
            local cur = GetEntityCoords(PlayerPedId())
            if #(vector3(cur.x, cur.y, cur.z) - vector3(x, y, z)) > 25.0 then
                local pp = PlayerPedId()
                SetEntityCoordsNoOffset(pp, x, y, z, false, false, false)
                SetEntityHeading(pp, heading)
            end
        end
    end)

    DoScreenFadeIn(1000)
end)

-- ── Show play menu ────────────────────────────────────────────────────────────

RegisterNetEvent("SPZ:showPlayMenu", function(playerData)
    if isSpawned or isMenuOpen then return end

    print("^2[spz-spawn] Showing play menu^7")
    isMenuOpen = true

    SendNUIMessage({ type = "showCover" })   -- cover the streaming behind the menu
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

    -- Enrich with statebag data
    local state = LocalPlayer.state
    playerData.avatar       = state.avatarUrl    or "https://i.imgur.com/8NzA8m8.png"
    playerData.crew         = state.crewTag      or ""
    playerData.licenseClass = state.rank         or "C-5"
    playerData.stateText    = state.state        or "IDLE"

    SendNUIMessage({ type = 'show', playerData = playerData, spawns = Config.Spawns })
    SetNuiFocus(true, true)

    -- Reveal once the (preloaded) area is streamed and the menu has mounted —
    -- the cover fades away last, so nothing raw is ever seen.
    CreateThread(function()
        AwaitCollision(pv.coords, 1500)
        DoScreenFadeIn(400)
        Wait(900)
        SendNUIMessage({ type = "hideCover" })
    end)
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
        local modelHash = pendingGender == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'
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
