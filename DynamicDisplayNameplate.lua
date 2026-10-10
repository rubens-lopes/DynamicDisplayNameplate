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
-- Blizzard's own switch for class-coloured friendly player names.
local CLASS_COLOR_CVAR = "nameplateUseClassColorForFriendlyPlayerUnitNames"
-- Blizzard's own name-only mode for friendly players, bar hidden even when hurt.
local ONLY_NAME_CVAR = "nameplateShowOnlyNameForFriendlyPlayerUnits"
-- Alpha of a full-health friendly plate in combat with the fade option; out
-- of combat it's 0. Fixed for now; meant to become a slider.
local FADED_ALPHA = 0.3
-- How far plates move sideways with the sides option, in UI units.
local SIDE_OFFSET = 60
local TITLE = "Dynamic Display Nameplate"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Every saved switch, in the order the options panel shows them. All start on
-- unless marked off = true.
local OPTIONS = {
    { key = "enemies", command = "enemies", label = "Enemy plates only in combat",
      help = "Turns enemy nameplates on when you enter combat and off when you leave it. "
          .. "Turn this off to leave them alone; V shows and hides them as usual." },
    { key = "engaged", command = "engaged", label = "Enemy plates only for mobs fighting your group", off = true,
      help = "Hides the plate of any enemy NPC that isn't your target, has nobody in your group on its threat list "
          .. "and isn't targeting one of you. Enemy players always show. Hidden plates still take up room when plates stack." },
    { key = "friends", command = "friends", label = "Friendly player plates only in combat",
      help = "Turns friendly player nameplates on when you enter combat and off when you leave it. "
          .. "Turn this off to leave them alone; Shift+V shows and hides them as usual." },
    { key = "groupOnly", command = "group", label = "Friendly player plates only for your party or raid", off = true,
      help = "Hides the plate of any friendly player who isn't in your party or raid, so solo you see none. "
          .. "Friendly NPCs aren't affected. Hidden plates still take up room when plates stack." },
    { key = "fadeFull", command = "fadefull", label = "Fade friendly plates at full health",
      help = "While a friendly player is at full health, their plate is faint in combat and hidden out of combat. "
          .. "It turns solid as soon as they lose health. Hidden plates still take up room when plates stack." },
    { key = "showHurt", command = "showhurt", label = "Show hurt friendly plates out of combat",
      help = "Keeps friendly plates switched on outside combat, so anyone below full health still shows. "
          .. "Players at full health stay hidden out of combat. Works with the friendly combat option; "
          .. "with that off, friendly plates are left to you." },
    { key = "names", command = "names", label = "Only the name of friendly players at full health", off = true,
      help = "In place of fading or hiding them, friendly plates at full health show just the name, in class colour, "
          .. "in and out of combat. The health bar appears as soon as they lose health. With the friendly combat option "
          .. "on, this keeps friendly plates switched on outside combat. Turns off Blizzard's own name-only setting, "
          .. "which hides the bar even when they're hurt, and puts it back when you turn this off." },
    { key = "deficit", command = "deficit", label = "Missing health on friendly plates", off = true,
      help = "Friendly plates show how much health is missing (-0 at full health) in place of Blizzard's health number. "
          .. "Inside dungeons and raids Blizzard keeps friendly plates off limits to addons; there, the party frames "
          .. "can show missing health instead. This used to be the Deficit Plates addon; disable that one." },
    { key = "sides", command = "sides", label = "Friendly plates on the left, enemy plates on the right",
      help = "Each plate shifts sideways: friendly ones to the left of the character, enemy ones to the right, "
          .. "so the two groups don't mix. On clients with the nameplateMotion setting, plates also stack "
          .. "instead of overlapping, and turning this off puts that setting back." },
}

-- Replaced by the saved table on ADDON_LOADED.
local settings = {}
for _, option in ipairs(OPTIONS) do settings[option.key] = not option.off end

local warned = {}
local lastWrite = {}
local lastError
local inCombat = false
-- Nameplate unit token -> Blizzard nameplate, while that plate is shown.
local plates = {}
-- Nameplate unit tokens of shown plates addons may not touch.
local forbidden = {}
-- Blizzard UnitFrames we moved or faded. Weak keys: Blizzard reuses them.
local moved = setmetatable({}, { __mode = "k" })
local faded = setmetatable({}, { __mode = "k" })
-- Health bars we faded to leave only the name, same weak keys.
local barFaded = setmetatable({}, { __mode = "k" })
-- Our missing-health text per Blizzard UnitFrame, same weak keys.
local deficitTexts = setmetatable({}, { __mode = "k" })
-- The old Deficit Plates addon, if still enabled, owns the health text.
local deficitPlatesLoaded = false

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

-- nil leaves the setting alone: friendly plates are managed only while the
-- friendly combat option is on. Hurt friends and names need them on out of
-- combat too.
local function FriendsWanted(combat)
    if not settings.friends then return end
    if settings.showHurt or settings.names then return true end
    return combat
end

-- A game setting held at value while an option is on. The old value is saved
-- under beforeKey so turning the option off, even after a reload, puts it
-- back. A setting the client lacks is skipped without a warning.
local function Hold(on, cvar, value, beforeKey)
    if InCombatLockdown() or GetValue(cvar) == nil then return end
    if on then
        local current = GetValue(cvar)
        if current == value then return end
        if settings[beforeKey] == nil then settings[beforeKey] = current end
        SetValue(cvar, value)
    elseif settings[beforeKey] ~= nil then
        SetValue(cvar, settings[beforeKey])
        settings[beforeKey] = nil
    end
end

-- Stacking on while sides is on (WoW Forever has no nameplateMotion). While
-- names is on, class colour on and Blizzard's name-only mode off, since that
-- one hides the bar of hurt friends too.
local function ApplyHeld()
    Hold(settings.sides, MOTION_CVAR, "1", "motionBefore")
    Hold(settings.names, CLASS_COLOR_CVAR, "1", "classColorBefore")
    Hold(settings.names, ONLY_NAME_CVAR, "0", "onlyNameBefore")
end

-- Unit state can be secret on this client. Comparing a secret raises, so
-- treat it as unknown.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- true if the unit is in your party or raid, false if not, nil if secret.
local function InGroup(unit)
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if issecretvalue and (issecretvalue(party) or issecretvalue(raid)) then return nil end
    return (party or raid) and true or false
end

-- Friendliness can be secret (inside instances, it seems). Party and raid
-- members are always friends, so they still count when it is.
local function IsFriend(unit)
    local friend = Plain(UnitIsFriend("player", unit))
    if friend ~= nil then return friend == true end
    return InGroup(unit) == true
end

-- Whose threat counts as the group's: you, your pet, and party or raid
-- members with their pets. Rebuilt when the group changes.
local members = { "player", "pet" }
local function UpdateMembers()
    members = { "player", "pet" }
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        members[#members + 1] = prefix .. i
        members[#members + 1] = prefix .. "pet" .. i
    end
end

-- true if the mob is your target, has someone in the group on its threat
-- list or targets one of you; false if none of that; nil if a secret value
-- hid part of the answer.
local function Engaged(unit)
    local unknown = false
    local function Yes(v)
        if issecretvalue and issecretvalue(v) then
            unknown = true
            return false
        end
        return v ~= nil and v ~= false
    end
    if Yes(UnitIsUnit(unit, "target")) then return true end
    -- nil when not on the threat list, 0-3 when on it.
    for _, member in ipairs(members) do
        if Yes(UnitThreatSituation(member, unit)) then return true end
    end
    local target = unit .. "target"
    if Yes(UnitIsUnit(target, "player")) or Yes(UnitIsUnit(target, "pet"))
        or Yes(UnitPlayerOrPetInParty(target)) or Yes(UnitPlayerOrPetInRaid(target)) then
        return true
    end
    if not unknown then return false end
end

-- Hidden: friendly players known not to be in the group (group only), and
-- enemy NPCs known not to be fighting it (engaged). Unknown means shown.
local function ShouldHide(unit, friend)
    local player = Plain(UnitIsPlayer(unit))
    if friend then
        if not settings.groupOnly or player ~= true then return false end
        return InGroup(unit) == false
    end
    if not settings.engaged or player ~= false then return false end
    return Engaged(unit) == false
end

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

-- With the names option, a full-health friend's health bar fades out and its
-- name stays, in place of the whole plate fading.
local function Fade(uf, unit, friend, hide)
    local bar = uf.HealthBarsContainer or uf.healthBar
    local namesOnly = friend and settings.names and bar and not hide
    local atFull = friend and not namesOnly and FullHealthTarget()
    if hide then
        uf:SetAlpha(0)
        faded[uf] = true
    elseif atFull then
        uf:SetAlpha(FullHealthAlpha(unit, atFull))
        faded[uf] = true
    elseif faded[uf] then
        uf:SetAlpha(1)
        faded[uf] = nil
    end
    if not bar then return end
    if namesOnly then
        bar:SetAlpha(FullHealthAlpha(unit, 0))
        barFaded[bar] = true
    elseif barFaded[bar] then
        bar:SetAlpha(1)
        barFaded[bar] = nil
    end
end

-- Blizzard's health texts are touched only on frames that got our text, so
-- with the option off, plates stay fully Blizzard's.
local function ShowDeficit(uf, unit, friend)
    local bar = uf.healthBar
    if not bar then return end
    local show = friend and settings.deficit and not deficitPlatesLoaded
    if show and not deficitTexts[uf] then deficitTexts[uf] = ns.Deficit.CreateText(bar) end
    if show or deficitTexts[uf] then ns.Deficit.Update(bar, deficitTexts[uf], unit, show) end
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
    local hide
    ok, hide = pcall(ShouldHide, unit, friend)
    if not ok then
        Warn("decide which plates to hide", tostring(hide))
        hide = false
    end
    ok, err = pcall(Fade, uf, unit, friend, hide)
    if not ok then Warn("fade full-health plates", tostring(err)) end
    ok, err = pcall(ShowDeficit, uf, unit, friend)
    if not ok then Warn("show missing health", tostring(err)) end
end

local function UpdateAllPlates()
    for unit in pairs(plates) do UpdatePlate(unit) end
end

local function Apply(combat)
    inCombat = combat
    if settings.enemies then SetPlates(PLATES[1].cvar, combat) end
    local friends = FriendsWanted(combat)
    if friends ~= nil then SetPlates(PLATES[2].cvar, friends) end
    ApplyHeld()
    UpdateAllPlates()
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    -- Forbidden plates (friendly ones inside instances) are Blizzard-only.
    if plate:IsForbidden() then
        forbidden[unit] = true
        return
    end
    plates[unit] = plate
    UpdatePlate(unit)
end

local function OnUnit(unit)
    if plates[unit] then UpdatePlate(unit) end
end

local PLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED = OnPlateAdded,
    NAME_PLATE_UNIT_REMOVED = function(unit)
        plates[unit] = nil
        forbidden[unit] = nil
    end,
    -- Friendly plates inside instances arrive only through these.
    FORBIDDEN_NAME_PLATE_UNIT_ADDED = function(unit) forbidden[unit] = true end,
    FORBIDDEN_NAME_PLATE_UNIT_REMOVED = function(unit) forbidden[unit] = nil end,
    UNIT_HEALTH = OnUnit,
    UNIT_MAXHEALTH = OnUnit,
    UNIT_FACTION = OnUnit,
    UNIT_THREAT_LIST_UPDATE = OnUnit,
    UNIT_TARGET = OnUnit,
    PLAYER_TARGET_CHANGED = UpdateAllPlates,
    GROUP_ROSTER_UPDATE = function()
        UpdateMembers()
        UpdateAllPlates()
    end,
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
            if settings[option.key] == nil then settings[option.key] = not option.off end
        end
        frame:UnregisterEvent("ADDON_LOADED")
        return
    end
    if PLATE_EVENTS[event] then return PLATE_EVENTS[event](arg1) end
    if event == "PLAYER_ENTERING_WORLD" then
        UpdateMembers()
        local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        deficitPlatesLoaded = loaded ~= nil and loaded("DeficitPlates") and true or false
        if deficitPlatesLoaded and settings.deficit and not warned.deficitPlates then
            warned.deficitPlates = true
            print(TAG .. "Deficit Plates is still enabled, so it keeps the health text. "
                .. "Its feature is part of this addon now; disable it in the AddOns list.")
        end
    end
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
        if option.key == "deficit" and settings.deficit and deficitPlatesLoaded then
            Say("Deficit Plates is still enabled, so it keeps the health text. Disable it in the AddOns list.")
        end
    elseif settings[option.key] then
        Say(("%s plates now show only in combat."):format(plate.label))
    else
        Say(("%s plates are no longer managed. Press %s to toggle them yourself."):format(
            plate.label, plate.keybind))
    end
end

-- /ddn-<command> [on|off]: no argument toggles.
local function MakeToggle(key)
    local option
    for _, o in ipairs(OPTIONS) do
        if o.key == key then option = o end
    end
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
    -- Also kept in the saved variables (written on /reload or logout), for
    -- output too long to screenshot. The run before is kept too, to compare.
    local lines = {}
    settings.previousStatus = settings.lastStatus
    settings.lastStatus = lines
    local echo = print
    local function print(line)
        lines[#lines + 1] = line
        echo(line)
    end
    print(TAG .. (InCombatLockdown() and "in combat lockdown" or "out of combat") .. " at " .. date("%H:%M:%S"))
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
    for _, cvar in ipairs({ MOTION_CVAR, CLASS_COLOR_CVAR, ONLY_NAME_CVAR }) do
        local value = GetValue(cvar)
        print(("  %s = %s (addon last wrote %s)"):format(cvar,
            value == nil and "missing" or value, lastWrite[cvar] or "nothing"))
    end
    local shown, friends = 0, 0
    for unit in pairs(plates) do
        shown = shown + 1
        if IsFriend(unit) then friends = friends + 1 end
    end
    local blocked = 0
    for _ in pairs(forbidden) do blocked = blocked + 1 end
    print(("  plates shown: %d, friendly: %d, off limits to addons: %d"):format(shown, friends, blocked))
    -- Whether the engaged check can see threat and targets on this client.
    -- "unknown" counts plates where a secret value hid the answer.
    local fighting, idle, unknown = 0, 0, 0
    for unit in pairs(plates) do
        if not IsFriend(unit) then
            local ok, engaged = pcall(Engaged, unit)
            if not ok or engaged == nil then
                unknown = unknown + 1
            elseif engaged then
                fighting = fighting + 1
            else
                idle = idle + 1
            end
        end
    end
    print(("  enemy plates fighting your group: %d, not fighting: %d, unknown: %d"):format(fighting, idle, unknown))
    local deficits = 0
    for unit in pairs(plates) do
        local text = deficitTexts[plates[unit].UnitFrame]
        if text and ns.Deficit.Visible(text) == "shown" then deficits = deficits + 1 end
    end
    print(("  friendly plates with missing health: %d (UnitHealthMissing: %s, AbbreviateNumbers: %s, Deficit Plates loaded: %s)"):format(
        deficits, UnitHealthMissing and "yes" or "no", AbbreviateNumbers and "yes" or "no",
        deficitPlatesLoaded and "yes" or "no"))
    -- Per plate, which unit checks this client answers and which it hides.
    local function Show(v)
        if issecretvalue and issecretvalue(v) then return "secret" end
        return tostring(v)
    end
    local units = {}
    for unit in pairs(plates) do units[#units + 1] = unit end
    table.sort(units)
    -- How a frame is drawn: shown/visible, alpha, size and points, to tell a
    -- plate we hid from one the client left blank.
    local function Looks(f)
        if not f then return "none" end
        local ok, text = pcall(function()
            local w, h = f:GetSize()
            return ("shown=%s visible=%s alpha=%s size=%sx%s points=%s"):format(Show(f:IsShown()),
                Show(f:IsVisible()), Show(f:GetAlpha()), Show(w), Show(h), Show(f:GetNumPoints()))
        end)
        return ok and text or ("error " .. tostring(text))
    end
    for _, unit in ipairs(units) do
        print(("  %s: friend=%s player=%s party=%s raid=%s -> %s"):format(unit,
            Show(UnitIsFriend("player", unit)), Show(UnitIsPlayer(unit)), Show(UnitInParty(unit)),
            Show(UnitInRaid(unit)), IsFriend(unit) and "friendly" or "enemy"))
        local plate = plates[unit]
        local uf = plate.UnitFrame
        print("    plate: " .. Looks(plate))
        print(("    frame: %s%s"):format(Looks(uf), faded[uf] and " (faded by us)" or ""))
        print("    health bar: " .. Looks(uf and uf.healthBar))
        print("    name: " .. Looks(uf and uf.name))
    end
    print("  last error: " .. (lastError or "none"))
    -- List the client's nameplate show, stacking and overlap CVars, to spot
    -- renamed ones.
    local ok, commands = pcall(function() return C_Console.GetAllCommands() end)
    if not ok or type(commands) ~= "table" then return end
    local others = {}
    for _, info in ipairs(commands) do
        local name = info.command
        local lower = name and name:lower() or ""
        local wanted = lower:find("^nameplate") and (lower:find("^nameplateshow")
            or lower:find("motion") or lower:find("stack") or lower:find("overlap"))
        if wanted and not managed[name] and name ~= MOTION_CVAR and name ~= ONLY_NAME_CVAR then
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
SlashCmdList.DDNENEMIES = MakeToggle("enemies")
SLASH_DDNENGAGED1 = "/ddn-engaged"
SlashCmdList.DDNENGAGED = MakeToggle("engaged")
SLASH_DDNFRIENDS1 = "/ddn-friends"
SlashCmdList.DDNFRIENDS = MakeToggle("friends")
SLASH_DDNGROUP1 = "/ddn-group"
SlashCmdList.DDNGROUP = MakeToggle("groupOnly")
SLASH_DDNFADEFULL1 = "/ddn-fadefull"
SlashCmdList.DDNFADEFULL = MakeToggle("fadeFull")
SLASH_DDNSHOWHURT1 = "/ddn-showhurt"
SlashCmdList.DDNSHOWHURT = MakeToggle("showHurt")
SLASH_DDNNAMES1 = "/ddn-names"
SlashCmdList.DDNNAMES = MakeToggle("names")
SLASH_DDNDEFICIT1 = "/ddn-deficit"
SlashCmdList.DDNDEFICIT = MakeToggle("deficit")
SLASH_DDNSIDES1 = "/ddn-sides"
SlashCmdList.DDNSIDES = MakeToggle("sides")
SLASH_DDNSTATUS1 = "/ddn-status"
SlashCmdList.DDNSTATUS = Status
SLASH_DDNWATCH1 = "/ddn-watch"
SlashCmdList.DDNWATCH = Watch
