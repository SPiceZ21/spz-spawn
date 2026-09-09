-- server/main.lua
--
-- Answers the client's boot handshake and performs spawns.
--
-- The old flow was push-based: the server decided what the player should see at
-- connect time and fired it at them. At that moment the client has no scripts
-- running, so those events went nowhere, and the client compensated by polling
-- SPZ:requestPlayMenu every 1.5 seconds forever. First-time players had no such
-- fallback and simply never got a character creator.
--
-- It is pull-based now. The client boots, says hello, and the server answers
-- with one decision — create a character, or show the play menu. One request,
-- one reply, no polling, and nothing is sent to a client that has not spoken.

-- ── The lobby bucket ─────────────────────────────────────────────────────────
--
-- A player between the loading screen and their first spawn is standing at a
-- spawn point with a camera flying around them, in whatever appearance the last
-- session left behind, sometimes for minutes. In freeroam that is a body in the
-- middle of the world that everybody can see, drive into and be blocked by.
--
-- So each one gets their OWN bucket for that window, and is moved to freeroam
-- only when they actually spawn. Per player rather than one shared lobby: two
-- people picking a spawn point would otherwise watch each other stand there,
-- and the camera fly-through would have strangers in the shot.
--
-- The bucket is deleted as they leave it. Ids are never reused by spz-core, so
-- failing to delete would leak a registry entry per join for the life of the
-- server.

local LobbyBucket = {}     -- [source] = bucketId

local function enterLobbyBucket(source)
    if LobbyBucket[source] then return LobbyBucket[source] end

    local id = exports['spz-core']:CreateBucket(("lobby_%s"):format(source), false)
    if not id then
        print(("^3[spz-spawn] Could not create a lobby bucket for %s — they will load into freeroam.^7")
            :format(tostring(source)))
        return nil
    end

    LobbyBucket[source] = id
    exports['spz-core']:AssignPlayerToBucket(source, id)
    return id
end

--- Back to freeroam, and the private bucket goes with them.
---
--- Order matters: the player is moved FIRST and the bucket deleted after, so
--- the delete never runs against a bucket that still has somebody in it (which
--- spz-core handles, loudly, by evacuating them — a warning nobody needs to
--- read every time a player spawns).
local function leaveLobbyBucket(source)
    local id = LobbyBucket[source]
    if not id then return end

    LobbyBucket[source] = nil
    exports['spz-core']:AssignPlayerToBucket(source, 0)
    exports['spz-core']:DeleteBucket(id)
end

-- A player who disconnects at the menu never spawns, so nothing else would ever
-- clean their bucket up.
AddEventHandler("playerDropped", function()
    local src = source
    local id  = LobbyBucket[src]
    if not id then return end

    LobbyBucket[src] = nil
    exports['spz-core']:DeleteBucket(id)
end)

--- Build the play-menu payload for a loaded profile.
local function PlayMenuData(source, profile)
    return {
        name     = profile.username or GetPlayerName(source),
        rank     = profile.rank_name or profile.rank or "Rookie",
        tier     = profile.license_tier or 0,
        gender   = profile.gender or 0,
        playtime = exports['spz-identity']:GetPlaytime(source),
    }
end

--- Decide what this player should be looking at and tell them.
---
--- Idempotent by design: a client that retries because its first hello was lost
--- gets the same answer rather than a second, conflicting one.
local function SendRoute(source)
    local profile = exports['spz-identity']:AttachProfile(source)

    -- Before either branch: whether they are creating a character or picking a
    -- spawn, they are about to stand somewhere visible for a while.
    enterLobbyBucket(source)

    if not profile then
        TriggerClientEvent("SPZ:spawn:route", source, {
            mode   = "error",
            reason = "Your driver profile could not be loaded.",
        })
        return false
    end

    if profile.first_time == 1 then
        Player(source).state:set("state", "CREATING", true)
        TriggerClientEvent("SPZ:spawn:route", source, {
            mode      = "create",
            suggested = exports['spz-identity']:GetPlatformName(source),
        })
        return true
    end

    Player(source).state:set("state", "MENU", true)
    TriggerClientEvent("SPZ:spawn:route", source, {
        mode       = "menu",
        playerData = PlayMenuData(source, profile),
    })
    return true
end

--- The client is running and ready to be told what to do.
RegisterNetEvent("SPZ:spawn:hello", function()
    local src = source
    print(("^2[spz-spawn] Handshake from %s^7"):format(tostring(src)))
    SendRoute(src)
end)

-- ── Physical spawn ────────────────────────────────────────────────────────────

--- @param source number
--- @param profile table
local function SpawnPlayer(source, profile, spawnIndex)
    if not profile then return end

    local spawnData = { gender = profile.gender or 0 }
    if spawnIndex and Config.Spawns[spawnIndex] then
        spawnData.coords  = Config.Spawns[spawnIndex].coords.xyz
        spawnData.heading = Config.Spawns[spawnIndex].coords.w
    end

    -- Out of the private bucket and into the world BEFORE the client is told
    -- where to put the ped: arriving in freeroam and then being routed there is
    -- a visible pop for everyone already standing at that spawn point.
    leaveLobbyBucket(source)

    TriggerClientEvent("SPZ:spawnPlayerTarget", source, spawnData)

    Player(source).state:set("state", "FREEROAM", true)
end

--- Player clicked START in the spawn menu.
RegisterNetEvent("SPZ:requestSpawn", function(spawnIndex)
    local src     = source
    local profile = exports['spz-identity']:GetProfile(src)
    if not profile then
        print(("^1[spz-spawn] Spawn request from %s with no profile^7"):format(tostring(src)))
        TriggerClientEvent("SPZ:spawn:route", src, {
            mode   = "error",
            reason = "Your driver profile could not be loaded.",
        })
        return
    end
    SpawnPlayer(src, profile, spawnIndex)
end)

--- Generic respawn request.
RegisterNetEvent("SPZ:requestRespawn", function()
    local src     = source
    local profile = exports['spz-identity']:GetProfile(src)
    if not profile then return end
    SpawnPlayer(src, profile)
end)

-- ── Post-creation ─────────────────────────────────────────────────────────────
--
-- Character creation flips first_time to 0, which changes the answer this
-- player would get from SendRoute. The client asks again once its appearance
-- editor is closed; this handler exists so the server does not have to guess
-- when that is.

RegisterNetEvent("SPZ:spawn:requestMenu", function()
    local src = source
    SendRoute(src)
end)

-- ── Compatibility ─────────────────────────────────────────────────────────────
--
-- The pre-handshake event name, kept so anything still calling it keeps
-- working. It routes through exactly the same decision.

RegisterNetEvent("SPZ:requestPlayMenu", function()
    SendRoute(source)
end)
