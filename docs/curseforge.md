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

Enemy and friendly nameplates only while you're in combat.

## Description

Dynamic Display Nameplate shows enemy and friendly player nameplates when you enter combat and hides them when you leave. It's the "combat plates" behavior from Leatrix Plus, on its own, for World of Warcraft: Forever.

**How it works**

- Entering combat turns nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

Install it and it works. There is one option:

- `/ddn-help` lists the commands.
- `/ddn-friends [on|off]` sets whether friendly nameplates follow combat too. On by default. When off, the addon leaves friendly nameplates alone.

**Good to know**

- If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they will hide again at the end of your next fight.
- The addon changes only the enemy and friendly nameplate settings. "Always show nameplates" is left as you set it.
- If you uninstall it, nameplates stay off. Press V / Shift+V to turn them back on.

**Compatibility**

- World of Warcraft: Forever (1.60.x)
- Works alongside other nameplate addons. It only decides when nameplates are shown, not what they look like.

**Source and issues**

The code is on [GitHub](https://github.com/rubens-lopes/DynamicDisplayNameplate). If something goes wrong, open an issue there and include any error text the addon printed in chat.
