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

    -- Framed to the RIGHT: the creation rail owns the left of the screen.
    CreateCinematicCamera(CAM_COMPOSE_CREATION)
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

--- SHOT LIST, not an orbit.
---
--- The old camera was one constant-speed circle at a fixed radius, height and
--- FOV. Nothing about the framing ever changed, so after ten seconds the eye had
--- seen the whole shot and the rest was just waiting — and a constant angular
--- rate is the single most recognisable "script camera" tell there is.
---
--- This is a route through five framings instead: a slow low push-in, a rise to
--- a close three-quarter, a wide crane, a low pull-out. Radius, height, FOV and
--- the speed of the arc all change per leg, so the shot keeps giving the player
--- something new to look at.
---
--- Keyframes are POLAR and RELATIVE to the ped's heading (angle 0 = directly in
--- front of the ped). Polar because interpolating positions in a straight line
--- between two points on opposite sides of the ped would fly the camera THROUGH
--- them; an arc cannot. Relative to heading so the framing is the same shot no
--- matter which way the preview scene faces.
---
--- `ang` only ever increases: the loop closes by ending 360° on from where it
--- started, at the same radius/height/FOV, so the last leg runs into the first
--- with no cut and no visible seam.
local CAM_SHOTS = {
    -- ang (deg, ped-relative), rad (m), h (m above ped root), fov, look (aim height), dur (s to NEXT keyframe), ease
    { ang = 200.0, rad = 3.8, h = 0.30, fov = 47.0, look = 0.50, dur = 9.0,  ease = 0.75 }, -- low, wide, behind-left
    { ang = 250.0, rad = 2.4, h = 0.95, fov = 40.0, look = 0.68, dur = 7.5,  ease = 0.55 }, -- push in and rise
    { ang = 318.0, rad = 1.9, h = 1.20, fov = 35.0, look = 0.78, dur = 8.5,  ease = 0.70 }, -- close three-quarter, near the face
    { ang = 392.0, rad = 3.4, h = 0.45, fov = 46.0, look = 0.42, dur = 10.0, ease = 0.60 }, -- drop and pull out, front-right
    { ang = 470.0, rad = 4.6, h = 1.65, fov = 52.0, look = 0.55, dur = 11.0, ease = 0.65 }, -- crane up and away
    { ang = 560.0, rad = 3.8, h = 0.30, fov = 47.0, look = 0.50 },                          -- == keyframe 1, +360° → seamless loop
}

-- ── Framing ───────────────────────────────────────────────────────────────────
--
-- Where the ped sits ACROSS the frame, as a fraction of the half-width: 0 is
-- dead centre, +1 would be the right edge. Positive = right of screen.
--
-- Character creation docks its rail down the left, so a centred ped stands
-- behind the form the player is filling in — they pick a model, a nation and a
-- number for someone half-hidden by a panel. The play menu keeps 0.0: its UI is
-- anchored to the frame corners with the middle deliberately clear, so centre is
-- the right composition there.
--
-- It is the AIM point that moves, not the camera. PointCamAtCoord recentres
-- whatever it is given, so aiming a little to the ped's left is what pushes the
-- ped to the right; moving the camera sideways would only orbit it, because the
-- aim would follow it round and the framing would come out identical.
local camComposeX = 0.0
local CAM_COMPOSE_CREATION = 0.42   -- ped centred in the space beside the rail

--- Sum of two sines at frequencies chosen not to share a period. Returns
--- roughly -1..1 and never repeats on any timescale the player will sit through.
local function drift(t, f1, f2, phase)
    return (math.sin(t * f1 + phase) * 0.62) + (math.sin(t * f2 + phase * 1.7) * 0.38)
end

--- Blend of linear and smoothstep. Pure smoothstep stops dead at every keyframe,
--- which reads as six separate shots stapled together; pure linear corners at
--- them. `k` is how much breath a leg gets: 0 = constant speed, 1 = full ease.
local function ease(t, k)
    local s = t * t * (3.0 - 2.0 * t)
    return t + (s - t) * (k or 0.6)
end

--- Where the camera is at `t` seconds into the (looping) shot list.
--- Returns angle, radius, height, fov, aim height.
local function sampleShots(t)
    local total = 0.0
    for i = 1, #CAM_SHOTS - 1 do total = total + CAM_SHOTS[i].dur end

    t = t % total
    for i = 1, #CAM_SHOTS - 1 do
        local a, b = CAM_SHOTS[i], CAM_SHOTS[i + 1]
        if t < a.dur then
            local f = ease(t / a.dur, a.ease)
            return a.ang  + (b.ang  - a.ang)  * f,
                   a.rad  + (b.rad  - a.rad)  * f,
                   a.h    + (b.h    - a.h)    * f,
                   a.fov  + (b.fov  - a.fov)  * f,
                   a.look + (b.look - a.look) * f
        end
        t = t - a.dur
    end

    local last = CAM_SHOTS[#CAM_SHOTS]
    return last.ang, last.rad, last.h, last.fov, last.look
end

--- `composeX` is the framing offset described above — omitted means centred.
CreateCinematicCamera = function(composeX)
    camComposeX = tonumber(composeX) or 0.0
    if cam then return end
    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamFov(cam, CAM_SHOTS[1].fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 1000, true, true)

    -- DOF is now tied to the shot: the close framings get a shallower, nearer
    -- focus plane than the wide ones, which is the actual difference between a
    -- portrait lens and an establishing shot.
    SetCamUseShallowDofMode(cam, true)

    -- Time is owned by spz-core (GlobalState envTime, re-asserted every frame).
    -- Overriding it here made the menu flicker between the two clocks — set
    -- Config.Environment.hour in spz-core to change the backdrop instead.

    camOrbitActive = true
    CreateThread(function()
        -- Everything is driven by WALL TIME, not per-frame increments. A camera
        -- advanced a fixed amount every frame runs at whatever speed the
        -- player's framerate happens to be — a 144 Hz client moved nearly two
        -- and a half times faster than a 60 Hz one, and a frame hitch jerked it.
        local t0 = GetGameTimer()

        while camOrbitActive and cam do
            local ped = PlayerPedId()
            local pc  = GetEntityCoords(ped)
            local t   = (GetGameTimer() - t0) / 1000.0

            local ang, radius, height, fov, look = sampleShots(t)

            -- Ped-relative angle → world. GTA headings run clockwise from north,
            -- so the ped's front is -sin/+cos, and the shot angle is added on top.
            local rad = math.rad(GetEntityHeading(ped) + ang)

            -- Handheld sway: centimetres, not metres. Enough to feel alive,
            -- small enough that you would not name it if asked. Scaled DOWN as
            -- the camera closes in — the same absolute wobble that reads as an
            -- operator breathing at four metres reads as a nervous twitch at two.
            local near  = math.min(1.0, radius / 3.8)
            local swayX = drift(t, 0.37, 0.83, 0.0) * 0.022 * near
            local swayY = drift(t, 0.29, 0.71, 2.1) * 0.022 * near
            local swayZ = drift(t, 0.23, 0.61, 4.3) * 0.030 * near

            SetCamCoord(cam,
                pc.x - math.sin(rad) * radius + swayX,
                pc.y + math.cos(rad) * radius + swayY,
                pc.z + height + swayZ)

            -- Handheld ROTATION, applied by nudging the point being looked at
            -- rather than by setting the camera's rotation directly. A moving
            -- aim point gives the same sway with none of the matrix work, and it
            -- cannot fight PointCamAtCoord the way an explicit SetCamRot would.
            local aimX = drift(t, 0.41, 0.97, 1.3) * 0.045 * near
            local aimY = drift(t, 0.33, 0.89, 3.7) * 0.045 * near
            local aimZ = drift(t, 0.19, 0.53, 5.2) * 0.030 * near

            -- Framing offset: slide the aim point sideways along the camera's
            -- own right axis so the ped lands off-centre in the frame.
            --
            -- Scaled by radius AND by the horizontal half-angle, so the ped
            -- holds the same position ON SCREEN through every leg of the shot
            -- list. A fixed metre offset would drift across the frame as the
            -- camera pushed in and the lens went long — worst exactly on the
            -- close three-quarter, where being half behind the rail is most
            -- obvious.
            local offX, offY = 0.0, 0.0
            if camComposeX ~= 0.0 then
                -- View direction is (sin, -cos); its right axis is (dy, -dx),
                -- so aiming AGAINST that axis moves the subject to the right.
                local tanHalf = math.tan(math.rad(fov * 0.5)) * GetAspectRatio(false)
                local shift   = camComposeX * radius * tanHalf
                offX = math.cos(rad) * shift
                offY = math.sin(rad) * shift
            end

            PointCamAtCoord(cam, pc.x + aimX + offX, pc.y + aimY + offY, pc.z + look + aimZ)

            -- Breath on the lens on top of the shot's own focal length: under a
            -- degree, slow enough to be felt and not seen. A locked FOV reads CG.
            SetCamFov(cam, fov + math.sin(t * 0.21) * 0.55)

            -- Focus rides the subject distance, so the ped stays sharp on every
            -- leg while the background softens more the closer the camera gets.
            SetCamNearDof(cam, math.max(0.4, radius - 1.1))
            SetCamFarDof(cam, radius + 4.0)
            SetCamDofStrength(cam, 0.28 + (1.0 - near) * 0.22)

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

    -- ── Show the player THEIR racer, not the game's default ───────────────────
    --
    -- Nothing here used to set a model, so the menu showed whatever ped the game
    -- handed the client on connect — Michael (player_zero). The player's own ped
    -- only appeared after START, because SPZ:spawnPlayerTarget is where the model
    -- swap and the outfit apply actually lived. So the menu previewed a
    -- character nobody had made, for a screen whose entire subject is the racer.
    --
    -- Do the same two steps the spawn does, but in the preview scene and without
    -- letting go of the ped: base model from the profile's gender, then the saved
    -- personal appearance on top.
    CreateThread(function()
        -- Only swap when the ped is not already the right base model: a swap
        -- resets every component to defaults, so doing it needlessly would strip
        -- the look off a ped that already had it (returning from creation).
        --
        -- RETRIED, and the result is checked. The swap can genuinely fail at
        -- boot — the model is not resident yet — and a single unchecked attempt
        -- is what left the menu showing Michael. Each attempt waits for the
        -- model itself, so this is not a busy spin; it is "keep asking until the
        -- streamer has it", with an end.
        -- Normalised, because the value comes out of a database column and
        -- `"1" == 1` is false in Lua: an unnormalised string would silently
        -- preview every player as male.
        local raw       = playerData.gender
        local gender    = (raw == 1 or raw == '1' or raw == 'female' or raw == 'f') and 1 or 0
        local want      = (gender == 1) and 'mp_f_freemode_01' or 'mp_m_freemode_01'
        local wantHash  = GetHashKey(want)
        local swapped   = GetEntityModel(PlayerPedId()) == wantHash

        for _ = 1, 5 do
            if swapped or not isMenuOpen then break end
            swapped = ApplyPreviewModel(gender) and GetEntityModel(PlayerPedId()) == wantHash
            if not swapped then Wait(1000) end
        end

        if not isMenuOpen then return end

        if not swapped then
            -- Say so rather than quietly previewing the wrong person. The outfit
            -- apply below still runs: on a non-freemode ped spz-appearance falls
            -- through to setPlayerAppearance, which swaps the model itself, so
            -- this is a second chance rather than a dead end.
            print("^1[spz-spawn] Preview model swap failed — menu may show the default ped^7")
        end

        -- Re-fetch: the model swap above hands back a NEW ped handle.
        local pped = PlayerPedId()
        SetEntityVisible(pped, true, false)

        TriggerEvent("SPZ:applyOutfit")

        -- spz-appearance's full-appearance path unfreezes the ped and hands
        -- control back ~300ms after applying (it is written for a player who has
        -- just spawned into the world). In the menu that would drop the ped out
        -- of its pose and let it walk out of frame.
        --
        -- The apply is a server round-trip, so there is no single moment to
        -- re-pin AFTER: hold the pose for a few seconds instead and re-assert it
        -- whenever it actually drifts. Cheap, and it cannot miss the unfreeze.
        local healed = false
        for _ = 1, 20 do
            Wait(150)
            if not isMenuOpen then return end
            local p = PlayerPedId()

            -- Late heal: if the ped is STILL not the right base model — the
            -- outfit apply's own fallback did not fire, or it fired before the
            -- model was resident — take one more run at it now that several
            -- seconds of streaming have passed. Cheap to check, and it is the
            -- difference between a menu that eventually shows your racer and one
            -- that shows Michael until you press START.
            -- Once only: each attempt already waits up to ten seconds for the
            -- model, so retrying it on every tick of this loop would stack those
            -- waits instead of holding the pose.
            if not healed and GetEntityModel(p) ~= wantHash then
                healed = true
                if ApplyPreviewModel(gender) then
                    TriggerEvent("SPZ:applyOutfit")
                end
                p = PlayerPedId()
            end

            if not IsEntityPositionFrozen(p) then
                SetEntityCoordsNoOffset(p, pv.coords.x, pv.coords.y, pv.coords.z, false, false, false)
                SetEntityHeading(p, pv.heading)
                FreezeEntityPosition(p, true)
                SetEntityInvincible(p, true)
                PlayMenuIdle()
            end
        end
    end)

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

    -- Re-request every iteration, and wait ten seconds rather than three.
    --
    -- This is where "the menu shows Michael" came from. A single RequestModel
    -- followed by a 3s cap is fine once the world is settled and is exactly the
    -- wrong bet at boot: the menu opens while the showcase area is still
    -- streaming, the freemode model is not in memory yet, the wait expires, and
    -- this returned false — silently, to a caller that ignored the result. The
    -- player was left as the game's default ped (player_zero, Michael) with
    -- nothing to correct it, which is why pressing START then produced the
    -- right racer: that path does the swap again, seconds later, when it works.
    local t = 0
    while not HasModelLoaded(modelHash) and t < 1000 do
        RequestModel(modelHash)
        Wait(10)
        t = t + 1
    end

    if not HasModelLoaded(modelHash) then
        print(("^1[spz-spawn] Model %s never loaded — preview ped left as-is^7"):format(modelHash))
        return false
    end

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

        -- Still creation (returning from the appearance editor) — same framing.
        CreateCinematicCamera(CAM_COMPOSE_CREATION)
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
