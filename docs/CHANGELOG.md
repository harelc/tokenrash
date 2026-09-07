# Changelog

Retroactive log of `main` through `7e54fe2`. Dates are commit dates. Bundle version in `Info.plist` is still `0.1.0`.

Newest first. Commit subjects are the source of truth; bodies are folded in where they add why.

## 2026-09-07

### Changed

- Bundle id is `com.lightricks.tokenrash` so the app identity matches the org, not a personal account. Preferences and Launch at Login live under the new id.
- Clone URL is `https://github.com/Lightricks/tokenrash.git`.
- Fetch personal JSON from `GET /api/me` (`/me` is the SPA). After sign-in, cookies live in the WebKit data store and polls use `URLSession` — no hidden keeper WebView.
- Poll faster as remaining drops (45s below 20%, 30s below 10%) so a binge is not three minutes late.
- Signed-out is an empty glass with **Sign In** on the yoke, not a fake 62% hourglass. Crossing 10% remaining while the overlay is hidden brings it forward once; bells still fire when it is off-screen.
- Overlay hourglass is a Metal fragment shader (~10 fps while sand flows, paused when hidden, occluded, empty, or full) so a Canvas timeline is not burning CPU all day. Dock tile stays a still Canvas snapshot.
- Menu is grouped (overlay, look/counters, prefs, preview, account) and title-cased. Overlay frame is saved on move/resize, not every second.
- `swiftc` builds with `-swift-version 6`. Alarm/flap audio state is `@MainActor` so mutable globals are not a Swift 6 error.

### Fixed

- Remaining sand sits in the top bulb and spent in the bottom; falling grains use the pile color; the stream is a visible column rather than a hairline. Empty cavity is glass, not grit.

### Added

- Five distinct hourglass looks (Horologist, Inkwell, Playroom, Telemetry, Jelly) so the widget can feel classic, cute, or futuristic rather than five tints of one glass. Menu **Look**. (`faab630`)
- Independent **Top counter** and **Bottom counter** toggles so remaining, spent, both, or neither can show — the hourglass can stand alone. (`7e54fe2`)

## 2026-09-06

### Changed

- Remaining and spent sit in the brass crown and plinth so the flaps read as part of the glass, not a plate stacked on top. (`8051b32`)
- Flap copy is read from the `@MainActor` store so stricter Swift isolation checks compile. (`2df9a8e`)
- Remaining budget is driven only from `GET /me`. Admin `/tree` dumps are ignored so the wrong person cannot be picked from an org graph. Sound effects are optional in the menu. Timer tasks capture `self` on the main actor. (`c3ef6a7`)

### Added

- Optional **Show in Dock**: paint the hourglass into a squircle Dock icon with a remaining-USD badge. Runtime `applicationIconImage` is not remasked by Dock, so the app clips the tile itself. (`b3f703d`)

### Fixed

- Keep the IAP WebView invisible after restart and display wake. macOS was moving the off-screen keeper onto the display as an unclickable `/me` window; the panel stays transparent and only a real sign-in chrome appears on Google/IAP. (`5bc85e5`)

## 2026-09-03

### Added

- Mechanical tick-clack when the remaining amount flaps. Each tile sounds as it folds and lands. **Preview warnings** includes **Counter flap** (also first in **Play all**). (`d736807`)

## 2026-09-02

### Added

- Floating macOS hourglass for the daily tokendash `/me` budget. (`336029c`)
- Remaining USD on a split-flap plate; IAP refresh stays hidden. Overlay is remaining-only; **Refresh now** reloads in the keeper WebView. README screenshot of the live widget. (`1c3b170`)
- Install to Applications with Launch at Login and a real app icon. Menu-bar click opens the menu. `install.sh` copies the bundle into `/Applications`. README is install plus develop. (`6541b50`)
- Warn at 10%, 5%, and 1% remaining. Bells fire once as the budget crosses each threshold; a siren and red flash kick in at 1%. **Preview warnings** lets you hear and see them on demand. (`49d1b11`)
