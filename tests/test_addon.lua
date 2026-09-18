-- Loads the addon into a stubbed WoW API and checks its CVar writes.
-- Run from the repo root: luajit tests/test_addon.lua

local ADDON_FILE = "DynamicDisplayNameplate.lua"
local ADDON_NAME = "DynamicDisplayNameplate"

-- opts.lockdown   InCombatLockdown() result (default false)
-- opts.noCCVar    leave C_CVar undefined so the addon must use global SetCVar
-- opts.setError   make every CVar write raise this error
-- opts.setReturn  value every CVar write returns (default true)
local function Load(opts)
    opts = opts or {}
    local env = { writes = {}, printed = {}, lockdown = opts.lockdown or false }

    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
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

    local chunk = assert(loadfile(ADDON_FILE))
    setfenv(chunk, G)
    chunk(ADDON_NAME, {})

    env.frame = frame
    env.globals = G
    function env.fire(event, ...)
        if not frame.events[event] then return end
        frame.scripts.OnEvent(frame, event, ...)
    end
    return env
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what, tostring(expected), tostring(actual)), 2)
    end
end

local function writes(env) return table.concat(env.writes, ",") end

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

test("registers the three events it handles", function()
    local env = Load()
    eq(env.frame.events.PLAYER_ENTERING_WORLD, true, "PLAYER_ENTERING_WORLD")
    eq(env.frame.events.PLAYER_REGEN_DISABLED, true, "PLAYER_REGEN_DISABLED")
    eq(env.frame.events.PLAYER_REGEN_ENABLED, true, "PLAYER_REGEN_ENABLED")
end)

test("defines no globals", function()
    local env = Load()
    local names = {}
    for k in pairs(env.globals) do
        if k ~= "CreateFrame" and k ~= "InCombatLockdown" and k ~= "C_CVar"
            and k ~= "SetCVar" and k ~= "print" then
            names[#names + 1] = k
        end
    end
    eq(table.concat(names, ","), "", "new globals")
end)

test("entering combat shows enemy plates", function()
    local env = Load()
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), "nameplateShowEnemies=1", "writes")
end)

test("leaving combat hides enemy plates", function()
    local env = Load()
    env.fire("PLAYER_REGEN_ENABLED")
    eq(writes(env), "nameplateShowEnemies=0", "writes")
end)

test("login out of combat hides enemy plates", function()
    local env = Load()
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(writes(env), "nameplateShowEnemies=0", "writes")
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
    eq(writes(env), "nameplateShowEnemies=0,nameplateShowEnemies=1,nameplateShowEnemies=0", "writes")
end)

test("falls back to global SetCVar without C_CVar", function()
    local env = Load({ noCCVar = true })
    env.fire("PLAYER_REGEN_DISABLED")
    eq(writes(env), "nameplateShowEnemies=1", "writes")
end)

test("a write that raises warns once and never errors", function()
    local env = Load({ setError = "blocked" })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    env.fire("PLAYER_REGEN_DISABLED")
    eq(#env.printed, 1, "warnings printed")
    assert(env.printed[1]:find("Dynamic Display Nameplate", 1, true), "warning names the addon: " .. env.printed[1])
    assert(env.printed[1]:find("blocked", 1, true), "warning includes the error: " .. env.printed[1])
end)

test("a write that returns false warns once", function()
    local env = Load({ setReturn = false })
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 1, "warnings printed")
end)

test("successful writes print nothing", function()
    local env = Load()
    env.fire("PLAYER_ENTERING_WORLD", true, false)
    env.fire("PLAYER_REGEN_DISABLED")
    env.fire("PLAYER_REGEN_ENABLED")
    eq(#env.printed, 0, "messages printed")
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
