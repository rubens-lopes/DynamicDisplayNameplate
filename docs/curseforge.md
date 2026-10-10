# CurseForge project page

Paste these into the project form at https://authors.curseforge.com/#/projects/create

- **Game:** World of Warcraft
- **Project type:** Addons
- **Name:** Dynamic Display Nameplate
- **Primary category:** Unit Frames
- **Additional category:** Combat
- **License:** MIT License
- **Logo:** `media/logo.png`
- **Source:** https://github.com/rubens-lopes/DynamicDisplayNameplate
- **Issues:** https://github.com/rubens-lopes/DynamicDisplayNameplate/issues

## Summary

Nameplates only in combat, only for what matters: mobs fighting your group, your party's plates, and missing health for healers.

## Description

Dynamic Display Nameplate decides when Blizzard's nameplates show, and which ones. It keeps Blizzard's look. For World of Warcraft: Forever.

**How it works**

- Entering combat turns enemy and friendly player nameplates on; leaving combat turns them off.
- Every switch is in the options panel: type `/ddn-options`, or Esc > Options > AddOns > Dynamic Display Nameplate. Each one has a short explanation and a chat command.

**Options**

- **Enemy plates only in combat** (on by default).
- **Enemy plates only for mobs fighting your group** (off by default): hides enemy NPC plates unless the mob is your target, has someone in your group on its threat list, or is targeting one of you. Enemy players always show.
- **Friendly player plates only in combat** (on by default).
- **Friendly player plates only for your party or raid** (off by default).
- **Fade friendly plates at full health** (on by default): faint in combat, hidden out of combat, solid as soon as they lose health.
- **Show hurt friendly plates out of combat** (on by default).
- **Only the name of friendly players at full health** (off by default): just the class-coloured name until they lose health, in and out of combat. Unlike Blizzard's own "only names" setting, the bar comes back when they're hurt.
- **Missing health on friendly plates** (off by default): `-118`, or `-0` at full health, in place of Blizzard's health number. This used to be the Deficit Plates addon.
- **Friendly plates on the left, enemy plates on the right** (on by default).

**Commands**

- `/ddn-help` lists the commands.
- `/ddn-options` opens the options panel.
- `/ddn-enemies`, `/ddn-engaged`, `/ddn-friends`, `/ddn-group`, `/ddn-fadefull`, `/ddn-showhurt`, `/ddn-names`, `/ddn-deficit`, `/ddn-sides` each take `on` or `off`; with no argument they toggle.
- `/ddn-status` shows what the addon sees. Include it in bug reports.
- `/ddn-watch` prints every game setting change until you run it again.

Settings are saved per account.

**Good to know**

- Inside dungeons and raids, Blizzard keeps friendly plates off limits to addons, so the friendly-plate options don't apply there. For missing health in a dungeon, set the party frames to show health lost.
- Hidden plates still take up room when plates stack.
- If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they hide again at the end of your next fight.
- If you uninstall it, nameplates stay off. Press V / Shift+V to turn them back on.
- Using Deficit Plates? Turn on "Missing health on friendly plates" here and disable Deficit Plates.

**Compatibility**

- World of Warcraft: Forever (1.60.x)

**Source and issues**

The code is on [GitHub](https://github.com/rubens-lopes/DynamicDisplayNameplate). If something goes wrong, open an issue there and include the `/ddn-status` output.
