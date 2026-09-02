# Tokenrash

![Tokenrash overlay and menu bar](docs/screenshot.png)

A floating macOS hourglass for your **remaining daily token budget** (USD), read from Lightricks tokendash after Google sign-in.

Menu-bar accessory: no Dock icon. Click the hourglass for the menu (show/hide the widget, sign in, refresh, launch at login).

## Install

Apple silicon, macOS 14+, Xcode Command Line Tools.

```bash
git clone https://github.com/harelc/tokenrash.git
cd tokenrash
chmod +x scripts/*.sh
./scripts/install.sh
```

That builds the app, copies it to `/Applications/Tokenrash.app`, and launches it. Then **Launch at Login** in the menu-bar menu so it returns after restart.

Re-run `./scripts/install.sh` to update. From a running copy you can also use **Install to Applications…**.

If Gatekeeper complains: `xattr -dr com.apple.quarantine /Applications/Tokenrash.app`

## Develop

```bash
./scripts/run.sh
```

Rebuilds and launches `dist/Tokenrash.app` (does not install). Do not enable Launch at Login on that copy — `run.sh` deletes `dist/` on every rebuild. Use the Applications install for anything that should survive a restart.
