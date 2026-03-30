# Yokuli — Vessel Control Platform

A Flutter-based marine vessel control app for Android and iOS. Designed to feel like a "Marine OS" — a launcher-style interface with modular panels for Signal K data, instruments, power management, safety, logbook, and maintenance.

## Status

> **Branch:** `claude/vessel-control-app-jeJzm`
> **Last updated:** 2026-03-30
> **Build status:** ✅ Source complete — ready for `flutter pub get && flutter run`

---

## Architecture

```
MVVM + Riverpod (manual Notifier, no code generation required)
Feature-first directory structure
Hive (no TypeAdapters) for logbook/maintenance storage
SharedPreferences for settings
go_router for navigation
```

### Multi-device LAN Sync

```
Host device                     Client device(s)
  │                                  │
Signal K WS ──► VesselState         │
  │                                  │
  └──► shelf WS server :8765 ────► WS client ──► VesselState

Discovery: UDP broadcast on port 43215 (auto) + manual IP entry
```

**Device roles (Settings screen):**
- **Standalone** — direct Signal K connection only
- **Host (Master)** — collects Signal K data, serves LAN peers via WebSocket
- **Client** — receives all data from host, no Signal K connection needed

---

## Modules

| Module | Status | Description |
|--------|--------|-------------|
| Signal K Hub | ✅ | WebSocket client, delta parser, auto-reconnect |
| Dashboard | ✅ | SOG, COG, Heading compass, wind, depth, GPS, batteries |
| Power | ✅ | Battery cards with SOC gauges, voltage, current |
| Logbook | ✅ | Manual + auto entries (departure/arrival/waypoint/MOB), swipe-to-delete |
| Safety | ✅ | MOB trigger with GPS + LAN broadcast, depth/speed alarms |
| Maintenance | ✅ | Task list with recurrence, overdue tracking, mark-done |
| Weather | 🔲 Stub | Entry point reserved |
| Tools | 🔲 Stub | Entry point reserved |
| Settings | ✅ | Vessel name, Signal K URL, LAN role, auto-connect |

---

## Setup

### Prerequisites

- Flutter SDK ≥ 3.3.0 (channel stable)
- Android SDK or Xcode for iOS

### First run

```bash
# 1. Clone
git clone https://github.com/ohkuku/yokuli_app.git
cd yokuli_app
git checkout claude/vessel-control-app-jeJzm

# 2. Get dependencies
flutter pub get

# 3. Run (Android or iOS)
flutter run

# For iOS (first time only)
cd ios && pod install && cd ..
flutter run
```

### Platform files

Android and iOS platform files are included. If you need to regenerate them:

```bash
# This overwrites only the platform scaffolding, not lib/
flutter create --project-name yokuli_app --org com.yokuli .
```

---

## Signal K Connection

1. Open **Signal K Hub** from home screen
2. Enter WebSocket URL: `ws://<server-ip>:3000/signalk/v1/stream`
3. Tap **Connect**

Default Signal K port is **3000**. Enable **Auto-connect** to connect on app launch.

---

## LAN Sync Setup

### On the "host" device (helm station, chartplotter tablet):
1. Go to **Settings → LAN Sync → Host (Master)**
2. Note the WS address shown (e.g. `ws://192.168.1.5:8765`)
3. Enable **Auto-start LAN sync on launch**
4. Connect this device to Signal K

### On "client" devices (cockpit tablet, phone):
1. Go to **Settings → LAN Sync → Client**
2. Enter the host IP (or tap **Scan for hosts**)
3. Tap **Restart LAN sync**

All client devices will now receive live vessel data from the host.

---

## Key packages

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Navigation |
| `web_socket_channel` | Signal K + LAN client |
| `shelf` + `shelf_web_socket` | LAN host WebSocket server |
| `hive_flutter` | Local storage (logbook, maintenance) |
| `shared_preferences` | Settings persistence |
| `geolocator` | Device GPS for MOB position fallback |

---

## Roadmap

- [ ] Weather module (OpenWeatherMap / Windy API)
- [ ] NMEA 0183 TCP input (raw sentence parser)
- [ ] Anchor alarm (GPS drift detection)
- [ ] Tidal data (offline tables)
- [ ] Unit converter + calculator tools
- [ ] Logbook GPX/CSV export
- [ ] Push notifications for alarms
- [ ] Dark/dim mode toggle (red night vision mode)
