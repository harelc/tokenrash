# Tokenrash

A floating macOS hourglass for your daily token budget, read from
`https://tokendash-backend-api-olut5dffgq-ew.a.run.app/me`.

## Run

Requires macOS 14+ and Xcode Command Line Tools (no full Xcode needed).

```bash
./scripts/run.sh
```

That builds `dist/Tokenrash.app` and launches it. The sandclock sits on the
desktop; an hourglass also appears in the menu bar.

- Drag the hourglass to move it.
- Click the brass plate to sign in with Google (IAP).
- Right-click the menu bar icon for refresh, click-through, payload inspect, and quit.

Until you sign in, it runs with demo sand.
