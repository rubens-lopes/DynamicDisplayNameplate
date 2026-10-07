-- Loads the addon into a stubbed WoW API and checks its CVar writes.
-- Run from the repo root: luajit tests/test_addon.lua

local ADDON_FILES = { "Deficit.lua", "DynamicDisplayNameplate.lua" }
local ADDON_NAME = "DynamicDisplayNameplate"

-- opts.lockdown   InCombatLockdown() result (default false)
-- opts.noCCVar    leave C_CVar undefined so the addon must use global SetCVar
-- opts.setError   make every CVar write raise this error
-- opts.setReturn  value every CVar write returns (default true)
-- opts.saved      DynamicDisplayNameplateDB as left by a previous session
-- opts.missing    CVar name the client doesn't have (GetCVar returns nil)
-- opts.console    CVar names C_Console.GetAllCommands() reports (default: none, API absent)
-- opts.values     starting CVar values (anything else reads "0")
local function Load(opts)
    opts = opts or {}
    local env = { writes = {}, printed = {}, lockdown = opts.lockdown or false, values = opts.values or {} }
    -- env.units[unit] = { friend = bool, health = "full" | "hurt" }, read by the stubs below.
    env.units = {}
    env.plates = {}

    local function NewFrame()
        local f = { events = {}, scripts = {} }
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:IsEventRegistered(event) return self.events[event] == true end
        function f:SetScript(name, fn) self.scripts[name] = fn end
        return f
    end
    local frame = NewFrame()
    env.frames = { frame }

    local function set(name, value)
        if opts.setError then error(opts.setError, 0) end
        env.writes[#env.writes + 1] = name .. "=" .. value
        env.values[name] = value
        if opts.setReturn ~= nil then return opts.setReturn end
        return true
    end

    local G = setmetatable({}, { __index = _G })
    G.CreateFrame = function()
        if #env.frames == 1 and not env.loaded then return frame end
        local f = NewFrame()
        env.frames[#env.frames + 1] = f
        return f
    end
    G.InCombatLockdown = function() return env.lockdown end
    local function get(name)
        if name == opts.missing then return nil end
        return env.values[name] or "0"
    end
    if opts.noCCVar then
        G.SetCVar = set
        G.GetCVar = get
    else
        G.C_CVar = { SetCVar = set, GetCVar = get }
        G.SetCVar = function() error("global SetCVar used while C_CVar exists", 0) end
        G.GetCVar = function() error("global GetCVar used while C_CVar exists", 0) end
    end
    G.print = function(...) env.printed[#env.printed + 1] = table.concat({ ... }, " ") end
    G.SlashCmdList = {}
    if opts.console then
        G.C_Console = { GetAllCommands = function()
            local list = {}
            for _, name in ipairs(opts.console) do list[#list + 1] = { command = name } end
            return list
        end }
    end
    G.DynamicDisplayNameplateDB = opts.saved

    -- A Blizzard plate: records the UnitFrame's alpha and anchors.
    function env.addPlate(unit, friend, health)
        env.units[unit] = { friend = friend, health = health or "full" }
        -- A health bar with Blizzard's three texts; records our FontString.
        local function Text(font)
            local t = { alpha = 1, shown = true, fontArgs = font }
            function t:SetAlpha(a) self.alpha = a end
            function t:GetAlpha() return self.alpha end
            function t:IsShown() return self.shown end
            function t:GetFont() if self.fontArgs then return unpack(self.fontArgs) end end
            function t:SetFont(...) self.fontArgs = { ... } end
            function t:SetText(s) self.text = s end
            function t:SetPoint(point, _, relativePoint) self.point = point .. " " .. relativePoint end
            function t:SetJustifyH(j) self.justify = j end
            return t
        end
        local bar = { created = {} }
        for _, key in ipairs({ "LeftText", "RightText", "TextString" }) do
            bar[key] = Text({ "Fonts\\BLIZZ.TTF", 9, "OUTLINE" })
        end
        function bar:CreateFontString()
            local t = Text()
            self.created[#self.created + 1] = t
            return t
        end
        local uf = { alpha = 1, points = "all", healthBar = bar }
        function uf:SetAlpha(a) self.alpha = a end
        function uf:ClearAllPoints() self.points = "" end
        function uf:SetAllPoints() self.points = "all" end
        function uf:SetPoint(point, _, _, x, y)
            self.points = self.points .. point .. "(" .. x .. "," .. y .. ")"
        end
        env.plates[unit] = { UnitFrame = uf, IsForbidden = function() return false end }
        env.fire("NAME_PLATE_UNIT_ADDED", unit)
        return uf
    end
    G.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }
    G.UnitIsFriend = function(_, unit) return env.units[unit].friend end
    -- Evaluates the addon's curve at 1 (full health) or 0.5 (hurt), exact points only.
    G.C_CurveUtil = { CreateCurve = function()
        local points = {}
        return { points = points, AddPoint = function(_, x, y) points[x] = y end }
    end }
    G.UnitHealthPercent = function(unit, _, curve)
        assert(curve, "UnitHealthPercent called without the curve")
        if env.units[unit].health == "full" then return curve.points[1] end
        return curve.points[0]
    end

    -- Engaged check. env.units[unit] may also carry: player (an enemy player),
    -- isTarget (your target), threat (set of group tokens on its threat list)
    -- and target (the group token it targets).
    env.group = { raid = false, size = 0 }
    G.IsInRaid = function() return env.group.raid end
    G.GetNumGroupMembers = function() return env.group.size end
    G.GetNumSubgroupMembers = function() return env.group.size end
    G.UnitIsPlayer = function(unit) return env.units[unit].player == true end
    local function TargetOf(token)
        local mob = token:match("^(.-)target$")
        return mob and env.units[mob] and env.units[mob].target
    end
    G.UnitIsUnit = function(a, b)
        if b == "target" then return env.units[a].isTarget == true end
        return (TargetOf(a) or a) == b
    end
    G.UnitThreatSituation = function(member, mob)
        local threat = env.units[mob].threat
        return threat and threat[member]
    end
    -- env.units[unit].group: "party" or "raid" for a group member.
    G.UnitInParty = function(unit) return env.units[unit].group == "party" end
    G.UnitInRaid = function(unit) if env.units[unit].group == "raid" then return 1 end end
    G.UnitPlayerOrPetInParty = function(token) return (TargetOf(token) or ""):match("^party") ~= nil end
    G.UnitPlayerOrPetInRaid = function(token) return (TargetOf(token) or ""):match("^raid") ~= nil end

    -- Missing health: env.units[unit].missing, plain numbers here.
    G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    G.UnitHealthMissing = function(unit) return env.units[unit].missing or 0 end
    G.AbbreviateNumbers = function(n) return "abbr" .. n end
    env.addons = {}
    G.C_AddOns = { IsAddOnLoaded = function(name) return env.addons[name] == true end }

    local ns = {}
    for _, file in ipairs(ADDON_FILES) do
        local chunk = assert(loadfile(file))
        setfenv(chunk, G)
        chunk(ADDON_NAME, ns)
    end

    env.loaded = true
    env.frame = frame
    env.globals = G
    function env.fire(event, ...)
        if not frame.events[event] then return end
        frame.scripts.OnEvent(frame, event, ...)
    end
    -- Runs a slash command the way the chat box does: look up SLASH_<KEY>n.
    function env.slash(text)
        local cmd, rest = text:match("^(%S+)%s*(.-)$")
        for key, fn in pairs(G.SlashCmdList) do
            local i = 1
            while rawget(G, "SLASH_" .. key .. i) do
                if rawget(G, "SLASH_" .. key .. i) == cmd then return fn(rest) end
                i = i + 1
            end
        end
        error("unknown slash command " .. cmd, 2)
    end
    env.fire("ADDON_LOADED", "SomeOtherAddon")
    env.fire("ADDON_LOADED", ADDON_NAME)
    return env
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function writes(env) return table.concat(env.writes, ",") end

local ON = "nameplateShowEnemies=1,nameplateShowFriendlyPlayers=1"
local OFF = "nameplateShowEnemies=0,nameplateShowFriendlyPlayers=0"

-- A saved table from v0.2.0: the health and sides options off.
local function Old(t)
    t = t or {}
    for _, key in ipairs({ "fadeFull", "showHurt", "sides" }) do
        if t[key] == nil then t[key] = false end
    end
    return t
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

test("registers the combat events it handles", function()
    local env = Load()
    eq(env.frame.events.PLAYER_ENTERING_WORLD, true, "PLAYER_ENTERING_WORLD")
    eq(env.frame.events.PLAYER_REGEN_DISABLED, true, "PLAYER_REGEN_DISABLED")
    eq(env.frame.events.PLAYER_REGEN_ENABLED, true, "PLAYER_REGEN_ENABLED")
end)

test("defines only its saved variable and slash commands as globals", function()
    local env = Load()
    local stubs = { UnitInParty = 1, UnitInRaid = 1, STANDARD_TEXT_FONT = 1, UnitHealthMissing = 1, AbbreviateNumbers = 1, C_AddOns = 1, IsInRaid = 1, GetNumGroupMembers = 1, GetNumSubgroupMembers = 1, UnitIsPlayer = 1, UnitIsUnit = 1, UnitThreatSituation = 1, UnitPlayerOrPetInParty = 1, UnitPlayerOrPetInRaid = 1, C_NamePlate = 1, UnitIsFriend = 1, C_CurveUtil = 1, UnitHealthPercent = 1, C_Console = 1, CreateFrame = 1, InCombatLockdown = 1, C_CVar = 1, SetCVar = 1, GetCVar = 1, print = 1, SlashCmdList = 1 }
    local names = {}
    for k in pairs(env.globals) do
        if not stubs[k] and k ~= "DynamicDisplayNameplateDB" and not k:match("^SLASH_DDN") then
            names[#names + 1] = k
        end
    end
    eq(table.concat(names, ","), "", "new globals")
end)

test("every slash command uses the /ddn- prefix", function()
    local env = Load()
    local n = 0
    for k, v in pairs(env.globals) do
        if k:match("^SLASH_") then
            n = n + 1
            assert(v:match("^/ddn%-%l+$"), k .. " = " .. v)
        end
    end
    eq(n, 12, "slash commands")
end)

test("every option but engaged is on by default on a fresh install", function()
    local env = Load()
    for _, key in ipairs({ "enemies", "friends", "fadeFull", "showHurt", "sides" }) do
        eq(env.globals.DynamicDisplayNameplateDB[key], true, "saved " .. key)
    end
    eq(env.globals.DynamicDisplayNameplateDB.engaged, false, "saved engaged")
    eq(env.globals.DynamicDisplayNameplateDB.deficit, false, "saved deficit")
    eq(env.globals.DynamicDisplayNameplateDB.groupOnly, false, "saved groupOnly")
end)

test("a saved table from before engaged gains it, off", function()
    local env = Load({ saved = Old() })
    eq(env.globals.DynamicDisplayNameplateDB.engaged, false, "saved engaged")
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", false)
    eq(uf.alpha, 1, "idle enemy while engaged is off")
end)

test("a saved table from v0.1.0 (friends only) gains the other options, on", function()
    local env = Load({ saved = { friends = false } })
    eq(env.globals.DynamicDisplayNameplateDB.enemies, true, "saved enemies")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "saved friends")
    eq(env.globals.DynamicDisplayNameplateDB.fadeFull, true, "saved fadeFull")
end)

test("a saved enemies off setting leaves enemy plates alone", function()
    local env = Load({ saved = Old({ enemies = false }) })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "nameplateShowFriendlyPlayers=1,nameplateShowFriendlyPlayers=0", "writes")
end)

test("a saved off setting survives a reload", function()
    local env = Load({ saved = Old({ friends = false }) })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), "nameplateShowEnemies=1", "writes")
end)

test("entering combat shows enemy and friendly plates", function()
    local env = Load({ saved = Old() })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), ON, "writes")
end)

test("leaving combat hides enemy and friendly plates", function()
    local env = Load({ saved = Old() })
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF, "writes")
end)

test("login out of combat hides enemy and friendly plates", function()
    local env = Load({ saved = Old() })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(writes(env), OFF, "writes")
end)

test("login during combat lockdown writes nothing", function()
    local env = Load({ saved = Old(), lockdown = true })
    env.fire("PLAYER_ENTERING_WORLD", false, true)
    eq(writes(env), "", "writes")
end)

test("no event writes during combat lockdown", function()
    local env = Load({ saved = Old(), lockdown = true })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "", "writes")
end)

test("a full fight turns plates on then off", function()
    local env = Load({ saved = Old() })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF .. "," .. ON .. "," .. OFF, "writes")
end)

test("falls back to global SetCVar without C_CVar", function()
    local env = Load({ saved = Old(), noCCVar = true })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), ON, "writes")
end)

test("a write that raises warns once per CVar and never errors", function()
    local env = Load({ saved = Old(), setError = "blocked" })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    env.fire("PLAYER_REGEN_DISABLED")
    eq(#env.printed, 2, "warnings printed")
    assert(env.printed[1]:find("Dynamic Display Nameplate", 1, true), "warning names the addon: " .. env.printed[1])
    assert(env.printed[1]:find("blocked", 1, true), "warning includes the error: " .. env.printed[1])
    assert(env.printed[2]:find("nameplateShowFriendlyPlayers", 1, true), "warning names the CVar: " .. env.printed[2])
end)

test("a write that returns false warns once per CVar", function()
    local env = Load({ saved = Old(), setReturn = false })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 2, "warnings printed")
end)

test("a CVar the client doesn't have is skipped with one warning", function()
    local env = Load({ saved = Old(), missing = "nameplateShowFriendlyPlayers" })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "nameplateShowEnemies=1,nameplateShowEnemies=0", "writes")
    eq(#env.printed, 1, "warnings printed")
    assert(env.printed[1]:find("nameplateShowFriendlyPlayers", 1, true), "warning names the CVar: " .. env.printed[1])
end)

test("successful writes print nothing", function()
    local env = Load({ saved = Old() })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 0, "messages printed")
end)

test("/ddn-friends toggles, saves, and stops managing friendly plates", function()
    local env = Load({ saved = Old() })
    env.slash("/ddn-friends")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "saved friends")
    eq(writes(env), "nameplateShowEnemies=0", "turning off leaves friendly plates alone")
    env.writes = {}
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "nameplateShowEnemies=1,nameplateShowEnemies=0", "writes")
end)

test("/ddn-friends on hides friendly plates right away out of combat", function()
    local env = Load({ saved = Old({ friends = false }) })
    env.slash("/ddn-friends on")
    eq(env.globals.DynamicDisplayNameplateDB.friends, true, "saved friends")
    eq(writes(env), OFF, "writes")
end)

test("/ddn-friends on during combat lockdown waits for the fight to end", function()
    local env = Load({ saved = Old({ friends = false }), lockdown = true })
    env.slash("/ddn-friends on")
    eq(writes(env), "", "writes")
    env.lockdown = false
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF, "writes")
end)

test("/ddn-friends off and junk arguments", function()
    local env = Load({ saved = Old() })
    env.slash("/ddn-friends OFF")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "after OFF")
    env.slash("/ddn-friends off")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "off is not a toggle")
    env.slash("/ddn-friends maybe")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "junk changes nothing")
    assert(env.printed[#env.printed]:find("usage", 1, true), "junk prints usage")
end)

test("/ddn-status shows the setting, live values and last writes", function()
    local env = Load({ saved = Old(), missing = "nameplateShowFriendlyPlayers" })
    env.fire("PLAYER_REGEN_ENABLED")
    env.printed = {}
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("out of combat", 1, true), out)
    assert(out:find("enemy plates managed: nameplateShowEnemies = 0 (addon last wrote 0)", 1, true), out)
    assert(out:find("friendly player plates managed: nameplateShowFriendlyPlayers = missing (addon last wrote nothing)", 1, true), out)
    eq(writes(env), "nameplateShowEnemies=0", "status writes nothing")
    local saved = env.globals.DynamicDisplayNameplateDB.lastStatus
    eq(#saved, #env.printed, "every line saved")
    eq(saved[2], env.printed[2], "same lines")
end)

test("/ddn-status lists other nameplateShow CVars when the client can enumerate them", function()
    local env = Load({ saved = Old(), console = { "nameplateShowEnemies", "nameplateShowFriendlyNPCs", "NameplateShowAll", "nameplateMaxDistance" } })
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("other: NameplateShowAll=0, nameplateShowFriendlyNPCs=0", 1, true), out)
    assert(not out:find("nameplateMaxDistance", 1, true), out)
end)

test("/ddn-enemies off stops managing enemy plates; on hides them right away", function()
    local env = Load({ saved = Old() })
    env.slash("/ddn-enemies off")
    eq(env.globals.DynamicDisplayNameplateDB.enemies, false, "saved enemies")
    env.writes = {}
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), "nameplateShowFriendlyPlayers=1", "writes while off")
    env.writes = {}
    env.fire("PLAYER_REGEN_ENABLED")
    env.writes = {}
    env.slash("/ddn-enemies")
    eq(env.globals.DynamicDisplayNameplateDB.enemies, true, "toggled back on")
    eq(writes(env), OFF, "writes when turned on")
    env.slash("/ddn-enemies nope")
    assert(env.printed[#env.printed]:find("usage: /ddn-enemies", 1, true), env.printed[#env.printed])
end)

test("/ddn-watch prints setting changes until run again", function()
    local env = Load({ saved = Old() })
    env.slash("/ddn-watch")
    local watcher = env.frames[2]
    eq(watcher.events.CVAR_UPDATE, true, "watching")
    watcher.scripts.OnEvent(watcher, "CVAR_UPDATE", "nameplateShowFriends", "1")
    assert(env.printed[#env.printed]:find("nameplateShowFriends = 1", 1, true), env.printed[#env.printed])
    env.slash("/ddn-watch")
    eq(watcher.events.CVAR_UPDATE, nil, "stopped")
    env.slash("/ddn-watch")
    eq(#env.frames, 2, "reuses its frame")
end)

test("/ddn-help lists every command", function()
    local env = Load({ saved = Old() })
    env.slash("/ddn-help")
    local out = table.concat(env.printed, "\n")
    for k, v in pairs(env.globals) do
        if k:match("^SLASH_") then
            assert(out:find(v, 1, true), "help mentions " .. v)
        end
    end
end)

test("show hurt keeps friendly plates on out of combat and hides full-health ones", function()
    local env = Load({ saved = Old({ showHurt = true }) })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(writes(env), "nameplateShowEnemies=0,nameplateShowFriendlyPlayers=1", "writes out of combat")
    local full = env.addPlate("nameplate1", true, "full")
    local hurt = env.addPlate("nameplate2", true, "hurt")
    eq(full.alpha, 0, "full-health friend out of combat")
    eq(hurt.alpha, 1, "hurt friend out of combat")
    env.fire("PLAYER_REGEN_DISABLED")
    eq(full.alpha, 1, "full-health friend in combat without fadeFull")
end)

test("fade full: full-health friends faint in combat, hidden out of it, solid once hurt", function()
    local env = Load({ saved = Old({ fadeFull = true }) })
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", true, "full")
    eq(uf.alpha, 0.3, "full health in combat")
    env.units.nameplate1.health = "hurt"
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(uf.alpha, 1, "after taking damage")
    env.units.nameplate1.health = "full"
    env.fire("PLAYER_REGEN_ENABLED")
    eq(uf.alpha, 0, "full health out of combat")
end)

test("fade full never fades enemy plates", function()
    local env = Load()
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", false, "full")
    eq(uf.alpha, 1, "enemy at full health")
end)

test("turning fade full off puts faded plates back", function()
    local env = Load({ saved = Old({ fadeFull = true }) })
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", true, "full")
    env.slash("/ddn-fadefull off")
    eq(uf.alpha, 1, "alpha after off")
    eq(env.globals.DynamicDisplayNameplateDB.fadeFull, false, "saved")
end)

test("a plate reused for another unit is updated on add", function()
    local env = Load({ saved = Old({ fadeFull = true }) })
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", true, "full")
    eq(uf.alpha, 0.3, "friend at full")
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    env.units.nameplate1 = { friend = false, health = "full" }
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(uf.alpha, 1, "enemy on the same frame")
end)

test("secret friend state still counts party and raid members as friends", function()
    local env = Load({ saved = Old({ deficit = true }) })
    local secret = {}
    env.globals.issecretvalue = function(v) return v == secret end
    env.globals.UnitIsFriend = function() return secret end
    local member = env.addPlate("nameplate1", true)
    env.units.nameplate1.group = "raid"
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(member.healthBar.created[1].alpha, 1, "member gets missing health")
    local other = env.addPlate("nameplate2", true)
    eq(#other.healthBar.created, 0, "non-member left alone")
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("nameplate1: friend=secret player=false party=false raid=1 -> friendly", 1, true), out)
    assert(out:find("nameplate2: friend=secret player=false party=false raid=nil -> enemy", 1, true), out)
end)

test("secret friend state counts as not a friend", function()
    local env = Load({ saved = Old({ fadeFull = true }) })
    env.globals.issecretvalue = function() return true end
    local uf = env.addPlate("nameplate1", true, "full")
    eq(uf.alpha, 1, "alpha")
end)

test("a failing health API warns once instead of erroring", function()
    local env = Load({ saved = Old({ fadeFull = true }) })
    env.globals.UnitHealthPercent = nil
    env.addPlate("nameplate1", true, "full")
    env.addPlate("nameplate2", true, "full")
    eq(#env.printed, 1, "warnings")
    assert(env.printed[1]:find("fade full-health plates", 1, true), env.printed[1])
end)

test("sides moves friendly plates left and enemy plates right, and turns stacking on", function()
    local env = Load({ saved = Old({ sides = true }) })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(writes(env), OFF .. ",nameplateMotion=1", "writes")
    eq(env.globals.DynamicDisplayNameplateDB.motionBefore, "0", "old stacking value saved")
    local friend = env.addPlate("nameplate1", true)
    local enemy = env.addPlate("nameplate2", false)
    eq(friend.points, "TOPLEFT(-60,0)BOTTOMRIGHT(-60,0)", "friend anchors")
    eq(enemy.points, "TOPLEFT(60,0)BOTTOMRIGHT(60,0)", "enemy anchors")
end)

test("turning sides off restores anchors and the old stacking value", function()
    local env = Load({ saved = Old({ sides = true }), values = { nameplateMotion = "0" } })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    local uf = env.addPlate("nameplate1", true)
    env.writes = {}
    env.slash("/ddn-sides off")
    eq(uf.points, "all", "anchors")
    eq(writes(env), OFF .. ",nameplateMotion=0", "writes")
    eq(env.globals.DynamicDisplayNameplateDB.motionBefore, nil, "saved value cleared")
end)

test("sides leaves stacking alone when it was already on", function()
    local env = Load({ saved = Old({ sides = true }), values = { nameplateMotion = "1" } })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.slash("/ddn-sides off")
    eq(writes(env), OFF .. "," .. OFF, "writes")
end)

test("sides without nameplateMotion still shifts plates and warns about nothing", function()
    local env = Load({ saved = Old({ sides = true }), missing = "nameplateMotion" })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    local uf = env.addPlate("nameplate1", true)
    eq(uf.points, "TOPLEFT(-60,0)BOTTOMRIGHT(-60,0)", "anchors")
    eq(writes(env), OFF, "writes")
    env.slash("/ddn-sides off")
    eq(#env.printed, 1, "only the toggle's own message")
end)

test("plates without sides are never re-anchored", function()
    local env = Load({ saved = Old() })
    local uf = env.addPlate("nameplate1", true)
    eq(uf.points, "all", "anchors")
end)

test("engaged hides idle enemy NPCs and shows them once they fight you", function()
    local env = Load({ saved = Old({ engaged = true }) })
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", false)
    eq(uf.alpha, 0, "idle mob")
    env.units.nameplate1.threat = { player = 0 }
    env.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(uf.alpha, 1, "you on its threat list")
    env.units.nameplate1.threat = nil
    env.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(uf.alpha, 0, "dropped off its threat list")
end)

test("engaged shows your target and mobs targeting you or your pet", function()
    local env = Load({ saved = Old({ engaged = true }) })
    local uf = env.addPlate("nameplate1", false)
    env.units.nameplate1.isTarget = true
    env.fire("PLAYER_TARGET_CHANGED")
    eq(uf.alpha, 1, "your target")
    env.units.nameplate1.isTarget = false
    env.fire("PLAYER_TARGET_CHANGED")
    eq(uf.alpha, 0, "no longer your target")
    env.units.nameplate1.target = "pet"
    env.fire("UNIT_TARGET", "nameplate1")
    eq(uf.alpha, 1, "targeting your pet")
end)

test("engaged counts party and raid members and their pets", function()
    local env = Load({ saved = Old({ engaged = true }) })
    local uf = env.addPlate("nameplate1", false)
    env.units.nameplate1.threat = { party2 = 1 }
    env.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(uf.alpha, 0, "party2 doesn't exist yet")
    env.group.size = 2
    env.fire("GROUP_ROSTER_UPDATE")
    eq(uf.alpha, 1, "party2 on its threat list")
    env.group.raid, env.group.size = true, 10
    env.units.nameplate1.threat = { raidpet7 = 0 }
    env.fire("GROUP_ROSTER_UPDATE")
    eq(uf.alpha, 1, "a raid member's pet on its threat list")
    env.units.nameplate1.threat = nil
    env.units.nameplate1.target = "raid3"
    env.fire("UNIT_TARGET", "nameplate1")
    eq(uf.alpha, 1, "targeting a raid member")
end)

test("engaged never hides enemy players or friendly plates", function()
    local env = Load({ saved = Old({ engaged = true }) })
    local player = env.addPlate("nameplate1", false)
    env.units.nameplate1.player = true
    env.fire("UNIT_FACTION", "nameplate1")
    eq(player.alpha, 1, "enemy player")
    local friend = env.addPlate("nameplate2", true, "hurt")
    eq(friend.alpha, 1, "friend")
end)

test("engaged keeps a plate shown when a secret value hides the answer", function()
    local env = Load({ saved = Old({ engaged = true }) })
    local secret = {}
    env.globals.issecretvalue = function(v) return v == secret end
    env.globals.UnitThreatSituation = function() return secret end
    local uf = env.addPlate("nameplate1", false)
    eq(uf.alpha, 1, "unknown stays shown")
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("fighting your group: 0, not fighting: 0, unknown: 1", 1, true), out)
end)

test("/ddn-status counts enemy plates fighting and not fighting your group", function()
    local env = Load({ saved = Old() })
    env.addPlate("nameplate1", false)
    env.addPlate("nameplate2", false)
    env.units.nameplate2.threat = { player = 3 }
    env.addPlate("nameplate3", true)
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("fighting your group: 1, not fighting: 1, unknown: 0", 1, true), out)
end)

test("turning engaged off puts hidden plates back", function()
    local env = Load({ saved = Old({ engaged = true }) })
    local uf = env.addPlate("nameplate1", false)
    eq(uf.alpha, 0, "hidden")
    env.slash("/ddn-engaged off")
    eq(uf.alpha, 1, "after off")
    eq(env.globals.DynamicDisplayNameplateDB.engaged, false, "saved")
end)

test("a hidden enemy plate reused for a friend gets the friend's fade", function()
    local env = Load({ saved = Old({ engaged = true, fadeFull = true }) })
    env.fire("PLAYER_REGEN_DISABLED")
    local uf = env.addPlate("nameplate1", false)
    eq(uf.alpha, 0, "idle enemy")
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    env.units.nameplate1 = { friend = true, health = "hurt" }
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(uf.alpha, 1, "hurt friend on the same frame")
end)

test("a failing threat API warns once and leaves plates shown", function()
    local env = Load({ saved = Old({ engaged = true }) })
    env.globals.UnitThreatSituation = nil
    local a = env.addPlate("nameplate1", false)
    env.addPlate("nameplate2", false)
    eq(a.alpha, 1, "alpha")
    eq(#env.printed, 1, "warnings")
    assert(env.printed[1]:find("decide which plates to hide", 1, true), env.printed[1])
end)

local function blizzardTexts(uf)
    local bar = uf.healthBar
    return ("%s,%s,%s"):format(bar.LeftText.alpha, bar.RightText.alpha, bar.TextString.alpha)
end

test("deficit off leaves health texts fully Blizzard's", function()
    local env = Load()
    local uf = env.addPlate("nameplate1", true, "hurt")
    eq(#uf.healthBar.created, 0, "nothing created")
    eq(blizzardTexts(uf), "1,1,1", "Blizzard's texts")
end)

test("deficit shows missing health on friendly plates in Blizzard's spot and font", function()
    local env = Load({ saved = Old({ deficit = true }) })
    local uf = env.addPlate("nameplate1", true, "hurt")
    env.units.nameplate1.missing = 1234
    env.fire("UNIT_HEALTH", "nameplate1")
    local text = uf.healthBar.created[1]
    eq(#uf.healthBar.created, 1, "one text")
    eq(text.text, "-abbr1234", "text")
    eq(text.alpha, 1, "shown")
    eq(table.concat(text.fontArgs, ","), "Fonts\\BLIZZ.TTF,9,OUTLINE", "font")
    eq(text.point, "RIGHT RIGHT", "anchor")
    eq(blizzardTexts(uf), "0,0,0", "Blizzard's texts hidden")
    env.units.nameplate1.missing = 0
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(text.text, "-abbr0", "-0 at full health")
end)

test("deficit leaves enemy plates alone and gives a reused frame back to Blizzard", function()
    local env = Load({ saved = Old({ deficit = true }) })
    local enemy = env.addPlate("nameplate1", false)
    eq(#enemy.healthBar.created, 0, "enemy: nothing created")
    eq(blizzardTexts(enemy), "1,1,1", "enemy: Blizzard's texts")
    local uf = env.addPlate("nameplate2", true)
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    env.units.nameplate2 = { friend = false, health = "full" }
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    eq(uf.healthBar.created[1].alpha, 0, "our text hidden")
    eq(blizzardTexts(uf), "1,1,1", "Blizzard's texts back")
    env.units.nameplate2.friend = true
    env.fire("UNIT_FACTION", "nameplate2")
    eq(#uf.healthBar.created, 1, "text made once per frame")
end)

test("turning deficit off gives Blizzard its number back", function()
    local env = Load({ saved = Old({ deficit = true }) })
    local uf = env.addPlate("nameplate1", true)
    env.slash("/ddn-deficit off")
    eq(uf.healthBar.created[1].alpha, 0, "our text hidden")
    eq(blizzardTexts(uf), "1,1,1", "Blizzard's texts back")
    eq(env.globals.DynamicDisplayNameplateDB.deficit, false, "saved")
end)

test("deficit falls back to the standard font and skips plates without a bar", function()
    local env = Load({ saved = Old({ deficit = true }) })
    local uf = env.addPlate("nameplate1", true)
    uf.healthBar = nil
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(#env.printed, 0, "no bar: no warnings")
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    env.units.nameplate1 = { friend = false, health = "full" }
    local plain = env.addPlate("nameplate2", false)
    plain.healthBar.RightText, plain.healthBar.TextString = nil, nil
    env.units.nameplate2.friend = true
    env.fire("UNIT_FACTION", "nameplate2")
    eq(table.concat(plain.healthBar.created[1].fontArgs, ","), "Fonts\\FRIZQT__.TTF,10,OUTLINE", "standard font")
    eq(#env.printed, 0, "no warnings")
end)

test("deficit steps aside while Deficit Plates is still enabled", function()
    local env = Load({ saved = Old({ deficit = true }) })
    env.addons.DeficitPlates = true
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    assert(env.printed[#env.printed]:find("Deficit Plates is still enabled", 1, true), env.printed[#env.printed])
    local uf = env.addPlate("nameplate1", true)
    eq(#uf.healthBar.created, 0, "left to Deficit Plates")
    eq(blizzardTexts(uf), "1,1,1", "Blizzard's texts untouched")
end)

test("a failing missing-health API warns once instead of erroring", function()
    local env = Load({ saved = Old({ deficit = true }) })
    env.globals.UnitHealthMissing = nil
    env.addPlate("nameplate1", true)
    env.addPlate("nameplate2", true)
    eq(#env.printed, 1, "warnings")
    assert(env.printed[1]:find("show missing health", 1, true), env.printed[1])
end)

test("/ddn-status reports missing health and stacking CVars", function()
    local env = Load({ saved = Old({ deficit = true }), console = { "nameplateStackFriendly", "nameplateOverlapV", "nameplateMaxDistance" } })
    env.addPlate("nameplate1", true)
    env.addPlate("nameplate2", false)
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("friendly plates with missing health: 1 (UnitHealthMissing: yes, AbbreviateNumbers: yes, Deficit Plates loaded: no)", 1, true), out)
    assert(out:find("other: nameplateOverlapV=0, nameplateStackFriendly=0", 1, true), out)
end)

-- A friendly player's plate, optionally in the group.
local function addFriend(env, unit, group, health)
    local uf = env.addPlate(unit, true, health)
    env.units[unit].player = true
    env.units[unit].group = group
    env.fire("UNIT_FACTION", unit)
    return uf
end

test("group only hides friendly players outside your party or raid", function()
    local env = Load({ saved = Old({ groupOnly = true }) })
    local stranger = addFriend(env, "nameplate1")
    local party = addFriend(env, "nameplate2", "party")
    local raid = addFriend(env, "nameplate3", "raid")
    local npc = env.addPlate("nameplate4", true)
    eq(stranger.alpha, 0, "stranger")
    eq(party.alpha, 1, "party member")
    eq(raid.alpha, 1, "raid member")
    eq(npc.alpha, 1, "friendly NPC")
    env.units.nameplate1.group = "party"
    env.fire("GROUP_ROSTER_UPDATE")
    eq(stranger.alpha, 1, "joined the group")
end)

test("group only is off by default and turns off cleanly", function()
    local env = Load({ saved = Old() })
    local uf = addFriend(env, "nameplate1")
    eq(uf.alpha, 1, "off: stranger shown")
    env.slash("/ddn-group on")
    eq(uf.alpha, 0, "on: stranger hidden")
    env.slash("/ddn-group off")
    eq(uf.alpha, 1, "off again")
end)

test("group only beats the full-health fade; members still fade", function()
    local env = Load({ saved = Old({ groupOnly = true, fadeFull = true }) })
    env.fire("PLAYER_REGEN_DISABLED")
    local stranger = addFriend(env, "nameplate1", nil, "full")
    local member = addFriend(env, "nameplate2", "party", "full")
    eq(stranger.alpha, 0, "stranger hidden")
    eq(member.alpha, 0.3, "member faded")
end)

test("group only keeps a plate shown when a secret value hides the answer", function()
    local env = Load({ saved = Old({ groupOnly = true }) })
    local secret = {}
    env.globals.issecretvalue = function(v) return v == secret end
    env.globals.UnitInParty = function() return secret end
    env.globals.UnitInRaid = function() return secret end
    local uf = addFriend(env, "nameplate1")
    eq(uf.alpha, 1, "unknown stays shown")
end)

test("forbidden plates are left alone and counted in /ddn-status", function()
    local env = Load({ saved = Old({ deficit = true, groupOnly = true }) })
    local uf = env.addPlate("nameplate1", true)
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    env.plates.nameplate1.IsForbidden = function() return true end
    uf.alpha = 1
    uf.healthBar.created = {}
    env.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    eq(#uf.healthBar.created, 0, "nothing created")
    env.slash("/ddn-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("plates shown: 0, friendly: 0, off limits to addons: 1", 1, true), out)
    env.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    env.slash("/ddn-status")
    out = table.concat(env.globals.DynamicDisplayNameplateDB.lastStatus, "\n")
    assert(out:find("off limits to addons: 0", 1, true), out)
    env.fire("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "nameplate4")
    env.fire("FORBIDDEN_NAME_PLATE_UNIT_ADDED", "nameplate5")
    env.fire("FORBIDDEN_NAME_PLATE_UNIT_REMOVED", "nameplate5")
    env.slash("/ddn-status")
    out = table.concat(env.globals.DynamicDisplayNameplateDB.lastStatus, "\n")
    assert(out:find("off limits to addons: 1", 1, true), out)
end)

test("/ddn-options says so when the panel isn't loaded", function()
    local env = Load()
    env.slash("/ddn-options")
    assert(env.printed[#env.printed]:find("options panel", 1, true), env.printed[#env.printed])
end)

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print("PASS  " .. t.name)
    else
        failed = failed + 1
        print("FAIL  " .. t.name .. "\n      " .. tostring(err))
    end
end
print(("%d passed, %d failed"):format(#tests - failed, failed))
os.exit(failed == 0 and 0 or 1)
