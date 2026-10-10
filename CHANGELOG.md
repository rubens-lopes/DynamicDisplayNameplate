# Changelog

## v0.3.1

- Fix: `/ddn-friends off` didn't stop the addon turning friendly plates on. "Show hurt friendly plates out of combat" kept switching them on, so they came back every fight. Now the addon leaves friendly plates alone while `/ddn-friends` is off.
- New: only the name of friendly players at full health (`/ddn-names`). Friendly plates at full health show just the class-coloured name, in and out of combat, and the health bar appears as soon as they lose health. It turns off Blizzard's own "only names" setting for friendly players while on, since that one hides the bar even when they're hurt, and puts it back when turned off. Off by default.
- `/ddn-status` prints the time, how each plate is drawn, and keeps the run before alongside the latest in the saved variables.

## v0.3.0-beta1

- New options panel (`/ddn-options`, or Esc > Options > AddOns) with an explanation of each switch. It scrolls when it doesn't fit.
- `/ddn-status` shows more: how each plate is classed, plates off limits to addons, missing-health checks, and the client's stacking settings when it lists them. Its output is also saved in the addon's saved variables, for output too long to screenshot.
- New: enemy plates only for mobs fighting your group (`/ddn-engaged`). An enemy NPC's plate shows only while it's your target, has someone in your group on its threat list, or is targeting one of you. Enemy players always show. Off by default.
- New: friendly player plates only for your party or raid (`/ddn-group`). Off by default.
- New: missing health on friendly plates (`/ddn-deficit`), merged in from the Deficit Plates addon. Off by default. If Deficit Plates is still enabled, it keeps the health text until you disable it.
- New: friendly plates at full health fade in combat and hide out of combat (`/ddn-fadefull`). On by default.
- New: show hurt friendly plates out of combat (`/ddn-showhurt`). On by default.
- New: friendly plates on the left, enemy plates on the right (`/ddn-sides`). On by default. Plates also stack instead of overlapping on clients with the `nameplateMotion` setting; WoW Forever doesn't have it.
- Inside dungeons and raids, Blizzard keeps friendly plates off limits to addons, so the friendly-plate options don't apply there. The party frames can show missing health instead.

## v0.2.0-beta1

- Fix: friendly player plates never changed. Forever calls the setting `nameplateShowFriendlyPlayers`, not `nameplateShowFriends`.
- A setting the client doesn't have now prints a warning instead of failing silently.
- New `/ddn-enemies [on|off]`: turn it off to leave enemy plates alone (for example, to manage only friendly plates as a healer).
- New `/ddn-status` and `/ddn-watch` commands for troubleshooting.

## v0.1.0-beta1

- Friendly player nameplates now also show only while you're in combat. This is on by default; turn it off with `/ddn-friends off`.
- New slash commands: `/ddn-help` and `/ddn-friends [on|off]`. The setting is saved per account.

## v0.0.1-beta1

- First beta for World of Warcraft: Forever. Enemy nameplates show only while you're in combat.
