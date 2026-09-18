# Dynamic Display Nameplate: design

Date: 2026-09-18
Status: approved in chat

## Goal

A standalone World of Warcraft: Forever addon that shows enemy nameplates only while the player is in combat. It is the "combat plates" feature from Leatrix Plus, without the rest of Leatrix Plus. It is published on CurseForge.

## Target

- WoW Forever only. It runs on the retail 12.x engine from the `_retail_` folder, with TOC `## Interface: 16001`.
- CurseForge flavor: Forever (game version type 88568, version 1.60.1).
- The first release is `v0.0.1-beta1` (CurseForge release type: beta).

## Behavior

The addon writes only the `nameplateShowEnemies` CVar.

| Event | Condition | Write |
|---|---|---|
| `PLAYER_REGEN_DISABLED` | none | `1` |
| `PLAYER_REGEN_ENABLED` | none | `0` |
| `PLAYER_ENTERING_WORLD` | player not in combat | `0` |
| `PLAYER_ENTERING_WORLD` | player in combat (e.g. a `/reload` mid-fight) | none; the next `PLAYER_REGEN_ENABLED` corrects it |

Rules for every write:

- Skip the write when `InCombatLockdown()` is true. `PLAYER_REGEN_DISABLED` fires before lockdown starts and `PLAYER_REGEN_ENABLED` fires after it ends, so the normal path is never skipped.
- Call `C_CVar.SetCVar`, falling back to the global `SetCVar`, inside `pcall`.
- If a write raises an error or returns false, print one chat line per session naming the addon and the error. Never raise an error.

Out of scope: options, slash commands, SavedVariables, friendly nameplates, `nameplateShowAll`.

Known side effects, which the CurseForge description documents:

- A manual V-key toggle outside combat is undone at the end of the next fight.
- Uninstalling leaves enemy nameplates off.

## Files

```
DynamicDisplayNameplate.toc
DynamicDisplayNameplate.lua
tests/test_addon.lua
.pkgmeta
.luacheckrc
.github/workflows/ci.yml
.github/workflows/release.yml
README.md
CHANGELOG.md
LICENSE
docs/curseforge.md
media/logo.png
```

The packaged zip contains only the `.toc`, the `.lua`, `LICENSE`, and `CHANGELOG.md`.

## Testing

- **Unit tests:** `tests/test_addon.lua` runs under LuaJIT, locally and in CI, against a stubbed WoW API. It covers each row of the behavior table, the lockdown skip, the fallback to global `SetCVar`, and a failing write producing exactly one warning with no error raised.
- **Lint:** luacheck in CI.
- **In-game:** the user runs a checklist on the Forever client before the first release.
  1. Turn on Lua errors (`/console scriptErrors 1`).
  2. Out of combat: enemy plates are hidden.
  3. Pull a mob: plates appear.
  4. Leave combat: plates hide.
  5. `/reload` mid-fight: plates hide when the fight ends.
  6. Zone into a dungeon.
  7. Confirm no chat warning appeared.

## Release

1. Public repo `rubens-lopes/DynamicDisplayNameplate`. Commits use github@rubenslop.es, set for this repo only.
2. The user creates the CurseForge project using `docs/curseforge.md` and generates an API token.
3. The project ID goes into the TOC as `## X-Curse-Project-ID`. The user stores the token with `gh secret set CF_API_TOKEN`.
4. After the in-game checklist passes, push the tag `v0.0.1-beta1`. `BigWigsMods/packager@v2` builds the zip and uploads it to CurseForge and GitHub Releases.
