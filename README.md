# Dynamic Display Nameplate

A World of Warcraft: Forever addon that shows enemy and friendly player nameplates only while you're in combat. It's the "combat plates" option from Leatrix Plus on its own.

- Entering combat turns nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they hide again at the end of your next fight. Uninstalling leaves them off; press V / Shift+V to turn them back on.

## Commands

- `/ddn-help` lists the commands.
- `/ddn-enemies [on|off]` sets whether enemy plates follow combat. On by default. When off, the addon leaves enemy plates alone.
- `/ddn-friends [on|off]` sets whether friendly player plates follow combat. On by default. When off, the addon leaves friendly plates alone.
- `/ddn-status` shows each nameplate setting, its current value, and what the addon last set it to.
- `/ddn-watch` prints every game setting change until you run it again. Useful for bug reports.

With no argument, `/ddn-enemies` and `/ddn-friends` toggle. Settings are saved per account.

## Install

Get it from CurseForge, or copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/DynamicDisplayNameplate` for the Forever beta.

## Development

```bash
luajit tests/test_addon.lua
```

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and attaches the zip to a GitHub Release. Tags containing `beta` or `alpha` become pre-releases. Upload that zip to CurseForge by hand, or add a `CF_API_TOKEN` repo secret and the same workflow uploads it for you.
