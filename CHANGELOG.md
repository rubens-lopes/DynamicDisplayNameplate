# Changelog

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
