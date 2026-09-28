-- Enemy (and, optionally, friendly) nameplates only while in combat.
-- PLAYER_REGEN_DISABLED fires just before combat lockdown starts and
-- PLAYER_REGEN_ENABLED just after it ends, so both writes happen while the
-- client still accepts them.

local ADDON_NAME = ...
local ENEMY_CVAR = "nameplateShowEnemies"
local FRIEND_CVAR = "nameplateShowFriends"
local TITLE = "Dynamic Display Nameplate"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Replaced by the saved table on ADDON_LOADED.
local settings = { friends = true }

local warned = {}

local function SetPlates(cvar, show)
    if InCombatLockdown() then return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, result = pcall(set, cvar, show and "1" or "0")
    if ok and result ~= false then return end
    if warned[cvar] then return end
    warned[cvar] = true
    print(("|cffff8800%s:|r couldn't change %s (%s)"):format(TITLE, cvar, tostring(result)))
end

local function Apply(inCombat)
    SetPlates(ENEMY_CVAR, inCombat)
    if settings.friends then SetPlates(FRIEND_CVAR, inCombat) end
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
        if settings.friends == nil then settings.friends = true end
        frame:UnregisterEvent("ADDON_LOADED")
        return
    end
    Apply(event == "PLAYER_REGEN_DISABLED")
end)

local function Say(msg) print(TAG .. msg) end

local function Help()
    Say("commands")
    print("  /ddn-help - show this list")
    print("  /ddn-friends [on|off] - also show friendly player plates only in combat (now "
        .. (settings.friends and "on" or "off") .. ")")
end

local function Friends(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "on" then
        settings.friends = true
    elseif arg == "off" then
        settings.friends = false
    elseif arg == "" then
        settings.friends = not settings.friends
    else
        Say("usage: /ddn-friends [on|off]")
        return
    end
    if settings.friends then
        Say("friendly plates now show only in combat.")
        SetPlates(FRIEND_CVAR, false)
    else
        Say("friendly plates are no longer managed. Press Shift+V to toggle them yourself.")
    end
end

SLASH_DDNHELP1 = "/ddn-help"
SlashCmdList.DDNHELP = Help
SLASH_DDNFRIENDS1 = "/ddn-friends"
SlashCmdList.DDNFRIENDS = Friends
