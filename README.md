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

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and attaches the zip to a GitHub Release. Tags containing `beta` or `alpha` become pre-releases. Upload that zip to CurseForge by hand, or add a `CF_API_TOKEN` repo secret and the same workflow uploads it for you.
