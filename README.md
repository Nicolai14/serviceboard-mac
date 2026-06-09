# DashboardFlow Mac

Native macOS app for the ServerFlow/Laravel dashboard. It shows the dashboard
UI as a WebView in its own Mac window and adds native navigation plus a menu bar
item with server load.

## Requirements

- macOS 13 or newer
- Xcode or the Xcode Command Line Tools (`xcode-select --install`) – provides `swiftc`

## Configuration

The dashboard's production URL is not stored in the code; it is read from a
local `.env` file (not checked in). Before the first build:

```bash
cp .env.example .env
# Open .env and set PRODUCTION_BASE_URL to your own dashboard URL
```

`build.sh` reads the `.env` and generates the required Swift configuration from
it. Without a `.env`, it falls back to the placeholder URL from `.env.example`.

## Build

```bash
./build.sh
```

The finished app bundle is then located at:

```text
build/DashboardFlow.app
```

Launch it with:

```bash
open build/DashboardFlow.app
```

## Features

- WebView wrapper for the Dashboard, Workflow, Server, Docker, Cloudflare,
  Costs, Alerts and Profile routes in a single native Mac window
- Native **Flow Map** with an overview of the DashboardFlow architecture
- Environment switcher in the toolbar: **Production** (configured via `.env`),
  **Local :8000** and **Local :8080**
- Menu bar item with a compact CPU/RAM/Disk overview for all servers
  (label `DF`)
- Custom DashboardFlow app icon

## Menu bar: server load

Click the server/gauge symbol in the macOS menu bar. On first use, sign in with
your ServerFlow email and password; this creates a Sanctum API token. The token
is stored locally in the app preferences, and the popover refreshes server load
every 60 seconds while the app is running.

If the menu bar item is not visible, quit any already running DashboardFlow
instance and open the freshly built app again.

## Local usage

Start Laravel locally, then pick **Local :8000** or **Local :8080** in the
toolbar.
