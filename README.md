<div align="center">

# Yokuli

**船控平台 · Vessel Control Platform**

*Flutter · Android · iOS · Web*

<br/>

[**中文**](#中文)　·　[**English**](#english)

</div>

---

<a name="中文"></a>

## 中文文档

> 🇬🇧 [Switch to English](#english)

### 简介

Yokuli 是一款基于 Flutter 的海洋船控 App，面向 Android、iOS 和 **Web** 三端。界面风格类似「船载操作系统」—— 以 launcher 方式组织各功能模块，接入 Signal K 服务器实时数据，支持多设备局域网数据共享。

**Web 端限制：** 浏览器无法运行服务器，因此 Web 版只能作为 Client 连接到原生设备（Android/iOS）的 Host。Signal K 直连功能正常。

### 当前状态

> **分支：** `claude/vessel-control-app-jeJzm`
> **最后更新：** 2026-03-30
> **构建状态：** ✅ 源码完整，执行 `flutter pub get && flutter run` 即可运行

---

### 功能模块

| 模块 | 状态 | 说明 |
|------|------|------|
| Signal K Hub | ✅ | WebSocket 客户端，Host IP + Port 输入，自动重连，断线60s无数据自动重连 |
| 仪表盘 | ✅ | 航速、航向罗盘、风速风向、水深、GPS、电池 |
| 电力管理 | ✅ | 电池卡片（SOC、电压、电流），太阳能充电控制器（面板电压/电流/功率） |
| AIS | ✅ | 地图叠加雷达（OpenStreetMap + 可缩放），极坐标雷达，目标列表，CPA 风险，详细信息 |
| 航程 | ✅ | 航程计时，快速日志按钮，事件列表（可删除、查看 GPS 详情），历史记录 |
| 系统日志 | ✅ | 全局事件流，按类型过滤 |
| 安全 | ✅ | MOB 触发（GPS 位置 + LAN 广播所有设备），水深 / 速度告警，取消 MOB 广播 |
| 船务看板 | ✅ | Kanban 看板（待办/进行中/已完成），自定义列，卡片含分类/优先级 |
| 天气 | 🔲 占位 | 入口已预留 |
| 小工具 | 🔲 占位 | 入口已预留 |
| 设置 | ✅ | 船名、Signal K 主机 IP + 端口、LAN 角色、连接/断开按钮、自动连接 |

---

### 架构说明

```
MVVM + Riverpod（手写 Notifier，无需 code generation）
Feature-first 目录结构
JSON 文件持久化（path_provider）用于日志、航程、看板
SharedPreferences 用于设置持久化
go_router 路由
```

#### 多设备 LAN 同步

```
主机设备 (Host)                    客户端设备 (Client)
  │                                      │
Signal K WS ──► VesselState              │
  │                                      │
  └──► shelf WS 服务器 :8765 ────────► WS 客户端 ──► VesselState

发现方式：UDP 广播端口 43215（自动）+ 手动填写 IP（备用）
```

**设备角色（设置页面选择）：**
- **独立模式 (Standalone)** — 直连 Signal K，不参与局域网同步
- **主机 (Host/Master)** — 汇聚 Signal K 数据，通过 WebSocket 向局域网客户端广播（仅原生端支持）
- **客户端 (Client)** — 从主机接收所有数据，首页不显示 Signal K 仪表盘（Web 端固定为此模式）

---

### 快速开始

**环境要求**
- Flutter SDK ≥ 3.3.0（stable 频道）
- Android SDK 或 Xcode（iOS）

**运行步骤**

```bash
# 1. 克隆仓库
git clone https://github.com/ohkuku/yokuli_app.git
cd yokuli_app
git checkout claude/vessel-control-app-jeJzm

# 2. 获取依赖
flutter pub get

# 3. 运行（Android 或 iOS）
flutter run

# iOS 首次运行需要额外执行
cd ios && pod install && cd ..
flutter run
```

---

### Signal K 连接

1. 首页点击 **Signal K Hub**
2. 填写主机 IP 和端口（默认端口 3000）
3. 点击 **Connect（连接）**

开启「启动时自动连接」后，App 启动时自动接入。如果连接成功但 60 秒内无数据，会自动断线重连（处理服务器重启后 TCP 半开连接问题）。

---

### 局域网多设备同步

**主机设备（舵手站、图表仪平板）：**
1. 进入 **设置 → LAN Sync → Host (Master)**
2. 记下显示的 WS 地址（如 `ws://192.168.1.5:8765`）
3. 开启「启动时自动连接 LAN」
4. 连接 Signal K

**客户端设备（驾驶舱平板、手机）：**
1. 进入 **设置 → LAN Sync → Client**
2. 填写主机 IP（或点击「扫描主机」自动发现）
3. 点击 **CONNECT LAN** 按钮

---

### 主要依赖

| 包 | 用途 |
|----|------|
| `flutter_riverpod` | 状态管理 |
| `go_router` | 页面路由 |
| `web_socket_channel` | Signal K + LAN 客户端 |
| `shelf` + `shelf_web_socket` | LAN 主机 WebSocket 服务器 |
| `flutter_map` | AIS 地图叠加（OpenStreetMap 瓦片） |
| `latlong2` | 地理坐标类型 |
| `path_provider` | 本地 JSON 文件存储 |
| `shared_preferences` | 设置持久化 |
| `geolocator` | 设备 GPS（MOB 位置备用） |

---

### 路线图

- [ ] 天气模块（OpenWeatherMap / Windy API）
- [ ] 锚泊报警（GPS 漂移检测）
- [ ] NMEA 0183 TCP 输入
- [ ] 离线地图瓦片缓存
- [ ] 航行日志 GPX / CSV 导出
- [ ] 告警推送通知
- [ ] 潮汐数据（离线表格）
- [ ] 暗色 / 红光夜视模式切换

---

<a name="english"></a>

## English Documentation

> 🇨🇳 [切换中文](#中文)

### Overview

Yokuli is a Flutter-based marine vessel control app for Android, iOS, and **Web**. Designed to feel like a "Marine OS" — a launcher-style interface with modular panels for Signal K data, instruments, power management, safety, AIS radar, voyage logging, and a Kanban task board. Supports real-time multi-device data sharing over LAN.

**Web limitations:** Browsers cannot run a server, so the web version acts only as a Client — connect to a Host running on a native (Android/iOS) device. Signal K direct connection works normally.

### Status

> **Branch:** `claude/vessel-control-app-jeJzm`
> **Last updated:** 2026-03-30
> **Build status:** ✅ Source complete — ready for `flutter pub get && flutter run`

---

### Modules

| Module | Status | Description |
|--------|--------|-------------|
| Signal K Hub | ✅ | WebSocket client, host IP + port input, auto-reconnect, 60s stale-data watchdog |
| Dashboard | ✅ | SOG, COG compass, wind, depth, GPS, batteries |
| Power | ✅ | Battery cards (SOC, voltage, current), solar charge controllers (panel V/A/W) |
| AIS | ✅ | Map overlay radar (OSM tiles, pinch-to-zoom), polar chart radar, target list, CPA risk |
| Voyage | ✅ | Voyage timer, quick-log buttons, event list (delete + GPS details), history |
| System Log | ✅ | Global event feed, filterable by type |
| Safety | ✅ | MOB trigger (GPS + LAN broadcast), depth/speed alarms, cancel-MOB broadcast |
| Kanban Board | ✅ | Ship tasks board (待办/进行中/已完成), custom columns, cards with category + priority |
| Weather | 🔲 Stub | Entry point reserved |
| Tools | 🔲 Stub | Entry point reserved |
| Settings | ✅ | Vessel name, SK host IP + port, LAN role, Connect/Disconnect button, auto-connect |

---

### Architecture

```
MVVM + Riverpod (manual Notifier, no code generation required)
Feature-first directory structure
JSON file persistence (path_provider) for logs, voyages, kanban
SharedPreferences for settings
go_router for navigation
```

#### Multi-device LAN Sync

```
Host device                     Client device(s)
  │                                  │
Signal K WS ──► VesselState          │
  │                                  │
  └──► shelf WS server :8765 ─────► WS client ──► VesselState

Discovery: UDP broadcast on port 43215 (auto) + manual IP entry (fallback)
```

**Device roles (Settings screen):**
- **Standalone** — direct Signal K connection only, no LAN sync
- **Host (Master)** — collects Signal K data, serves LAN peers via WebSocket (native only)
- **Client** — receives all data from host, Signal K tile hidden on home screen (Web is always Client)

---

### Setup

**Prerequisites**
- Flutter SDK ≥ 3.3.0 (stable channel)
- Android SDK or Xcode for iOS

**First run**

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

---

### Signal K Connection

1. Open **Signal K Hub** from the home screen
2. Enter the server host IP and port (default: 3000)
3. Tap **Connect**

Enable **Auto-connect** to connect automatically on app launch. If the connection appears live but no data is received for 60 seconds (e.g. after a server restart), the client automatically forces a reconnect to clear any stale TCP half-open connections.

---

### LAN Sync Setup

**On the host device (helm station, chartplotter tablet):**
1. Go to **Settings → LAN Sync → Host (Master)**
2. Note the WS address shown (e.g. `ws://192.168.1.5:8765`)
3. Enable **Auto-start LAN sync on launch**
4. Connect this device to Signal K

**On client devices (cockpit tablet, phone):**
1. Go to **Settings → LAN Sync → Client**
2. Enter the host IP (or tap **Scan for hosts**)
3. Tap **CONNECT LAN**

---

### Key Packages

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Navigation |
| `web_socket_channel` | Signal K + LAN client |
| `shelf` + `shelf_web_socket` | LAN host WebSocket server |
| `flutter_map` | AIS map overlay (OpenStreetMap tiles) |
| `latlong2` | Geographic coordinate types |
| `path_provider` | Local JSON file storage |
| `shared_preferences` | Settings persistence |
| `geolocator` | Device GPS for MOB position fallback |

---

### Roadmap

- [ ] Weather module (OpenWeatherMap / Windy API)
- [ ] Anchor alarm (GPS drift detection)
- [ ] NMEA 0183 TCP input
- [ ] Offline map tile caching
- [ ] Voyage log GPX/CSV export
- [ ] Push notifications for alarms
- [ ] Tidal data (offline tables)
- [ ] Dark/dim mode toggle (red night vision mode)
