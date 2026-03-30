<div align="center">

# Yokuli

**船控平台 · Vessel Control Platform**

*Flutter · Android · iOS*

<br/>

[**中文**](#中文)　·　[**English**](#english)

</div>

---

<a name="中文"></a>

## 中文文档

> 🇬🇧 [Switch to English](#english)

### 简介

Yokuli 是一款基于 Flutter 的海洋船控 App，面向 Android 和 iOS 双平台。界面风格类似「船载操作系统」—— 以 launcher 方式组织各功能模块，接入 Signal K 服务器实时数据，支持多设备局域网数据共享。

### 当前状态

> **分支：** `claude/vessel-control-app-jeJzm`
> **最后更新：** 2026-03-30
> **构建状态：** ✅ 源码完整，执行 `flutter pub get && flutter run` 即可运行

---

### 功能模块

| 模块 | 状态 | 说明 |
|------|------|------|
| Signal K Hub | ✅ | WebSocket 客户端，Delta 解析，自动重连 |
| 仪表盘 | ✅ | 航速、航向罗盘、风速风向、水深、GPS、电池 |
| 电力管理 | ✅ | 电池卡片，SOC 进度条，电压 / 电流 |
| 航行日志 | ✅ | 手动 + 自动条目（离港/到港/航点/MOB），左滑删除 |
| 安全 | ✅ | MOB 触发（记录 GPS + 广播到所有设备），深度 / 速度告警 |
| 维护记录 | ✅ | 任务清单，循环周期，逾期提示，标记完成 |
| 天气 | 🔲 占位 | 入口已预留，功能待实现 |
| 小工具 | 🔲 占位 | 入口已预留，功能待实现 |
| 设置 | ✅ | 船名、Signal K 地址、LAN 角色、自动连接 |

---

### 架构说明

```
MVVM + Riverpod（手写 Notifier，无需 code generation）
Feature-first 目录结构
Hive（无 TypeAdapter，存原始 Map）用于日志 / 维护存储
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
- **主机 (Host/Master)** — 汇聚 Signal K 数据，通过 WebSocket 向局域网客户端广播
- **客户端 (Client)** — 从主机接收所有数据，无需独立连接 Signal K

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

**重新生成平台文件（可选）**

```bash
# 仅重新生成平台脚手架，不影响 lib/ 代码
flutter create --project-name yokuli_app --org com.yokuli .
```

---

### Signal K 连接

1. 首页点击 **Signal K Hub**
2. 填写 WebSocket 地址：`ws://<服务器IP>:3000/signalk/v1/stream`
3. 点击 **Connect（连接）**

Signal K 默认端口为 **3000**。开启「启动时自动连接」后，App 启动时自动接入。

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
3. 点击「重启 LAN 同步」

之后所有客户端设备均可实时接收来自主机的船舶数据。

---

### 主要依赖

| 包 | 用途 |
|----|------|
| `flutter_riverpod` | 状态管理 |
| `go_router` | 页面路由 |
| `web_socket_channel` | Signal K + LAN 客户端 |
| `shelf` + `shelf_web_socket` | LAN 主机 WebSocket 服务器 |
| `hive_flutter` | 本地存储（日志、维护记录） |
| `shared_preferences` | 设置持久化 |
| `geolocator` | 设备 GPS（MOB 位置备用） |

---

### 路线图

- [ ] 天气模块（OpenWeatherMap / Windy API）
- [ ] NMEA 0183 TCP 输入（原始语句解析器）
- [ ] 锚泊报警（GPS 漂移检测）
- [ ] 潮汐数据（离线表格）
- [ ] 单位换算 + 计算工具
- [ ] 航行日志 GPX / CSV 导出
- [ ] 告警推送通知
- [ ] 暗色 / 红光夜视模式切换

---

<a name="english"></a>

## English Documentation

> 🇨🇳 [切换中文](#中文)

### Overview

Yokuli is a Flutter-based marine vessel control app for Android and iOS. Designed to feel like a "Marine OS" — a launcher-style interface with modular panels for Signal K data, instruments, power management, safety, logbook, and maintenance. Supports real-time multi-device data sharing over LAN.

### Status

> **Branch:** `claude/vessel-control-app-jeJzm`
> **Last updated:** 2026-03-30
> **Build status:** ✅ Source complete — ready for `flutter pub get && flutter run`

---

### Modules

| Module | Status | Description |
|--------|--------|-------------|
| Signal K Hub | ✅ | WebSocket client, delta parser, auto-reconnect |
| Dashboard | ✅ | SOG, COG compass, wind, depth, GPS, batteries |
| Power | ✅ | Battery cards with SOC gauges, voltage, current |
| Logbook | ✅ | Manual + auto entries (departure/arrival/waypoint/MOB), swipe-to-delete |
| Safety | ✅ | MOB trigger with GPS + LAN broadcast, depth/speed alarms |
| Maintenance | ✅ | Task list with recurrence, overdue tracking, mark-done |
| Weather | 🔲 Stub | Entry point reserved |
| Tools | 🔲 Stub | Entry point reserved |
| Settings | ✅ | Vessel name, Signal K URL, LAN role, auto-connect |

---

### Architecture

```
MVVM + Riverpod (manual Notifier, no code generation required)
Feature-first directory structure
Hive (no TypeAdapters) for logbook/maintenance storage
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
- **Host (Master)** — collects Signal K data, serves LAN peers via WebSocket
- **Client** — receives all data from host, no Signal K connection needed

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

**Regenerate platform files (optional)**

```bash
# Overwrites platform scaffolding only, does not touch lib/
flutter create --project-name yokuli_app --org com.yokuli .
```

---

### Signal K Connection

1. Open **Signal K Hub** from home screen
2. Enter WebSocket URL: `ws://<server-ip>:3000/signalk/v1/stream`
3. Tap **Connect**

Default Signal K port is **3000**. Enable **Auto-connect** to connect on app launch.

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
3. Tap **Restart LAN sync**

All client devices will now receive live vessel data from the host.

---

### Key Packages

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

### Roadmap

- [ ] Weather module (OpenWeatherMap / Windy API)
- [ ] NMEA 0183 TCP input (raw sentence parser)
- [ ] Anchor alarm (GPS drift detection)
- [ ] Tidal data (offline tables)
- [ ] Unit converter + calculator tools
- [ ] Logbook GPX/CSV export
- [ ] Push notifications for alarms
- [ ] Dark/dim mode toggle (red night vision mode)
