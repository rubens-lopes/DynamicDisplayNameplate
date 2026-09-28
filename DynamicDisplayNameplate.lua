-- Enemy and friendly player nameplates only while in combat, each one
-- switchable with a /ddn- command.
-- PLAYER_REGEN_DISABLED fires just before combat lockdown starts and
-- PLAYER_REGEN_ENABLED just after it ends, so both writes happen while the
-- client still accepts them.

local ADDON_NAME = ...
-- On the 12.x engine the friendly-player CVar is nameplateShowFriendlyPlayers;
-- nameplateShowFriends doesn't exist.
local PLATES = {
    { key = "enemies", cvar = "nameplateShowEnemies", label = "enemy", keybind = "V" },
    { key = "friends", cvar = "nameplateShowFriendlyPlayers", label = "friendly player", keybind = "Shift+V" },
}
local TITLE = "Dynamic Display Nameplate"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Replaced by the saved table on ADDON_LOADED.
local settings = { enemies = true, friends = true }

local warned = {}
local lastWrite = {}

local function GetValue(cvar)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get(cvar)
end

local function Warn(cvar, reason)
    if warned[cvar] then return end
    warned[cvar] = true
    print(("|cffff8800%s:|r couldn't change %s (%s)"):format(TITLE, cvar, reason))
end

local function SetPlates(cvar, show)
    if InCombatLockdown() then return end
    -- Writing a CVar the client doesn't have fails silently, so check first.
    if GetValue(cvar) == nil then return Warn(cvar, "no such setting on this client") end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local value = show and "1" or "0"
    local ok, result = pcall(set, cvar, value)
    lastWrite[cvar] = value
    if ok and result ~= false then return end
    Warn(cvar, tostring(result))
end

local function Apply(inCombat)
    for _, plate in ipairs(PLATES) do
        if settings[plate.key] then SetPlates(plate.cvar, inCombat) end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        DynamicDisplayNameplateDB = DynamicDisplayNameplateDB or {}
        settings = DynamicDisplayNameplateDB
        for _, plate in ipairs(PLATES) do
            if settings[plate.key] == nil then settings[plate.key] = true end
        end
        frame:UnregisterEvent("ADDON_LOADED")
        return
    end
    Apply(event == "PLAYER_REGEN_DISABLED")
end)

local function Say(msg) print(TAG .. msg) end

local function Help()
    Say("commands")
    print("  /ddn-help - show this list")
    print("  /ddn-status - show the nameplate settings the addon sees")
    print("  /ddn-watch - print every game setting change until run again (troubleshooting)")
    for _, plate in ipairs(PLATES) do
        print(("  /ddn-%s [on|off] - show %s plates only in combat (now %s)"):format(
            plate.key, plate.label, settings[plate.key] and "on" or "off"))
    end
end

-- /ddn-enemies and /ddn-friends: no argument toggles.
local function MakeToggle(plate)
    return function(arg)
        arg = (arg or ""):lower():match("^%s*(.-)%s*$")
        if arg == "on" then
            settings[plate.key] = true
        elseif arg == "off" then
            settings[plate.key] = false
        elseif arg == "" then
            settings[plate.key] = not settings[plate.key]
        else
            Say(("usage: /ddn-%s [on|off]"):format(plate.key))
            return
        end
        if settings[plate.key] then
            Say(("%s plates now show only in combat."):format(plate.label))
            SetPlates(plate.cvar, false)
        else
            Say(("%s plates are no longer managed. Press %s to toggle them yourself."):format(
                plate.label, plate.keybind))
        end
    end
end

local function Status()
    Say(InCombatLockdown() and "in combat lockdown" or "out of combat")
    local managed = {}
    for _, plate in ipairs(PLATES) do
        local value = GetValue(plate.cvar)
        print(("  %s plates %s: %s = %s (addon last wrote %s)"):format(plate.label,
            settings[plate.key] and "managed" or "not managed", plate.cvar,
            value == nil and "missing" or value, lastWrite[plate.cvar] or "nothing"))
        managed[plate.cvar] = true
    end
    -- List every nameplateShow* CVar the client has, to spot renamed ones.
    local ok, commands = pcall(function() return C_Console.GetAllCommands() end)
    if not ok or type(commands) ~= "table" then return end
    local others = {}
    for _, info in ipairs(commands) do
        local name = info.command
        if name and name:lower():find("^nameplateshow") and not managed[name] then
            local value = GetValue(name)
            if value ~= nil then others[#others + 1] = name .. "=" .. value end
        end
    end
    table.sort(others)
    if #others > 0 then print("  other: " .. table.concat(others, ", ")) end
end

local watcher

local function Watch()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(_, _, name, value)
            print(("  setting changed: %s = %s"):format(tostring(name), tostring(value)))
        end)
    end
    if watcher:IsEventRegistered("CVAR_UPDATE") then
        watcher:UnregisterEvent("CVAR_UPDATE")
        Say("stopped watching setting changes.")
    else
        watcher:RegisterEvent("CVAR_UPDATE")
        Say("watching setting changes. Run /ddn-watch again to stop.")
    end
end

SLASH_DDNHELP1 = "/ddn-help"
SlashCmdList.DDNHELP = Help
SLASH_DDNENEMIES1 = "/ddn-enemies"
SlashCmdList.DDNENEMIES = MakeToggle(PLATES[1])
SLASH_DDNFRIENDS1 = "/ddn-friends"
SlashCmdList.DDNFRIENDS = MakeToggle(PLATES[2])
SLASH_DDNSTATUS1 = "/ddn-status"
SlashCmdList.DDNSTATUS = Status
SLASH_DDNWATCH1 = "/ddn-watch"
SlashCmdList.DDNWATCH = Watch
