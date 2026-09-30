# Dynamic Display Nameplate

A World of Warcraft: Forever addon that shows enemy and friendly player nameplates only while you're in combat. It's the "combat plates" option from Leatrix Plus on its own, plus friendly plates that follow health and a friendly-left / enemy-right layout.

- Entering combat turns nameplates on.
- Leaving combat turns them off.
- Logging in, reloading, or zoning out of combat turns them off.

If you press V (or Shift+V for friendly plates) to show nameplates outside combat, they hide again at the end of your next fight. Uninstalling leaves them off; press V / Shift+V to turn them back on.

## Options

Open the panel with `/ddn-options`, or Esc > Options > AddOns > Dynamic Display Nameplate. Every switch starts on.

- **Enemy plates only in combat**: turns enemy plates on when you enter combat and off when you leave it.
- **Friendly player plates only in combat**: same for friendly player plates.
- **Fade friendly plates at full health**: while a friendly player is at full health, their plate is faint (30% opacity) in combat and hidden out of combat. It turns solid as soon as they lose health. Hidden plates still take up room when plates stack.
- **Show hurt friendly plates out of combat**: keeps friendly plates on outside combat, so anyone below full health still shows.
- **Friendly plates on the left, enemy plates on the right**: plates stack instead of overlapping, and friendly plates shift left of the character and enemy plates right. Turning it off puts your old overlap setting back.

## Commands

- `/ddn-help` lists the commands.
- `/ddn-options` opens the options panel.
- `/ddn-enemies [on|off]` sets whether enemy plates follow combat. On by default. When off, the addon leaves enemy plates alone.
- `/ddn-friends [on|off]` sets whether friendly player plates follow combat. On by default. When off, the addon leaves friendly plates alone.
- `/ddn-fadefull [on|off]`, `/ddn-showhurt [on|off]` and `/ddn-sides [on|off]` switch the other three options.
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
