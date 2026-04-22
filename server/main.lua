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
    })
end

--- Execute the physical spawn on the client.
--- @param source number
--- @param profile table
local function SpawnPlayer(source, profile)
    if not profile then return end
    TriggerClientEvent("SPZ:spawnPlayerTarget", source, { gender = profile.gender or 0 })
end

-- ── Event Bridging ────────────────────────────────────────────────────────

--- Returning players: Triggered by spz-identity after successful connection/DB load.
AddEventHandler("SPZ:playerReady", function(source, profile)
    ShowPlayMenu(source, profile)
end)

--- New players: Triggered by character creation after profile is initialized.
AddEventHandler("SPZ:characterReady", function(source)
    local profile = exports["spz-identity"]:GetProfile(source)
    ShowPlayMenu(source, profile)
end)

-- ── Network Handlers ──────────────────────────────────────────────────────

--- Player clicked ENTER in the play menu.
RegisterNetEvent("SPZ:requestSpawn", function()
    local src  = source
    local profile = exports["spz-identity"]:GetProfile(src)
    if not profile then return end
    SpawnPlayer(src, profile)
end)

--- Generic respawn request (kept for future modularity if death is ever re-enabled, 
--  but currently not called by this resource's client).
RegisterNetEvent("SPZ:requestRespawn", function()
    local src  = source
    local profile = exports["spz-identity"]:GetProfile(src)
    if not profile then return end
    SpawnPlayer(src, profile)
end)
