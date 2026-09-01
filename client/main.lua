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
-- Forward declarations: these are defined further down but called by the
-- handlers above them. A local referenced before its declaration resolves to a
-- nil GLOBAL instead, which is how the character-creation reveal thread used to
-- die on its first line every single time.
local CreateCinematicCamera, DestroyCinematicCamera
local PlayMenuIdle
local ApplyPreviewModel

-- ── Loading screen ────────────────────────────────────────────────────────────
--
-- spz-loading owns the screen's lifetime; this file only reports progress and
-- says when it is safe to take it down. It used to call ShutdownLoadingScreen
-- directly from inside two event handlers, which meant an error anywhere before
-- those lines left the screen up forever with no way to recover.

local function LoadStage(key, label)
    if GetResourceState('spz-loading') ~= 'started' then return end
    pcall(function() exports['spz-loading']:Stage(key, label) end)
end

local function KillLoadingScreen()
    if GetResourceState('spz-loading') == 'started' then
        pcall(function() exports['spz-loading']:Finish() end)
        return
    end
    -- spz-loading absent: the screen is not manual-shutdown in that case, but
    -- calling these is harmless and keeps this path honest.
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
end

-- ── Streaming helpers ─────────────────────────────────────────────────────────
--
-- Declared here rather than halfway down the file because the spawn handlers
-- above call it. As a local defined AFTER its callers, the name resolved to a
-- nil global inside them: the character-creation reveal thread errored on its
-- first line every single time, so the cover never lifted, NUI focus was never
-- taken and the creator never appeared. That was the stuck loading screen.

--- Wait until collision is actually streamed around the player (or a cap),
--- instead of a blind fixed sleep. Returns as soon as it is ready.
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

-- ── New-player flow ────────────────────────────────────────────────────────────

RegisterNetEvent("SPZ:openCharacterCreation", function(route)
    if isSpawned or isMenuOpen then return end
    print("^2[spz-spawn] Opening character creation^7")
    -- Raise the branded cover BEFORE killing the loading screen, so the raw
    -- world streaming / ped placement is never visible — feels like one screen.
    -- The kill itself happens further down, once the cover has actually painted
    -- AND the world is streamed; doing it here (as this used to) handed the
    -- player a frame or two of empty grey while the cover was still mounting.
    SendNUIMessage({ type = "showCover" })
    isMenuOpen     = true
    isNewCharacter = true

    -- Place the ped at the fixed preview scene so the UI has a real backdrop
    -- instead of the unstreamed void (black screen).
    local pv = Config.PreviewLocation or Config.SafeZone
    local c  = pv.coords
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, pv.heading, true, true)

    -- VISIBLE, deliberately. This ped used to be hidden for the whole of
    -- character creation, which meant the player picked a model, a name, a
    -- nation and a number for someone they never saw. The racer being built is
    -- the subject of this screen — the UI is docked to one side precisely so
    -- there is something to dock beside.
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetPedDefaultComponentVariation(ped)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    RequestCollisionAtCoord(c.x, c.y, c.z)

    CreateCinematicCamera()
    DisplayHud(false)
    DisplayRadar(false)

    -- Reveal as soon as the area is actually streamed (preloaded in the
    -- background), not after a blind fixed wait.
    CreateThread(function()
        -- Put the ped on the default base model straight away.
        --
        -- Not cosmetic: fivem-appearance refuses to open on anything that is not
        -- a freemode ped, and a freshly connected player is whatever model the
        -- game handed them. The old flow got away with it because it called
        -- SetPlayerModel before opening the editor; this flow only swaps the
        -- model when the player CHANGES gender, so keeping the default meant the
        -- editor was handed a non-freemode ped, bounced it, and fired Done
        -- immediately — the appearance step never appeared.
        ApplyPreviewModel(0)

        Wait(120)                 -- let the cover paint before anything uncovers
        LoadStage('world')
        AwaitCollision(c, 3000)
        KillLoadingScreen()       -- handing off from one full-screen cover to another
        LoadStage('ready')
        DoScreenFadeIn(400)
        SetNuiFocus(true, true)
        -- `suggested` is the player's platform name, offered as a default in the
        -- name field. The server resolves it; the UI may or may not use it.
        SendNUIMessage({ type = "showCharacterCreation", suggested = route and route.suggested or nil })
        Wait(900)                                   -- hold the cover a touch, let the menu mount
        SendNUIMessage({ type = "hideCover" })      -- fade the cover away → reveal
    end)
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

-- ── Boot handshake ────────────────────────────────────────────────────────────
--
-- The client asks; the server answers. That order matters: for the whole time
-- the server used to spend deciding what to show this player and firing it at
-- them, the client had no scripts running and every one of those events was
-- discarded. The only reason returning players ever saw a menu was a poll loop
-- that re-asked every 1.5 seconds, forever, with no failure state — so a real
-- problem looked exactly like a slow one.
--
-- Now: one hello, one route back. Retries are bounded and get slower, and when
-- they run out the player is told what happened instead of being left on a
-- loading screen.

local ROUTE_TIMEOUT_MS = 4000     -- first wait for a reply; grows by 1s per retry
local MAX_ATTEMPTS     = 8        -- ~60s of trying in total, then give up and say so
local routed           = false

local function ShowBootError(reason)
    KillLoadingScreen()
    DoScreenFadeIn(500)
    print(("^1[spz-spawn] Boot failed: %s^7"):format(reason))
    lib.notify({
        title       = 'Could not join',
        description = reason .. ' Try reconnecting.',
        type        = 'error',
        duration    = 15000,
    })
end

CreateThread(function()
    LoadStage('connect')

    -- Let the client's own resources finish starting before announcing. This is
    -- not a guess at how long the server needs — it is how long WE need before
    -- we can act on a reply.
    Wait(500)

    for attempt = 1, MAX_ATTEMPTS do
        if routed then return end

        if attempt > 1 then
            LoadStage('connect', ('CONTACTING SERVER (%d)'):format(attempt))
            print(("^3[spz-spawn] No route yet — handshake attempt %d^7"):format(attempt))
        end

        TriggerServerEvent("SPZ:spawn:hello")

        -- Back off a little each time rather than hammering a server that is
        -- probably just busy.
        local waited = 0
        local budget = ROUTE_TIMEOUT_MS + (attempt - 1) * 1000
        while waited < budget do
            Wait(250)
            waited = waited + 250
            if routed then return end
        end
    end

    ShowBootError('The server did not respond to your client.')
end)

--- The server's answer: what this player should be looking at.
RegisterNetEvent("SPZ:spawn:route", function(route)
    if routed or isSpawned or isMenuOpen then return end
    if not route or not route.mode then return end

    routed = true
    LoadStage('profile')
    print(("^2[spz-spawn] Route: %s^7"):format(route.mode))

    if route.mode == "create" then
        TriggerEvent("SPZ:openCharacterCreation", route)
    elseif route.mode == "menu" then
        TriggerEvent("SPZ:showPlayMenu", route.playerData or {})
    else
        ShowBootError(route.reason or 'The server could not place you in the world.')
    end
end)

--- Re-ask for a route. Used after character creation, when the answer the
--- server would give has changed.
local function RequestRoute()
    routed = false
    TriggerServerEvent("SPZ:spawn:requestMenu")
end

-- ── Cinematic camera ──────────────────────────────────────────────────────────
--
-- A slow orbit with a HANDHELD feel: the operator is breathing, their weight is
-- shifting, and the frame drifts a little because nobody holds a camera
-- perfectly still. It is not shake — shake reads as an explosion. It is a small
-- amount of low-frequency wander, mostly rotational, because that is what
-- actually distinguishes a handheld shot from a tripod.
--
-- The wander is summed sine waves at deliberately incommensurate frequencies
-- rather than random jitter. Random per-frame values look like noise and buzz;
-- sines at frequencies that never line up produce a path that keeps wandering
-- without visibly repeating, and it is smooth by construction, so it can never
-- pop between frames.
--
-- Everything is driven by WALL TIME, not per-frame increments. The old orbit
-- advanced a fixed amount every frame, which meant it ran at whatever speed the
-- player's framerate happened to be: a 144 Hz client orbited nearly two and a
-- half times faster than a 60 Hz one, and a frame hitch jerked the camera.

local camOrbitActive = false

local CAM_ORBIT_DPS  = 2.6    -- degrees per second — full orbit ≈ 2m20s
local CAM_RADIUS     = 3.4
local CAM_FOV        = 45.0

--- Sum of two sines at frequencies chosen not to share a period. Returns
--- roughly -1..1 and never repeats on any timescale the player will sit through.
local function drift(t, f1, f2, phase)
    return (math.sin(t * f1 + phase) * 0.62) + (math.sin(t * f2 + phase * 1.7) * 0.38)
end

CreateCinematicCamera = function()
    if cam then return end
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamFov(cam, CAM_FOV)
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
        local startAngle = (Config.PreviewLocation and Config.PreviewLocation.heading or 0.0) + 210.0
        local t0 = GetGameTimer()

        while camOrbitActive and cam do
            local ped = PlayerPedId()
            local pc  = GetEntityCoords(ped)
            local t   = (GetGameTimer() - t0) / 1000.0

            -- Orbit: behind-right of the ped, drifting counter-clockwise.
            local angle = startAngle + t * CAM_ORBIT_DPS
            local rad   = math.rad(angle)

            -- Handheld translation: centimetres, not metres. Enough to feel
            -- alive, small enough that you would not name it if asked.
            local swayX = drift(t, 0.37, 0.83, 0.0)  * 0.022
            local swayY = drift(t, 0.29, 0.71, 2.1)  * 0.022
            local swayZ = drift(t, 0.23, 0.61, 4.3)  * 0.030

            SetCamCoord(cam,
                pc.x + math.cos(rad) * CAM_RADIUS + swayX,
                pc.y + math.sin(rad) * CAM_RADIUS + swayY,
                pc.z + 0.55 + math.sin(rad * 0.5) * 0.18 + swayZ)

            -- Handheld ROTATION, applied by nudging the point being looked at
            -- rather than by setting the camera's rotation directly. A moving
            -- aim point gives the same sway with none of the matrix work, and it
            -- cannot fight PointCamAtCoord the way an explicit SetCamRot would.
            -- Larger than the positional sway on purpose: at this distance a few
            -- centimetres of aim drift is what the eye actually reads as
            -- "someone is holding this".
            local aimX = drift(t, 0.41, 0.97, 1.3) * 0.05
            local aimY = drift(t, 0.33, 0.89, 3.7) * 0.05
            local aimZ = drift(t, 0.19, 0.53, 5.2) * 0.035

            PointCamAtCoord(cam, pc.x + aimX, pc.y + aimY, pc.z + 0.45 + aimZ)

            -- Breath on the lens: under a degree, slow enough to be felt and not
            -- seen. Real operators drift focal length; a locked FOV reads CG.
            SetCamFov(cam, CAM_FOV + math.sin(t * 0.21) * 0.55)

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

PlayMenuIdle = function()
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
        Wait(120)                 -- let the cover paint before anything uncovers
        LoadStage('world')
        AwaitCollision(pv.coords, 3000)
        KillLoadingScreen()       -- handing off from one full-screen cover to another
        LoadStage('ready')
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

--- Swap the live preview ped to the chosen base model.
---
--- The model IS the choice, so it changes on the ped in front of the player
--- rather than only in a label. Runs during creation only — the ped is frozen
--- at the preview scene with a scripted camera on it, so a model swap here is
--- safe in a way it would not be out in the world.
ApplyPreviewModel = function(gender)
    local modelHash = gender == 1 and 'mp_f_freemode_01' or 'mp_m_freemode_01'

    RequestModel(modelHash)
    local t = 0
    while not HasModelLoaded(modelHash) and t < 300 do Wait(10) t = t + 1 end
    if not HasModelLoaded(modelHash) then return false end

    SetPlayerModel(PlayerId(), modelHash)
    SetModelAsNoLongerNeeded(modelHash)
    Wait(120)

    -- SetPlayerModel hands back a NEW ped handle with uninitialised components.
    -- Without defaults, fivem-appearance's settings builder returns undefined
    -- and its UI throws on "masks"/"hats"; the ped also has to be re-placed,
    -- because the swap drops it at its spawn position.
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, true)

    local pv = Config.PreviewLocation or Config.SafeZone
    SetEntityCoordsNoOffset(ped, pv.coords.x, pv.coords.y, pv.coords.z, false, false, false)
    SetEntityHeading(ped, pv.heading)
    FreezeEntityPosition(ped, true)
    PlayMenuIdle()

    return true
end

RegisterNUICallback('previewGender', function(data, cb)
    cb('ok')
    pendingGender = tonumber(data.gender) or 0
    CreateThread(function() ApplyPreviewModel(pendingGender) end)
end)

--- Hand the screen to the appearance editor, then take it back.
---
--- Appearance now happens BEFORE the racer is named, so the player is naming
--- someone they have already built and can see. That means the editor has to be
--- opened from inside the creation UI and returned from, rather than being
--- launched once by the server after the profile is written.
RegisterNUICallback('openAppearanceStep', function(_, cb)
    cb('ok')

    CreateThread(function()
        -- The editor takes NUI focus and drives its own camera.
        -- PAUSE, not hide: "hide" unmounts the creation UI and takes its state
        -- with it, so the model choice and the step you were on would be lost
        -- while the editor is up.
        SetNuiFocus(false, false)
        SendNUIMessage({ type = "creationPause" })
        DestroyCinematicCamera()

        -- fivem-appearance will refuse a non-freemode ped and quietly report
        -- Done, which looks exactly like "the button did nothing". Guarantee the
        -- model here rather than trusting that something upstream set it.
        local ped = PlayerPedId()
        local model = GetEntityModel(ped)
        if model ~= GetHashKey('mp_m_freemode_01') and model ~= GetHashKey('mp_f_freemode_01') then
            print("^3[spz-spawn] Ped is not freemode before appearance step — applying base model^7")
            ApplyPreviewModel(pendingGender)
            ped = PlayerPedId()
        end

        FreezeEntityPosition(ped, false)
        ClearPedTasksImmediately(ped)   -- drop the menu idle so the editor poses freely

        TriggerEvent("SPZ:openAppearanceCustomization")
    end)
end)

RegisterNUICallback('submitCharacterCreation', function(data, cb)
    pendingGender = tonumber(data.gender) or 0
    TriggerServerEvent("SPZ:characterCreated", data.gender, data.name, data.nation, data.raceNumber)
    cb('ok')
end)

-- ── Character creation response ────────────────────────────────────────────────
-- New-character flow: model → appearance editor → naming → play menu → spawn.

RegisterNetEvent("SPZ:characterCreateCompleted", function(success, message)
    if not success then
        SendNUIMessage({ type = "characterCreationError", message = message or "Unknown error." })
        return
    end

    -- The ped is already built and already wearing what the player chose — the
    -- appearance editor ran before this point, not after it. All that is left is
    -- to stand down the creation scene and ask the server where to go next.
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "hide" })
    DestroyCinematicCamera()

    isMenuOpen     = false
    isNewCharacter = false

    print("^2[spz-spawn] Creation complete — asking for a route^7")
    RequestRoute()
end)

-- fivem-appearance finished (saved or cancelled).
--
-- Two callers, two different meanings:
--
--   During creation, the editor is step two of building the racer, so this hands
--   the screen back to the creation UI on its naming step. The profile does not
--   exist yet — nothing is asked of the server here.
--
--   Outside creation (/appearance in freeroam) the player is already in the
--   world, and there is nothing to hand back to.
AddEventHandler("SPZ:appearanceCustomizationDone", function()
    if not isNewCharacter then return end

    print("^2[spz-spawn] Appearance step done — returning to naming^7")

    CreateThread(function()
        -- Rebuild the preview scene the editor took over: back on the mark,
        -- posed, cinematic camera up, creation UI in front of it again.
        local pv  = Config.PreviewLocation or Config.SafeZone
        local ped = PlayerPedId()

        SetEntityCoordsNoOffset(ped, pv.coords.x, pv.coords.y, pv.coords.z, false, false, false)
        SetEntityHeading(ped, pv.heading)
        SetEntityVisible(ped, true, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        PlayMenuIdle()

        CreateCinematicCamera()
        DisplayHud(false)
        DisplayRadar(false)

        Wait(150)
        SetNuiFocus(true, true)
        SendNUIMessage({ type = "appearanceStepDone" })
    end)
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
