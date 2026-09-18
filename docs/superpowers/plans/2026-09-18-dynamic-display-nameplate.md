# Dynamic Display Nameplate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a WoW Forever addon that shows enemy nameplates only in combat. Test it in the local Forever beta client, then release it to CurseForge as `v0.0.1-beta1`.

**Architecture:** One Lua file registers three events on a frame and writes the `nameplateShowEnemies` CVar. The writes happen outside combat lockdown and are wrapped in `pcall`, with a one-time chat warning if a write fails. A LuaJIT test file loads the addon into a stubbed WoW environment. The BigWigs packager builds the zip locally for the in-game test, and a GitHub Action builds and uploads it on a version tag.

**Tech Stack:** Lua 5.1 (WoW), LuaJIT (local tests at `/opt/homebrew/bin/luajit`), luacheck (CI only), BigWigsMods/packager v2, GitHub Actions, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-09-18-dynamic-display-nameplate-design.md`

## Global Constraints

- TOC `## Interface: 16001`. The addon targets WoW Forever only.
- The addon folder and TOC name is `DynamicDisplayNameplate`. The display title is `Dynamic Display Nameplate`.
- The addon writes only the CVar `nameplateShowEnemies`, with values `"1"` and `"0"`.
- The only combat check is `InCombatLockdown()`. Do not call `UnitAffectingCombat`.
- There are no SavedVariables, slash commands, options, or libraries.
- Commits use author `Rubens Lopes <github@rubenslop.es>`, which is already set in the repo's local git config. Do not add a `Co-Authored-By` trailer.
- Repo: `rubens-lopes/DynamicDisplayNameplate` (public).
- First release tag: `v0.0.1-beta1`.
- CurseForge token secret name: `CF_API_TOKEN`.
- Local Forever AddOns folder: `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns`.

---

### Task 1: Addon core (TDD)

**Files:**
- Create: `tests/test_addon.lua`
- Create: `DynamicDisplayNameplate.toc`
- Create: `DynamicDisplayNameplate.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `DynamicDisplayNameplate.lua`, loaded by the TOC with `(addonName, ns)` varargs. It creates one frame, registers `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`, and defines no globals. `tests/test_addon.lua` runs with `luajit tests/test_addon.lua` from the repo root and exits 1 on any failure.

- [ ] **Step 1: Write the failing test**

Create `tests/test_addon.lua`:

```lua
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `luajit tests/test_addon.lua`
Expected: a failure. `loadfile` returns nil and the `assert` reports `cannot open DynamicDisplayNameplate.lua`.

- [ ] **Step 3: Write the TOC and the minimal implementation**

Create `DynamicDisplayNameplate.toc`:

```
## Interface: 16001
## Title: Dynamic Display Nameplate
## Notes: Shows enemy nameplates only while you're in combat.
## Author: Rubens Lopes
## Version: @project-version@
## Category: Combat
## IconTexture: Interface\Icons\Ability_DualWield

DynamicDisplayNameplate.lua
```

Create `DynamicDisplayNameplate.lua`:

```lua
-- Enemy nameplates only while in combat. PLAYER_REGEN_DISABLED fires just
-- before combat lockdown starts and PLAYER_REGEN_ENABLED just after it ends,
-- so both writes happen while the client still accepts them.

local CVAR = "nameplateShowEnemies"
local TITLE = "Dynamic Display Nameplate"

local warned = false

local function SetEnemyPlates(show)
    if InCombatLockdown() then return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local ok, result = pcall(set, CVAR, show and "1" or "0")
    if ok and result ~= false then return end
    if warned then return end
    warned = true
    print(("|cffff8800%s:|r couldn't change enemy nameplates (%s)"):format(TITLE, tostring(result)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
    SetEnemyPlates(event == "PLAYER_REGEN_DISABLED")
end)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `luajit tests/test_addon.lua`
Expected: 12 `PASS` lines, then `12 passed, 0 failed`, with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add DynamicDisplayNameplate.toc DynamicDisplayNameplate.lua tests/test_addon.lua
git commit -m "Add combat-only enemy nameplates with tests"
```

---

### Task 2: Packaging, lint and CI

**Files:**
- Create: `.pkgmeta`
- Create: `.luacheckrc`
- Create: `.gitignore`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: the files from Task 1.
- Produces:
  - A packager config whose zip holds `DynamicDisplayNameplate/` containing `DynamicDisplayNameplate.toc`, `DynamicDisplayNameplate.lua`, `LICENSE` and `CHANGELOG.md`, and nothing else.
  - `release.yml`, which runs on `v*` tags using the secrets `CF_API_TOKEN` and `GITHUB_TOKEN`.

- [ ] **Step 1: Write the config files**

`.pkgmeta`:

```yaml
package-as: DynamicDisplayNameplate

manual-changelog:
  filename: CHANGELOG.md
  markup-type: markdown

ignore:
  - README.md
  - docs
  - media
  - tests
```

`.luacheckrc`:

```lua
std = "lua51"
max_line_length = false
exclude_files = { ".release" }

read_globals = {
    "C_CVar",
    "CreateFrame",
    "InCombatLockdown",
    "SetCVar",
}
```

`.gitignore`:

```
.release/
.env
.DS_Store
.playwright-mcp/
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: nebularg/actions-luacheck@v1
        with:
          args: --no-color
      - name: Install LuaJIT
        run: sudo apt-get update && sudo apt-get install -y luajit
      - name: Unit tests
        run: luajit tests/test_addon.lua
```

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    env:
      CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install LuaJIT
        run: sudo apt-get update && sudo apt-get install -y luajit
      - name: Unit tests
        run: luajit tests/test_addon.lua
      - uses: BigWigsMods/packager@v2
```

- [ ] **Step 2: Write the docs files**

`README.md`:

````markdown
# Dynamic Display Nameplate

A World of Warcraft: Forever addon that shows enemy nameplates only while you're in combat. It's the "combat plates" option from Leatrix Plus on its own, with nothing to configure.

- Entering combat turns enemy nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

If you press V to show nameplates outside combat, they hide again at the end of your next fight. Uninstalling leaves enemy nameplates off; press V to turn them back on.

## Install

Get it from CurseForge, or copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/DynamicDisplayNameplate` for the Forever beta.

## Development

```bash
luajit tests/test_addon.lua
```

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and uploads the build to CurseForge. Tags containing `beta` or `alpha` go up as beta or alpha releases.
````

`CHANGELOG.md`:

```markdown
# Changelog

## v0.0.1-beta1

- First beta for World of Warcraft: Forever. Enemy nameplates show only while you're in combat.
```

`LICENSE`:

```
MIT License

Copyright (c) 2026 Rubens Lopes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Commit, then run a local packager dry run**

The packager reads git state, so commit first:

```bash
git add .pkgmeta .luacheckrc .gitignore .github README.md CHANGELOG.md LICENSE
git commit -m "Add packaging, lint config, CI and release workflows"
```

Then build without uploading. The packager checkout lives in the session scratchpad; clone it again if it's missing:

```bash
PK=/private/tmp/claude-502/-Users-kh-DynamicDisplayNameplate/76718d02-8cd9-4de2-b5d6-a5034b99de08/scratchpad/pk
[ -d "$PK" ] || git clone --depth 1 https://github.com/BigWigsMods/packager.git "$PK"
/opt/homebrew/bin/bash "$PK/release.sh" -d
unzip -l .release/DynamicDisplayNameplate-*.zip
grep -n "Version" .release/DynamicDisplayNameplate/DynamicDisplayNameplate.toc
```

Expected:
- The packager reports game type `forever` and interface 16001.
- The zip lists exactly `DynamicDisplayNameplate/DynamicDisplayNameplate.toc`, `DynamicDisplayNameplate/DynamicDisplayNameplate.lua`, `DynamicDisplayNameplate/LICENSE` and `DynamicDisplayNameplate/CHANGELOG.md`.
- The TOC's `## Version:` line holds a commit-based version instead of `@project-version@`.

If any other file appears in the zip, add it to `.pkgmeta` `ignore`, commit, and rerun.

---

### Task 3: Local in-game test (user gate)

**Files:** none in the repo. This task copies the build into the WoW client.

**Interfaces:**
- Consumes: `.release/DynamicDisplayNameplate/` from Task 2.
- Produces: the user's pass or fail on the in-game checklist. Task 4 does not start until the user reports a pass.

- [ ] **Step 1: Install the local build into the Forever beta**

```bash
ADDONS="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
rm -rf "$ADDONS/DynamicDisplayNameplate"
cp -R .release/DynamicDisplayNameplate "$ADDONS/"
ls -la "$ADDONS/DynamicDisplayNameplate"
```

Expected: the folder contains the `.toc`, `.lua`, `LICENSE` and `CHANGELOG.md`.

- [ ] **Step 2: The user runs the checklist in the Forever beta**

1. Launch the Forever beta and check that *Dynamic Display Nameplate* is enabled in the AddOns list on the character screen.
2. In game: `/console scriptErrors 1`
3. Standing near enemies out of combat, enemy nameplates are hidden.
4. Pull a mob. Enemy nameplates appear as combat starts.
5. Kill the mob or run away. Nameplates hide when combat ends.
6. Pull a mob, `/reload` mid-fight, and finish the fight. Nameplates hide when it ends.
7. Zone into a dungeon and pull a pack. Plates show in combat and hide after.
8. No Lua error popup and no orange "couldn't change enemy nameplates" line in chat.

- [ ] **Step 3: If any check fails**

Collect the failing step, any error text, and the output of `/dump C_CVar.GetCVar("nameplateShowEnemies")` taken in and out of combat. Stop and use superpowers:systematic-debugging before changing code.

---

### Task 4: GitHub repo and CurseForge release

**Files:**
- Modify: `DynamicDisplayNameplate.toc`, adding a `## X-Curse-Project-ID:` line after `## Version:`.

**Interfaces:**
- Consumes:
  - the CurseForge Project ID the user sends after creating the project from `docs/curseforge.md`;
  - the user's pass on the Task 3 checklist;
  - the secret `CF_API_TOKEN`, set by the user.
- Produces: tag `v0.0.1-beta1` on GitHub, a GitHub Release, and a beta file on CurseForge tagged Forever 1.60.1.

- [ ] **Step 1: Add the CurseForge project ID to the TOC**

Insert the line below after `## Version: @project-version@`, using the numeric ID the user sent:

```
## X-Curse-Project-ID: 1234567
```

(`1234567` stands for the user's real ID. Do not commit this sample value.)

```bash
luajit tests/test_addon.lua
git add DynamicDisplayNameplate.toc
git commit -m "Add CurseForge project ID"
```

- [ ] **Step 2: Create the public GitHub repo under rubens-lopes and push**

`gh` currently defaults to `rubens-sindel`. Switch to `rubens-lopes` and stay on it until Step 7. The git pushes (through gh's credential helper) and the user's `gh secret set` need that account.

```bash
gh auth switch -u rubens-lopes
gh repo create rubens-lopes/DynamicDisplayNameplate --public \
  --description "WoW Forever addon: enemy nameplates only while you're in combat" \
  --source . --remote origin --push
gh repo view rubens-lopes/DynamicDisplayNameplate --json url,visibility
```

Expected: the URL is `https://github.com/rubens-lopes/DynamicDisplayNameplate` with visibility `PUBLIC`.

- [ ] **Step 3: Check that CI passes on main**

```bash
gh run list -R rubens-lopes/DynamicDisplayNameplate --workflow CI --limit 1
gh run watch -R rubens-lopes/DynamicDisplayNameplate --exit-status "$(gh run list -R rubens-lopes/DynamicDisplayNameplate --workflow CI --limit 1 --json databaseId -q '.[0].databaseId')"
```

Expected: the run ends in `success`. If luacheck fails, fix the reported warnings, commit, push, and repeat.

- [ ] **Step 4: The user stores the CurseForge token**

The user runs this themselves, so the token never passes through the agent:

```
! gh secret set CF_API_TOKEN -R rubens-lopes/DynamicDisplayNameplate
```

Verify: `gh secret list -R rubens-lopes/DynamicDisplayNameplate` shows `CF_API_TOKEN`.

- [ ] **Step 5: Tag and release, only after the Task 3 checklist passed**

```bash
git tag v0.0.1-beta1
git push origin v0.0.1-beta1
gh run watch -R rubens-lopes/DynamicDisplayNameplate --exit-status "$(gh run list -R rubens-lopes/DynamicDisplayNameplate --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')"
```

Expected: the Release run succeeds, and its log shows an upload to CurseForge for game version `1.60.1` with release type `beta`.

- [ ] **Step 6: Confirm the release**

```bash
gh release view v0.0.1-beta1 -R rubens-lopes/DynamicDisplayNameplate --json tagName,isPrerelease,assets -q '{tag: .tagName, pre: .isPrerelease, assets: [.assets[].name]}'
```

Expected: `pre: true` and a single `DynamicDisplayNameplate-v0.0.1-beta1.zip` asset. The user checks the project's Files tab on CurseForge for the beta file.

- [ ] **Step 7: Switch `gh` back to the user's default account**

```bash
gh auth switch -u rubens-sindel
gh auth status 2>&1 | grep -B1 "Active account: true"
```

Expected: `rubens-sindel` is the active account again.
