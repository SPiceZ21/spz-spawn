-- server/main.lua

--- Show the play menu (welcome screen) instead of spawning immediately.
--- @param source number
--- @param profile table
local function ShowPlayMenu(source, profile)
    if not profile then return end
    TriggerClientEvent("SPZ:showPlayMenu", source, {
        name   = profile.username or GetPlayerName(source),
        rank   = profile.rank_name or "Rookie",
        tier   = profile.license_tier or 0,
        gender = profile.gender or 0,
        playtime = exports['spz-identity']:GetPlaytime(source)
    })
    
    -- Ensure state is MENU when in the play menu
    exports["spz-core"]:SetPlayerState(source, "MENU")
end

--- Execute the physical spawn on the client.
--- @param source number
--- @param profile table
local function SpawnPlayer(source, profile, spawnIndex)
    if not profile then return end
    
    local spawnData = { gender = profile.gender or 0 }
    if spawnIndex and Config.Spawns[spawnIndex] then
        spawnData.coords = Config.Spawns[spawnIndex].coords.xyz
        spawnData.heading = Config.Spawns[spawnIndex].coords.w
    end

    TriggerClientEvent("SPZ:spawnPlayerTarget", source, spawnData)
    
    -- Set state to FREEROAM after spawning
    exports["spz-core"]:SetPlayerState(source, "FREEROAM")
end

-- ── Event Bridging ────────────────────────────────────────────────────────

--- Returning players: Triggered by spz-identity after successful connection/DB load.
AddEventHandler("SPZ:playerReady", function(source, profile)
    print("^2[spz-spawn] DEBUG: Received playerReady for source " .. tostring(source) .. "^7")
    ShowPlayMenu(source, profile)
end)

--- New players: Triggered by character creation after profile is initialized.
AddEventHandler("SPZ:characterReady", function(source)
    print("^2[spz-spawn] DEBUG: Received characterReady for source " .. tostring(source) .. "^7")
    local profile = exports["spz-identity"]:GetProfile(source)
    ShowPlayMenu(source, profile)
end)

--- Explicit request from client when they finish loading
RegisterNetEvent("SPZ:requestPlayMenu", function()
    local src = source
    local profile = exports["spz-identity"]:GetProfile(src)
    if profile then
        print("^2[spz-spawn] DEBUG: Servicing play menu request for " .. tostring(src) .. "^7")
        ShowPlayMenu(src, profile)
    end
end)

-- ── Network Handlers ──────────────────────────────────────────────────────

--- Player clicked START in the spawn menu.
RegisterNetEvent("SPZ:requestSpawn", function(spawnIndex)
    local src  = source
    local profile = exports["spz-identity"]:GetProfile(src)
    if not profile then return end
    SpawnPlayer(src, profile, spawnIndex)
end)

--- Generic respawn request.
RegisterNetEvent("SPZ:requestRespawn", function()
    local src  = source
    local profile = exports["spz-identity"]:GetProfile(src)
    if not profile then return end
    SpawnPlayer(src, profile)
end)
