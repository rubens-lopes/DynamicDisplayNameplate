-- Enemy and friendly player nameplates only while in combat, plus friendly
-- plates that follow health and a friendly-left / enemy-right layout. Every
-- switch is in the options panel and has a /ddn- command.
-- PLAYER_REGEN_DISABLED fires just before combat lockdown starts and
-- PLAYER_REGEN_ENABLED just after it ends, so both writes happen while the
-- client still accepts them.

local ADDON_NAME, ns = ...
-- On the 12.x engine the friendly-player CVar is nameplateShowFriendlyPlayers;
-- nameplateShowFriends doesn't exist.
local PLATES = {
    { key = "enemies", cvar = "nameplateShowEnemies", label = "enemy", keybind = "V" },
    { key = "friends", cvar = "nameplateShowFriendlyPlayers", label = "friendly player", keybind = "Shift+V" },
}
-- 1 stacks plates, 0 lets them overlap.
local MOTION_CVAR = "nameplateMotion"
-- Alpha of a full-health friendly plate in combat with the fade option; out
-- of combat it's 0. Fixed for now; meant to become a slider.
local FADED_ALPHA = 0.3
-- How far plates move sideways with the sides option, in UI units.
local SIDE_OFFSET = 60
local TITLE = "Dynamic Display Nameplate"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Every saved switch, in the order the options panel shows them. All start on.
local OPTIONS = {
    { key = "enemies", command = "enemies", label = "Enemy plates only in combat",
      help = "Turns enemy nameplates on when you enter combat and off when you leave it. "
          .. "Turn this off to leave them alone; V shows and hides them as usual." },
    { key = "friends", command = "friends", label = "Friendly player plates only in combat",
      help = "Turns friendly player nameplates on when you enter combat and off when you leave it. "
          .. "Turn this off to leave them alone; Shift+V shows and hides them as usual." },
    { key = "fadeFull", command = "fadefull", label = "Fade friendly plates at full health",
      help = "While a friendly player is at full health, their plate is faint in combat and hidden out of combat. "
          .. "It turns solid as soon as they lose health. Hidden plates still take up room when plates stack." },
    { key = "showHurt", command = "showhurt", label = "Show hurt friendly plates out of combat",
      help = "Keeps friendly plates switched on outside combat, so anyone below full health still shows. "
          .. "Players at full health stay hidden out of combat while the fade option or the friendly combat option is on." },
    { key = "sides", command = "sides", label = "Friendly plates on the left, enemy plates on the right",
      help = "Plates stack instead of overlapping, and each plate shifts sideways: friendly ones to the left "
          .. "of the character, enemy ones to the right, so the two groups don't mix. "
          .. "Turning this off puts the overlap setting back the way it was." },
}

-- Replaced by the saved table on ADDON_LOADED.
local settings = {}
for _, option in ipairs(OPTIONS) do settings[option.key] = true end

local warned = {}
local lastWrite = {}
local lastError
local inCombat = false
-- Nameplate unit token -> Blizzard nameplate, while that plate is shown.
local plates = {}
-- Blizzard UnitFrames we moved or faded. Weak keys: Blizzard reuses them.
local moved = setmetatable({}, { __mode = "k" })
local faded = setmetatable({}, { __mode = "k" })

local function GetValue(cvar)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get(cvar)
end

local function Warn(what, reason)
    lastError = ("couldn't %s (%s)"):format(what, reason)
    if warned[what] then return end
    warned[what] = true
    print(("|cffff8800%s:|r %s"):format(TITLE, lastError))
end

local function SetValue(cvar, value)
    if InCombatLockdown() then return end
    -- Writing a CVar the client doesn't have fails silently, so check first.
    if GetValue(cvar) == nil then return Warn("change " .. cvar, "no such setting on this client") end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, result = pcall(set, cvar, value)
    lastWrite[cvar] = value
    if ok and result ~= false then return end
    Warn("change " .. cvar, tostring(result))
end

local function SetPlates(cvar, show) SetValue(cvar, show and "1" or "0") end

-- Hurt friends need the plates on out of combat; otherwise they follow combat
-- when managed. nil leaves the setting alone.
local function FriendsWanted(combat)
    if settings.showHurt then return true end
    if settings.friends then return combat end
end

-- Stacking on while sides is on. The old value is saved so turning sides off,
-- even after a reload, puts it back.
local function ApplyMotion()
    if InCombatLockdown() then return end
    if settings.sides then
        local current = GetValue(MOTION_CVAR)
        if current == "1" then return end
        if current ~= nil and settings.motionBefore == nil then settings.motionBefore = current end
        SetValue(MOTION_CVAR, "1")
    elseif settings.motionBefore ~= nil then
        SetValue(MOTION_CVAR, settings.motionBefore)
        settings.motionBefore = nil
    end
end

-- Unit state can be secret on this client. Comparing a secret raises, so
-- treat it as unknown.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function IsFriend(unit) return Plain(UnitIsFriend("player", unit)) == true end

-- Health is secret, so it can't be compared to 100%. A curve turns it into
-- 1 below full health and atFull at full, and SetAlpha takes that as it is.
-- One curve per atFull value.
local curves = {}
local function FullHealthAlpha(unit, atFull)
    local curve = curves[atFull]
    if not curve then
        curve = C_CurveUtil.CreateCurve()
        curve:AddPoint(0, 1)
        curve:AddPoint(0.999, 1)
        curve:AddPoint(1, atFull)
        curves[atFull] = curve
    end
    return UnitHealthPercent(unit, false, curve)
end

-- Alpha for a full-health friendly plate, or nil to leave it solid. Out of
-- combat, friendly plates are on only for hurt friends (show hurt) or because
-- the player pressed Shift+V; either way full-health ones hide.
local function FullHealthTarget()
    if inCombat then return settings.fadeFull and FADED_ALPHA or nil end
    if settings.fadeFull or (settings.friends and settings.showHurt) then return 0 end
end

local function Place(plate, uf, friend)
    if settings.sides then
        local dx = friend and -SIDE_OFFSET or SIDE_OFFSET
        uf:ClearAllPoints()
        uf:SetPoint("TOPLEFT", plate, "TOPLEFT", dx, 0)
        uf:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", dx, 0)
        moved[uf] = true
    elseif moved[uf] then
        uf:ClearAllPoints()
        uf:SetAllPoints(plate)
        moved[uf] = nil
    end
end

local function Fade(uf, unit, friend)
    local atFull = friend and FullHealthTarget()
    if atFull then
        uf:SetAlpha(FullHealthAlpha(unit, atFull))
        faded[uf] = true
    elseif faded[uf] then
        uf:SetAlpha(1)
        faded[uf] = nil
    end
end

-- Each step in its own pcall, so a client change shows one chat line
-- instead of a Lua error on every plate.
local function UpdatePlate(unit)
    local plate = plates[unit]
    local uf = plate and plate.UnitFrame
    if not uf then return end
    local friend = IsFriend(unit)
    local ok, err = pcall(Place, plate, uf, friend)
    if not ok then Warn("move plates", tostring(err)) end
    ok, err = pcall(Fade, uf, unit, friend)
    if not ok then Warn("fade full-health plates", tostring(err)) end
end

local function UpdateAllPlates()
    for unit in pairs(plates) do UpdatePlate(unit) end
end

local function Apply(combat)
    inCombat = combat
    if settings.enemies then SetPlates(PLATES[1].cvar, combat) end
    local friends = FriendsWanted(combat)
    if friends ~= nil then SetPlates(PLATES[2].cvar, friends) end
    ApplyMotion()
    UpdateAllPlates()
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return end
    plates[unit] = plate
    UpdatePlate(unit)
end

local function OnUnit(unit)
    if plates[unit] then UpdatePlate(unit) end
end

local PLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED = OnPlateAdded,
    NAME_PLATE_UNIT_REMOVED = function(unit) plates[unit] = nil end,
    UNIT_HEALTH = OnUnit,
    UNIT_MAXHEALTH = OnUnit,
    UNIT_FACTION = OnUnit,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
for event in pairs(PLATE_EVENTS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        DynamicDisplayNameplateDB = DynamicDisplayNameplateDB or {}
        settings = DynamicDisplayNameplateDB
        for _, option in ipairs(OPTIONS) do
            if settings[option.key] == nil then settings[option.key] = true end
        end
        frame:UnregisterEvent("ADDON_LOADED")
        return
    end
    if PLATE_EVENTS[event] then return PLATE_EVENTS[event](arg1) end
    Apply(event == "PLAYER_REGEN_DISABLED" or (event == "PLAYER_ENTERING_WORLD" and InCombatLockdown()))
end)

local function Say(msg) print(TAG .. msg) end

-- Shared with Options.lua, which builds the panel from the same list.
ns.TITLE = TITLE
ns.OPTIONS = OPTIONS
function ns.Get(key) return settings[key] end
function ns.Set(key, value)
    settings[key] = value
    Apply(inCombat)
end

local function Help()
    Say("commands")
    print("  /ddn-help - show this list")
    print("  /ddn-options - open the options panel, with a longer explanation of each switch")
    print("  /ddn-status - show the nameplate settings the addon sees")
    print("  /ddn-watch - print every game setting change until run again (troubleshooting)")
    for _, option in ipairs(OPTIONS) do
        print(("  /ddn-%s [on|off] - %s (now %s)"):format(
            option.command, option.label:lower(), settings[option.key] and "on" or "off"))
    end
end

local function Confirm(option)
    local plate = option.key == "enemies" and PLATES[1] or option.key == "friends" and PLATES[2]
    if not plate then
        Say(("%s: %s."):format(option.label, settings[option.key] and "on" or "off"))
    elseif settings[option.key] then
        Say(("%s plates now show only in combat."):format(plate.label))
    else
        Say(("%s plates are no longer managed. Press %s to toggle them yourself."):format(
            plate.label, plate.keybind))
    end
end

-- /ddn-<command> [on|off]: no argument toggles.
local function MakeToggle(option)
    return function(arg)
        arg = (arg or ""):lower():match("^%s*(.-)%s*$")
        local value
        if arg == "on" then
            value = true
        elseif arg == "off" then
            value = false
        elseif arg == "" then
            value = not settings[option.key]
        else
            Say(("usage: /ddn-%s [on|off]"):format(option.command))
            return
        end
        ns.Set(option.key, value)
        Confirm(option)
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
    for _, option in ipairs(OPTIONS) do
        if option.key ~= "enemies" and option.key ~= "friends" then
            print(("  %s: %s"):format(option.label, settings[option.key] and "on" or "off"))
        end
    end
    local motion = GetValue(MOTION_CVAR)
    print(("  %s = %s (addon last wrote %s)"):format(MOTION_CVAR,
        motion == nil and "missing" or motion, lastWrite[MOTION_CVAR] or "nothing"))
    local shown, friends = 0, 0
    for unit in pairs(plates) do
        shown = shown + 1
        if IsFriend(unit) then friends = friends + 1 end
    end
    print(("  plates shown: %d, friendly: %d"):format(shown, friends))
    print("  last error: " .. (lastError or "none"))
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

-- Options.lua sets ns.OpenOptions once the panel is registered.
local function Options()
    if ns.OpenOptions then return ns.OpenOptions() end
    Say("the options panel isn't available on this client. Use /ddn-help for the commands.")
end

SLASH_DDNHELP1 = "/ddn-help"
SlashCmdList.DDNHELP = Help
SLASH_DDNOPTIONS1 = "/ddn-options"
SlashCmdList.DDNOPTIONS = Options
SLASH_DDNENEMIES1 = "/ddn-enemies"
SlashCmdList.DDNENEMIES = MakeToggle(OPTIONS[1])
SLASH_DDNFRIENDS1 = "/ddn-friends"
SlashCmdList.DDNFRIENDS = MakeToggle(OPTIONS[2])
SLASH_DDNFADEFULL1 = "/ddn-fadefull"
SlashCmdList.DDNFADEFULL = MakeToggle(OPTIONS[3])
SLASH_DDNSHOWHURT1 = "/ddn-showhurt"
SlashCmdList.DDNSHOWHURT = MakeToggle(OPTIONS[4])
SLASH_DDNSIDES1 = "/ddn-sides"
SlashCmdList.DDNSIDES = MakeToggle(OPTIONS[5])
SLASH_DDNSTATUS1 = "/ddn-status"
SlashCmdList.DDNSTATUS = Status
SLASH_DDNWATCH1 = "/ddn-watch"
SlashCmdList.DDNWATCH = Watch
