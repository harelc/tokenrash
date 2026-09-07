# Tokenrash for developers

User-facing install is in the [root README](../README.md). History of `main` is in [CHANGELOG.md](CHANGELOG.md).

Tokenrash is a small SwiftUI + AppKit overlay. Remaining daily budget comes from Lightricks tokendash `GET /api/me` after Google IAP. A `WKWebView` exists only while signing in; afterward cookies live in the WebKit data store and polls use `URLSession`. There is no Xcode project; the `.app` is assembled by `scripts/build.sh`.

## Requirements

Apple silicon, macOS 14+, Xcode Command Line Tools. Bundle id `com.lightricks.tokenrash`. `Info.plist` still reports version `0.1.0`.

## Build and run

```bash
./scripts/run.sh       # rebuild dist/Tokenrash.app and launch it
./scripts/install.sh   # same build, copy to /Applications, launch that copy
```

`run.sh` deletes `dist/` on every rebuild. Do not turn on **Launch at Login** against a `run.sh` copy; use `/Applications/Tokenrash.app`.

`build.sh` compiles every `Sources/Tokenrash/*.swift` with `swiftc -swift-version 6` for `arm64-apple-macos14.0`, copies `Resources/Info.plist` and `AppIcon.icns`, and ad-hoc codesigns. Adding a new Swift file in that folder is enough; nothing else lists sources. Links **Metal** and **MetalKit**.

Do **not** use `swift build` or `xcodebuild`. `Package.swift` exists so the folder is a Swift package, but SPM emits a CLI binary, not an `.app`. `xcodebuild` has no project to drive.

`scripts/install.sh` kills a running Tokenrash, rebuilds, replaces `/Applications/Tokenrash.app`, clears quarantine, and opens it.

If Gatekeeper complains after a manual copy: `xattr -dr com.apple.quarantine /Applications/Tokenrash.app`.

## Layout

```
Sources/Tokenrash/     all app code (one target, no tests)
Resources/             Info.plist, AppIcon.icns
scripts/               build.sh, run.sh, install.sh
docs/                  this file, changelog, screenshot
dist/                  local .app (gitignored)
```

| File | Role |
|---|---|
| `App.swift` | `@main`, menu bar, overlay panel, Dock policy, preference toggles |
| `OverlayView.swift` | Hourglass + look chrome, scaled to the panel |
| `HourglassView.swift` | Glass: Metal shader on the overlay, still Canvas for the Dock tile |
| `MetalHourglass.swift` | Runtime-compiled fragment shader + `MTKView` for the live overlay |
| `WidgetLook.swift` | Five looks (palette, silhouette, numerals); persisted |
| `WidgetChrome.swift` | Crown / plinth yokes per look |
| `SplitFlapBoard.swift` | Remaining/spent flap tiles + tick-clack |
| `BudgetStore.swift` | `@MainActor` live + preview state |
| `TokenBudget.swift` | `/me` parser and USD formatting |
| `IAPSession.swift` | IAP login WebView, `URLSession` `/api/me`, adaptive poll |
| `Config.swift` | Backend origin, poll intervals, alarm steps |
| `BudgetAlarms.swift` | Thresholds, sounds, sound/Dock/counter prefs |
| `DockIcon.swift` | Runtime squircle tile with remaining badge |
| `Install.swift` | Copy to Applications, `SMAppService` login item |
| `ResizeHandleView.swift` | Bottom-right resize in screen space |

## Overlay

`AppDelegate` builds a borderless `NSPanel` at `.floating`, always on all Spaces. `LSUIElement` is true, so the process is a menu-bar accessory unless **Show in Dock** flips `NSApp.setActivationPolicy(.regular)`.

Design size is 200×300 (`HourglassChrome.design`, aspect 1.5). The panel is movable by the background; the resize handle uses its own mouse-tracking loop so SwiftUI and window-move do not steal the drag. Frame is restored from `overlay.frame.v2` on move/resize (not every second); height is recomputed from width × aspect. Metal drawing pauses when the panel is hidden or occluded.

Left-click the menu-bar hourglass for the menu (grouped: overlay, look/counters, prefs, preview, account). Overlay tap while signed out starts sign-in.

## Looks and counters

`WidgetLook` is not five tints of one glass:

| Look | Silhouette | Numerals |
|---|---|---|
| Horologist | classic | brass split-flap |
| Inkwell | column | gold serif |
| Playroom | fat toy bulbs | chunky rounded |
| Telemetry | diamond | amber mono HUD |
| Jelly | blob | puffy rounded |

`LookChrome` draws the top remaining yoke and bottom spent yoke. **Remaining** / **Spent** hide them independently; both on is the default. The glass still draws; only the plates go away.

The Dock tile uses `HourglassView(chrome: .icon, look:)` plus a remaining-USD badge. macOS does not remask `applicationIconImage`, so `DockIcon` clips to a squircle itself.

## Budget

Remaining is `limit − spend` from personal JSON:

```text
GET /api/me  →  { email, today: { spend_usd, effective_limit_usd | standing_limit_usd } }
```

`TokenBudgetParser.extract` only reads a root `today`. Org dumps (`nodes`, or `personas` without `today`) are dropped. Walking `/tree` cannot recover a manager’s own spend: team/org `spend` is the sum of children, and ICs appear once. Always use the personal card, not `/tree`.

Poll interval is adaptive (`TokenrashConfig.pollInterval(remaining:)`): 180s when remaining is above 20%, 45s at or below 20%, 30s at or below 10%. **Refresh** hits `URLSession` `GET /api/me` with stored IAP cookies; the WebView opens only if that session is dead.

## Auth (IAP, not gcloud)

There is no JWT or `gcloud` token. Google IAP cookies live in `WKWebsiteDataStore.default()` and survive after the WebView is torn down.

- **Login window** — a `WKWebView` exists only while signing in. It appears when the navigation host is Google accounts or `iap.googleapis.com`. After a successful ingest (sniffer or in-page `fetch('/api/me')`), the WebView is destroyed. Closing the window without a budget returns to signed-out.
- **Live fetch** — `URLSession` `GET /api/me` with `Accept: application/json`, Safari user-agent, and a `Cookie` header copied from `WKHTTPCookieStore`. `Set-Cookie` on the response is written back to the WebKit store. There is no keeper panel.
- **Sniffer** — injected `fetch` / XHR hook during login posts `{ url, body }` only for `/api/me` and `/me` URLs; `/tree` is ignored.

Safari user-agent is set so IAP does not bounce to a broken client. Signed-out is an empty glass with **Sign In** on the remaining yoke, not a fake 62% hourglass.

## Alarms and sound

Steps in `TokenrashConfig.alarmSteps`: 10% (bell), 5% (bells), 1% (siren + red flash). Each id fires once per day until remaining jumps up by more than 8% (reset). Sounds play even if the overlay is hidden. Crossing 10% while the panel is hidden or occluded brings it forward once. **Preview Alarms** drives `BudgetStore` preview fields so the overlay animates without waiting for spend.

`SoundSettings` gates alarm and flap audio. Split-flap tiles tick/clack as they fold.

## Preferences

All under the app’s standard `UserDefaults` (bundle `com.lightricks.tokenrash`):

| Key | Default | Meaning |
|---|---|---|
| `widget.look` | `horologist` | `WidgetLook.rawValue` |
| `counters.top` | on | remaining yoke |
| `counters.bottom` | on | spent yoke |
| `sounds.enabled` | on | alarms + flap |
| `dock.enabled` | off | activation policy + painted tile |
| `overlay.frame.v2` | — | panel frame |
| `alarms.lastRemaining` / `alarms.fired` | — | threshold state |
| `install.launchAtLogin.pending` | — | enable login item after copy-to-Applications |

## Debug

Menu **Inspect Payload…** shows the last parsed JSON.

On disk:

- `~/Library/Logs/Tokenrash-last-me.json` — last ingest (parsed or miss)
- `~/Library/Logs/Tokenrash-captures.jsonl` — source, length, 300-char prefix per capture

Console: `NSLog` lines tagged `[Tokenrash]`.

## Concurrency

`BudgetStore` is `@MainActor @Observable`. Silent `/api/me` polls are a `Task` on that actor, not a repeating `Timer`. Flap copy (`remainingPlate` / `spentPlate`) is computed on the store so stricter isolation checks compile. Do not read those from a background task.

## Install and login item

`AppInstall.installAndRelaunch` copies the running bundle to `/Applications/Tokenrash.app`, opens it, then terminates. **Launch at Login** uses `SMAppService.mainApp`. If the user enables it from a non-Applications copy, install sets `install.launchAtLogin.pending` and the new process registers after launch.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). When you land a user-visible change, add a dated bullet there in the same voice as the git history (why, not a file list).
