-- Loads the addon into a stubbed WoW API and checks its CVar writes.
-- Run from the repo root: luajit tests/test_addon.lua

local ADDON_FILE = "DynamicDisplayNameplate.lua"
local ADDON_NAME = "DynamicDisplayNameplate"

-- opts.lockdown   InCombatLockdown() result (default false)
-- opts.noCCVar    leave C_CVar undefined so the addon must use global SetCVar
-- opts.setError   make every CVar write raise this error
-- opts.setReturn  value every CVar write returns (default true)
-- opts.saved      DynamicDisplayNameplateDB as left by a previous session
local function Load(opts)
    opts = opts or {}
    local env = { writes = {}, printed = {}, lockdown = opts.lockdown or false }

    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end

    local function set(name, value)
        if opts.setError then error(opts.setError, 0) end
        env.writes[#env.writes + 1] = name .. "=" .. value
        if opts.setReturn ~= nil then return opts.setReturn end
        return true
    end

    local G = setmetatable({}, { __index = _G })
    G.CreateFrame = function() return frame end
    G.InCombatLockdown = function() return env.lockdown end
    if opts.noCCVar then
        G.SetCVar = set
    else
        G.C_CVar = { SetCVar = set }
        G.SetCVar = function() error("global SetCVar used while C_CVar exists", 0) end
    end
    G.print = function(...) env.printed[#env.printed + 1] = table.concat({ ... }, " ") end
    G.SlashCmdList = {}
    G.DynamicDisplayNameplateDB = opts.saved

    local chunk = assert(loadfile(ADDON_FILE))
    setfenv(chunk, G)
    chunk(ADDON_NAME, {})

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

local ON = "nameplateShowEnemies=1,nameplateShowFriends=1"
local OFF = "nameplateShowEnemies=0,nameplateShowFriends=0"

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
    local stubs = { CreateFrame = 1, InCombatLockdown = 1, C_CVar = 1, SetCVar = 1, print = 1, SlashCmdList = 1 }
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
    eq(n, 2, "slash commands")
end)

test("friendly plates are managed by default on a fresh install", function()
    local env = Load()
    eq(env.globals.DynamicDisplayNameplateDB.friends, true, "saved friends")
end)

test("a saved off setting survives a reload", function()
    local env = Load({ saved = { friends = false } })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), "nameplateShowEnemies=1", "writes")
end)

test("entering combat shows enemy and friendly plates", function()
    local env = Load()
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), ON, "writes")
end)

test("leaving combat hides enemy and friendly plates", function()
    local env = Load()
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF, "writes")
end)

test("login out of combat hides enemy and friendly plates", function()
    local env = Load()
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(writes(env), OFF, "writes")
end)

test("login during combat lockdown writes nothing", function()
    local env = Load({ lockdown = true })
    env.fire("PLAYER_ENTERING_WORLD", false, true)
    eq(writes(env), "", "writes")
end)

test("no event writes during combat lockdown", function()
    local env = Load({ lockdown = true })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "", "writes")
end)

test("a full fight turns plates on then off", function()
    local env = Load()
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF .. "," .. ON .. "," .. OFF, "writes")
end)

test("falls back to global SetCVar without C_CVar", function()
    local env = Load({ noCCVar = true })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), ON, "writes")
end)

test("a write that raises warns once per CVar and never errors", function()
    local env = Load({ setError = "blocked" })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    env.fire("PLAYER_REGEN_DISABLED")
    eq(#env.printed, 2, "warnings printed")
    assert(env.printed[1]:find("Dynamic Display Nameplate", 1, true), "warning names the addon: " .. env.printed[1])
    assert(env.printed[1]:find("blocked", 1, true), "warning includes the error: " .. env.printed[1])
    assert(env.printed[2]:find("nameplateShowFriends", 1, true), "warning names the CVar: " .. env.printed[2])
end)

test("a write that returns false warns once per CVar", function()
    local env = Load({ setReturn = false })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 2, "warnings printed")
end)

test("successful writes print nothing", function()
    local env = Load()
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 0, "messages printed")
end)

test("/ddn-friends toggles, saves, and stops managing friendly plates", function()
    local env = Load()
    env.slash("/ddn-friends")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "saved friends")
    eq(writes(env), "", "turning off writes nothing")
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "nameplateShowEnemies=1,nameplateShowEnemies=0", "writes")
end)

test("/ddn-friends on hides friendly plates right away out of combat", function()
    local env = Load({ saved = { friends = false } })
    env.slash("/ddn-friends on")
    eq(env.globals.DynamicDisplayNameplateDB.friends, true, "saved friends")
    eq(writes(env), "nameplateShowFriends=0", "writes")
end)

test("/ddn-friends on during combat lockdown waits for the fight to end", function()
    local env = Load({ saved = { friends = false }, lockdown = true })
    env.slash("/ddn-friends on")
    eq(writes(env), "", "writes")
    env.lockdown = false
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), OFF, "writes")
end)

test("/ddn-friends off and junk arguments", function()
    local env = Load()
    env.slash("/ddn-friends OFF")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "after OFF")
    env.slash("/ddn-friends off")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "off is not a toggle")
    env.slash("/ddn-friends maybe")
    eq(env.globals.DynamicDisplayNameplateDB.friends, false, "junk changes nothing")
    assert(env.printed[#env.printed]:find("usage", 1, true), "junk prints usage")
end)

test("/ddn-help lists every command", function()
    local env = Load()
    env.slash("/ddn-help")
    local out = table.concat(env.printed, "\n")
    for k, v in pairs(env.globals) do
        if k:match("^SLASH_") then
            assert(out:find(v, 1, true), "help mentions " .. v)
        end
    end
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
