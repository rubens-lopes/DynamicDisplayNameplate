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

Enemy and friendly player nameplates only while you're in combat.

## Description

Dynamic Display Nameplate shows enemy and friendly player nameplates when you enter combat and hides them when you leave. It's the "combat plates" behavior from Leatrix Plus, on its own, for World of Warcraft: Forever.

**How it works**

- Entering combat turns nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

Install it and it works. To change it, use these chat commands:

- `/ddn-help` lists the commands.
- `/ddn-enemies [on|off]` sets whether enemy plates follow combat. On by default. When off, the addon leaves enemy plates alone.
- `/ddn-friends [on|off]` sets whether friendly player plates follow combat. On by default. When off, the addon leaves friendly plates alone.
- `/ddn-status` shows each nameplate setting, its current value, and what the addon last set it to.
- `/ddn-watch` prints every game setting change until you run it again. Useful for bug reports.

With no argument, `/ddn-enemies` and `/ddn-friends` toggle. Settings are saved per account.

**Good to know**

- If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they will hide again at the end of your next fight.
- The addon changes only the enemy and friendly player nameplate settings. Friendly NPC plates and "Always show nameplates" are left as you set them.
- If you uninstall it, nameplates stay off. Press V / Shift+V to turn them back on.

**Compatibility**

- World of Warcraft: Forever (1.60.x)
- Works alongside other nameplate addons. It only decides when nameplates are shown, not what they look like.

**Source and issues**

The code is on [GitHub](https://github.com/rubens-lopes/DynamicDisplayNameplate). If something goes wrong, open an issue there and include any error text the addon printed in chat.
