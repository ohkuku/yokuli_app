# Yokuli — 智能船舶管理平台

基于 Flutter 的海洋船控应用，支持 Android、iOS 和 Web。以「船载操作系统」为设计理念，launcher 风格首页组织各功能模块，接入 Signal K 服务器获取实时传感器数据，支持多设备局域网自动同步。

## 功能总览

| 模块 | 说明 |
|------|------|
| **Signal K Hub** | WebSocket 客户端，连接 Signal K 服务器获取航行数据（航速、航向、风速、水深、电池等），支持用户名/密码认证，自动重连，60s 无数据自动断线重连 |
| **仪表盘** | 航速（SOG）、航向罗盘（COG/HDG）、真风/视风（TWS/AWS/AWA）、水深（DBK/DBS）、GPS 位置、电池状态 |
| **电力管理** | 多电池组卡片（SOC、电压、电流、温度），太阳能充电控制器面板（面板电压/电流/功率/日发电量） |
| **AIS** | OpenStreetMap 地图叠加 + 极坐标雷达 + 目标列表，CPA/TCPA 风险分析，MMSI 详情 |
| **航程** | 航程计时，快速日志按钮（天气/帆况/事件），事件列表含 GPS 详情，历史航程列表 |
| **船务看板** | Kanban 看板（自定义列），卡片含分类/优先级/标签，拖拽排序 |
| **告警中心** | 自定义告警规则（支持持续时间、滞后带、冷却期），告警实例管理（确认/解除/贪睡），审计日志 |
| **MOB** | 长按 1.2s 触发落水警报，GPS 定位 + 距离方位计算，LAN 广播同步所有设备，自动规则触发（Signal K notifications 路径） |
| **天气** | iOS 风格动画天气背景（基于 WMO 天气码 + 日出日落），Open-Meteo 免费 API（可选 MetService NZ），Signal K GPS 优先，设备 GPS 兜底 |
| **系统日志** | 全局事件流（导航/系统/MOB/告警），按类型过滤 |
| **设置** | 设备名、船名、Signal K 配置、LAN 设备列表、同步状态诊断、天气数据源、屏幕常亮 |

## 多设备同步

所有原生设备（Android/iOS）同时运行 WebSocket 服务器和客户端。通过 UDP 广播（端口 43215）自动发现同网段设备，连接后自动交换同步游标，增量推送差异数据。

**同步范围：**
- 航程、任务、问题、日志、看板（列+卡片）— 游标增量同步（LWW 合并）
- 告警规则、告警实例、告警动作 — 游标增量同步
- MOB 警报/取消 — 实时广播
- MOB 规则 — 实时广播 + 首次连接推送
- 船名、Signal K 配置、告警阈值、首页布局、屏幕常亮、语言 — settings_sync 推送
- 通知渠道配置 — 实时广播
- 船舶状态（VesselState）— 2Hz 持续广播

**冲突解决：** Last-Write-Wins (LWW)，按 `updatedAt` 时间戳 → 软删除标记 → `sourceDeviceId` 字典序三级判定。

**首次加入：** 新设备只需填写设备名，连接后自动从已有设备拉取全部配置和数据。

**Web 限制：** 浏览器无法运行 WebSocket 服务器，只能作为 Client 连接到原生设备。

## 快速开始

```bash
git clone https://github.com/ohkuku/yokuli_app.git
cd yokuli_app
git checkout claude/vessel-control-app-jeJzm
flutter pub get
flutter run
```

**环境要求：** Flutter SDK ≥ 3.3.0（stable），Android SDK 或 Xcode。

## Signal K 连接

1. 首页点击 **Signal K Hub**
2. 填写主机地址和端口（默认 3000）
3. 点击连接

支持用户名/密码认证。开启「自动连接」后每次启动自动接入。连接后 60 秒内无数据自动重连（处理服务器重启后的 TCP 半开连接）。

## 主要依赖

| 包 | 用途 |
|----|------|
| `flutter_riverpod` | 状态管理（手写 Notifier，无 codegen） |
| `go_router` | 页面路由 |
| `web_socket_channel` | Signal K + LAN 客户端 WebSocket |
| `shelf` + `shelf_web_socket` | LAN WebSocket 服务器（原生端） |
| `flutter_map` + `latlong2` | AIS 地图叠加（OpenStreetMap 瓦片） |
| `path_provider` | 本地 JSON 文件持久化 |
| `shared_preferences` | 设置持久化 |
| `geolocator` | 设备 GPS（天气定位 + MOB 位置兜底） |
| `http` | 天气 API、Signal K REST |
| `hive_flutter` | 备用本地存储 |
| `intl` | 日期时间格式化 |
| `package_info_plus` | 应用版本检查 |

## 项目结构

```
lib/
├── main.dart                          # 入口
├── app.dart                           # MaterialApp + ProviderScope
├── router/app_router.dart             # GoRouter 路由定义
├── core/
│   ├── models/                        # 数据模型（VesselState, AlarmRule, MobAlert, etc.）
│   ├── providers/                     # Riverpod 状态管理
│   ├── services/
│   │   ├── signalk/                   # Signal K 客户端/解析器/认证
│   │   ├── lan_sync/                  # LAN 多设备同步基础设施
│   │   ├── alarm_evaluator.dart       # 告警条件持续评估引擎
│   │   ├── alarm_dispatcher.dart      # 告警响应分发
│   │   ├── data_export_service.dart   # 数据导入/导出
│   │   ├── telemetry_service.dart     # 连接/同步遥测
│   │   └── update/                    # 应用更新检查
│   ├── sync/                          # 同步引擎（LWW 合并 + 游标存储）
│   ├── theme/                         # 深色主题 + 颜色系统
│   ├── l10n/                          # 国际化字符串（中文/英文）
│   ├── utils/                         # ID 生成等工具
│   └── widgets/                       # 共享 UI 组件（GlassCard 等）
└── features/
    ├── home/                          # 首页 launcher + 天气背景
    ├── startup/                       # 启动页 + 首次配置向导
    ├── dashboard/                     # 航行仪表盘
    ├── signalk/                       # Signal K 连接管理
    ├── power/                         # 电力管理
    ├── ais/                           # AIS 雷达 + 地图
    ├── voyage/                        # 航程管理
    ├── logbook/                       # 系统日志
    ├── kanban/                        # 船务看板
    ├── alarm_center/                  # 告警中心 + 规则编辑
    ├── alarm_management/              # 告警配置管理
    ├── safety/                        # 安全设置（深度/速度告警阈值）
    ├── mob/                           # MOB 落水警报
    ├── weather/                       # 天气详情页
    ├── issues/                        # 问题追踪
    ├── tasks/                         # 任务管理
    ├── maintenance/                   # 维护记录
    └── settings/                      # 系统设置
```
