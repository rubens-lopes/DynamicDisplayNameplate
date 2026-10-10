# Dynamic Display Nameplate

A World of Warcraft: Forever addon that shows enemy and friendly player nameplates only while you're in combat. It's the "combat plates" option from Leatrix Plus on its own, plus friendly plates that follow health and a friendly-left / enemy-right layout.

- Entering combat turns nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they hide again at the end of your next fight. Uninstalling leaves them off; press V / Shift+V to turn them back on.

## Options

Open the panel with `/ddn-options`, or Esc > Options > AddOns > Dynamic Display Nameplate. Every switch starts on except the engaged, group, names and missing-health ones. The panel scrolls if it doesn't fit.

- **Enemy plates only in combat**: turns enemy plates on when you enter combat and off when you leave it.
- **Enemy plates only for mobs fighting your group**: hides the plate of any enemy NPC that isn't your target, has nobody in your group (you, party or raid members, and pets) on its threat list, and isn't targeting one of you. Enemy players always show. Off by default. Hidden plates still take up room when plates stack.
- **Friendly player plates only in combat**: same for friendly player plates.
- **Friendly player plates only for your party or raid**: hides the plate of any friendly player who isn't in your group, so solo you see none. Friendly NPCs aren't affected. Off by default.
- **Fade friendly plates at full health**: while a friendly player is at full health, their plate is faint (30% opacity) in combat and hidden out of combat. It turns solid as soon as they lose health. Hidden plates still take up room when plates stack.
- **Show hurt friendly plates out of combat**: keeps friendly plates on outside combat, so anyone below full health still shows. Only while "Friendly player plates only in combat" is on; with that off, the addon leaves friendly plates alone.
- **Only the name of friendly players at full health**: in place of fading or hiding them, friendly plates at full health show just the name, in class colour, in and out of combat. The health bar appears as soon as they lose health. Turns on Blizzard's class-coloured friendly names and turns off Blizzard's own name-only setting (which hides the bar even when they're hurt); turning it off puts both back the way they were. Off by default.
- **Missing health on friendly plates**: friendly plates show how much health is missing (`-0` at full health) in place of Blizzard's health number. Off by default. This used to be the Deficit Plates addon; while that one is still enabled, it keeps the health text and this option waits.
- **Friendly plates on the left, enemy plates on the right**: friendly plates shift left of the character and enemy plates right. On clients with the `nameplateMotion` setting, plates also stack instead of overlapping, and turning it off puts your old setting back. WoW Forever doesn't have it, so there plates only shift.

### Inside dungeons and raids

Blizzard keeps friendly plates off limits to addons there, so the friendly-plate options (group only, fade, missing health, sides) don't apply to them; they look the way Blizzard draws them. Enemy plates work as usual. For missing health in a dungeon, set the party frames to show health lost in Blizzard's options.

## Commands

- `/ddn-help` lists the commands.
- `/ddn-options` opens the options panel.
- `/ddn-enemies [on|off]` sets whether enemy plates follow combat. On by default. When off, the addon leaves enemy plates alone.
- `/ddn-friends [on|off]` sets whether friendly player plates follow combat. On by default. When off, the addon leaves friendly plates alone.
- `/ddn-engaged [on|off]`, `/ddn-group [on|off]`, `/ddn-fadefull [on|off]`, `/ddn-showhurt [on|off]`, `/ddn-names [on|off]`, `/ddn-deficit [on|off]` and `/ddn-sides [on|off]` switch the other seven options.
- `/ddn-status` shows each nameplate setting, its current value, and what the addon last set it to.
- `/ddn-watch` prints every game setting change until you run it again. Useful for bug reports.

With no argument, each switch command toggles. Settings are saved per account.

## Install

Get it from CurseForge, or copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/DynamicDisplayNameplate` for the Forever beta.

## Development

```bash
luajit tests/test_addon.lua
```

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and attaches the zip to a GitHub Release. Tags containing `beta` or `alpha` become pre-releases. Upload that zip to CurseForge by hand, or add a `CF_API_TOKEN` repo secret and the same workflow uploads it for you.
