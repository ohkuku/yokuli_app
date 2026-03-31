# Yokuli 技术架构文档

## 1. 总体架构

```
MVVM + Riverpod（手写 Notifier，无需 code generation）
Feature-first 目录结构
JSON 文件持久化（path_provider）+ SharedPreferences
go_router 声明式路由
```

### 技术栈
- **框架**: Flutter 3.3+, Dart
- **状态管理**: flutter_riverpod (Notifier pattern)
- **路由**: go_router (GoRouter)
- **网络**: web_socket_channel (WS 客户端), shelf + shelf_web_socket (WS 服务器)
- **地图**: flutter_map + latlong2 (OpenStreetMap)
- **持久化**: path_provider (JSON 文件), shared_preferences (KV 存储)
- **定位**: geolocator + permission_handler

## 2. 数据模型

### 2.1 VesselState — 船舶实时状态

核心实时数据模型，汇聚来自 Signal K 的所有传感器数据。

| 字段 | 类型 | JSON Key | 说明 |
|------|------|----------|------|
| speedOverGround | double? | `sog` | 对地速度 (kn) |
| courseOverGround | double? | `cog` | 对地航向 (°true) |
| heading | double? | `hdg` | 罗经航向 (°true) |
| position | GpsPosition? | `pos` | GPS 位置 |
| trueWindSpeed | double? | `tws` | 真风速 (kn) |
| trueWindDirection | double? | `twd` | 真风向 (°true) |
| apparentWindSpeed | double? | `aws` | 视风速 (kn) |
| apparentWindAngle | double? | `awa` | 视风角 (°, ±180) |
| depthBelowKeel | double? | `dbt` | 龙骨下水深 (m) |
| depthBelowSurface | double? | `dbs` | 水面下水深 (m) |
| batteries | Map\<String, BatteryState\> | `batteries` | 电池组 |
| solar | Map\<String, SolarChargeControllerState\> | `solar` | 太阳能控制器 |
| powerSummary | PowerSummaryState? | `ps` | 电力汇总 |
| aisTargets | Map\<String, AisTargetState\> | `aisTargets` | AIS 目标 |
| aisOwnShip | AisOwnShipState? | `aisOwn` | 本船 AIS 信息 |
| lastUpdated | DateTime | `ts` | 最后更新时间 |
| sourceDeviceId | String? | `src` | 数据来源设备 |

**GpsPosition**: `latitude` (lat), `longitude` (lon), `altitude?` (alt), `timestamp` (ts)
包含 `distanceTo()` (海里) 和 `bearingTo()` (°true) 辅助方法。

**BatteryState**: `id`, `name`, `voltage?` (v), `current?` (a), `stateOfCharge?` (soc, 0~1), `temperature?` (temp), `lastUpdated` (lu), `status` (s, enum index)

**BatteryStatus**: `normal | warning | critical | stale | noData`

### 2.2 AlarmRule — 告警规则

| 字段 | 类型 | JSON Key | 说明 |
|------|------|----------|------|
| id | String | `id` | UUID |
| name | String | `name` | 规则名称 |
| enabled | bool | `enabled` | 是否启用 |
| level | AlarmLevel | `level` | critical/warning/info |
| condition | AlarmCondition | `condition` | 触发条件 |
| responsePlan | AlarmResponsePlan | `responsePlan` | 响应策略 |
| snoozeMins | int | `snoozeMins` | 贪睡时间(分钟) |
| isBuiltIn | bool | `isBuiltIn` | 是否内置规则 |
| deleted | bool | `del` | 软删除标记 |
| updatedAt | DateTime | `ua` | LWW 时间戳 |
| sourceDeviceId | String | `src` | 来源设备 |

**AlarmCondition**:
- `source`: vesselMetric / signalK
- `metric`: 指标 key (sog, depth_keel, battery_voltage_main, wind_true_speed 等)
- `operator`: >= / <= / > / < (含 hysteresis 恢复判定)
- `threshold`: 阈值
- `sustainMs`: 持续时间要求 (ms)
- `hysteresis`: 滞后带
- `cooldownMs`: 冷却期 (ms)

**内置预设规则**: Shallow Water (depth_keel ≤ 3m), High Speed (sog ≥ 20kn), Battery Low (≤ 11.8V), Battery Critical (≤ 11.5V), High Wind (tws ≥ 20kn)

### 2.3 AlarmInstance — 告警实例

告警条件触发后生成的实例记录。

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| ruleId | `ruleId` | 关联规则 |
| ruleName | `rn` | 规则名快照 |
| level | `level` | 告警级别 |
| message | `msg` | 描述信息 |
| triggeredValue | `tv` | 触发时的数值 |
| triggeredAt | `ta` | 触发时间 |
| acknowledgedAt | `ackAt` | 确认时间 |
| clearedAt | `clAt` | 解除时间 |
| snoozedUntil | `snUntil` | 贪睡截止时间 |
| status | `status` | active/acknowledged/cleared/snoozed |
| updatedAt | `ua` | LWW 时间戳 |
| sourceDeviceId | `src` | 来源设备 |

### 2.4 AlarmAction — 告警操作审计

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| instanceId | `iid` | 关联实例 |
| action | `action` | acknowledge/clear/snooze/escalate |
| performedBy | `by` | 操作设备 |
| performedAt | `at` | 操作时间 |
| note | `note` | 备注 |
| updatedAt | `ua` | LWW 时间戳 |
| sourceDeviceId | `src` | 来源设备 |

### 2.5 MobAlert — 落水警报

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| triggeredAt | `ts` | 触发时间 |
| position | `pos` | GPS 位置 (GpsPosition) |
| triggeredByDevice | `by` | 触发设备 |
| isActive | `active` | 是否活跃 |
| triggerSource | `src` | manual / rule |
| triggerRuleName | `rn` | 触发规则名 |
| clearedAt | `clAt` | 解除时间 |

### 2.6 MobTriggerRule — MOB 自动触发规则

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| name | `name` | 规则名 |
| enabled | `enabled` | 是否启用 |
| type | `type` | signalkNotification / (未来扩展) |
| config | `config` | 规则参数 (pathPattern, states) |
| updatedAt | `ua` | 更新时间 |

**signalkNotification 类型配置**:
- `pathPattern`: Signal K notifications 路径子串匹配 (如 `mob`)
- `states`: 触发状态列表 (如 `['emergency', 'alarm']`)

### 2.7 Voyage — 航程

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| startTime | `st` | 开始时间 |
| endTime | `et` | 结束时间 |
| events | `events` | 事件列表 (VoyageEvent) |
| startPosition | `sp` | 起始位置 |
| endPosition | `ep` | 结束位置 |
| updatedAt | `ua` | LWW 时间戳 |
| sourceDeviceId | `sdid` | 来源设备 |

### 2.8 Task / TaskInstance — 任务

**TaskCategory**: preDeparture, postArrival, periodic, safety, custom
**TaskRecurrence**: none, daily, weekly, monthly, perVoyage
**TaskStatus**: open, inProgress, done, skipped

TaskInstance 包含 checklist items，每项有 pending/done/issue 状态，可关联 Issue。

### 2.9 Issue — 问题

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| title | `title` | 标题 |
| description | `desc` | 描述 |
| status | `status` | open/inProgress/resolved/closed |
| priority | `priority` | low/medium/high/critical |
| notes | `notes` | 备注列表 |
| createdAt | `ca` | 创建时间 |
| updatedAt | `ua` | LWW 时间戳 |
| sourceDeviceId | `sdid` | 来源设备 |

### 2.10 LogEntry — 日志条目

| 字段 | JSON Key | 说明 |
|------|----------|------|
| id | `id` | UUID |
| timestamp | `ts` | 时间 |
| type | `type` | nav/system/mob/alarm/weather/custom |
| subtype | `sub` | 子类型 |
| message | `msg` | 消息 |
| position | `pos` | GPS 位置 |
| updatedAt | `ua` | LWW 时间戳 |
| sourceDeviceId | `src` | 来源设备 |

### 2.11 Kanban — 看板

**KanbanColumn**: `id`, `title`, `order`, `updatedAt` (ua), `sourceDeviceId` (src)
**KanbanCard**: `id`, `columnId`, `title`, `description`, `category`, `priority`, `order`, `updatedAt` (ua), `sourceDeviceId` (src)

### 2.12 WeatherState — 天气状态

| 字段 | 说明 |
|------|------|
| temperature | 温度 (°C) |
| apparentTemperature | 体感温度 |
| condition | WeatherCondition enum |
| weatherCode | WMO 天气码 |
| windSpeed | 风速 (kn) |
| windDirection | 风向 (°) |
| precipitation | 降水 (mm) |
| description | 天气描述 |
| isLoading | 加载中 |
| error | 错误信息 |

**WeatherCondition**: clearDay, clearNight, partlyCloudy, cloudy, foggy, drizzle, rain, heavyRain, snow, thunderstorm

**WeatherSkyTheme**: 每种天气条件 × 时段（夜晚/日出/白天/日落）对应不同渐变色 + 粒子特效（星星/云/雨/雪/雾/极光）

## 3. Provider 体系

### 3.1 核心 Provider

| Provider | 类型 | 状态 | 持久化 | 同步 |
|----------|------|------|--------|------|
| `settingsProvider` | Notifier\<AppSettings\> | 全局设置 | SharedPreferences | settings_sync 广播 |
| `deviceProvider` | Notifier\<DeviceInfo\> | 设备 ID + stateVersion | SharedPreferences | — |
| `vesselProvider` | Notifier\<VesselState\> | 实时船舶状态 | 不持久化 | 2Hz 广播 |
| `connectionProvider` | Notifier\<ConnectionState\> | SK/LAN 连接状态 | 不持久化 | — |
| `localeProvider` | Notifier\<String\> | 语言代码 | SharedPreferences | settings_sync |
| `weatherProvider` | Notifier\<WeatherState\> | 天气数据 | 不持久化 | — |

### 3.2 数据 Provider

| Provider | 持久化 | 同步集合 | 广播消息类型 |
|----------|--------|----------|------------|
| `logProvider` | JSON 文件 | `logs` | `log_append` |
| `alarmProvider` | JSON 文件 | `alarms` | `alarm` |
| `taskProvider` | JSON 文件 | `tasks` | `task_upsert` |
| `issueProvider` | JSON 文件 | `issues` | `issue_upsert` |
| `voyageProvider` | JSON 文件 | `voyages` | `voyage_upsert` |
| `kanbanProvider` | JSON 文件 | `kanban_columns`, `kanban_cards` | `kanban_sync` |
| `alarmRuleProvider` | JSON 文件 | `alarm_rules` | `alarm_rules_sync` |
| `alarmInstanceProvider` | JSON 文件 | `alarm_instances` | `alarm_instance_sync` |
| `alarmActionProvider` | JSON 文件 | `alarm_actions` | `alarm_action_sync` |

### 3.3 功能 Provider

| Provider | 说明 |
|----------|------|
| `mobProvider` | MOB 状态 + 规则 + 历史 (JSON 文件持久化) |
| `safetyProvider` | 深度/速度告警阈值 (SharedPreferences) |
| `alarmRuleProvider` | 告警规则管理 + 内置规则合并 |
| `notifyChannelProvider` | 通知渠道配置 (Discord webhook) |
| `aisProvider` | AIS 目标状态 (不持久化) |
| `powerProvider` | 电力状态 (不持久化) |
| `lanBroadcastProvider` | LAN 广播函数 (StateProvider) |

## 4. 通信架构

### 4.1 Signal K 连接

```
SignalKClient (signalk_client.dart)
  ├── WebSocket → ws://host:port/signalk/v1/stream?subscribe=all
  ├── 认证: SignalKAuth.login() → JWT token
  ├── 解析: SignalKParser → VesselState (导航+风+深度+电池)
  │         SignalKParserAis → AIS 目标
  │         SignalKParserPower → 太阳能/电力汇总
  ├── 订阅: navigation.*, environment.wind.*, environment.depth.*,
  │         electrical.batteries.*, notifications.*, sensors.raw_nmea
  ├── 看门狗: 60s 无数据 → 自动重连
  └── onRawDelta → MobWatcherService (MOB 自动规则评估)
```

### 4.2 LAN 多设备同步

#### 网络拓扑

```
每台原生设备同时运行:
  ├── WebSocket 服务器 (SyncHost, 端口 8765)
  └── WebSocket 客户端 (SyncClient, 连接到发现的 peer)

发现方式:
  ├── UDP 广播 (端口 43215, 每 5 秒)
  │   └── 载荷: {name, port, deviceId, stateVersionMs}
  └── TCP 子网扫描 (备用)

Web 端: 仅 Client 模式，手动输入 Host IP
```

#### 消息类型

| 消息类型 | 方向 | 说明 |
|----------|------|------|
| `sync_hello` | 双向 | 连接握手，交换游标 |
| `sync_changes` | 双向 | 批量记录推送 (含 eventId 去重) |
| `settings_sync` | 双向 | 设置同步 (船名/SK/告警阈值/规则/通知) |
| `sk_credentials` | Host→Client | Signal K 凭证推送 |
| `mob` | 广播 | MOB 警报 |
| `mob_cancel` | 广播 | MOB 取消 |
| `mob_rule_sync` | 广播 | MOB 规则增删改 |
| `alarm_rules_sync` | 广播 | 告警规则更新 |
| `alarm_instance_sync` | 广播 | 告警实例更新 |
| `alarm_action_sync` | 广播 | 告警操作记录 |
| `notify_channel_sync` | 广播 | 通知渠道配置 |
| `log_append` | 广播 | 日志追加 |
| `task_upsert` | 广播 | 任务更新 |
| `issue_upsert` | 广播 | 问题更新 |
| `voyage_upsert` | 广播 | 航程更新 |
| `kanban_sync` | 广播 | 看板全量同步 |
| `vessel_state` | Host→Client | 2Hz 船舶状态广播 |
| `vessel_state_push` | Client→Host | 客户端 SK 数据上行 |
| `network_join_sync` | 广播 | 新设备加入通知 |
| `ping` / `pong` | 双向 | 心跳 (15s 间隔, 35s 超时) |

#### 同步流程

```
设备 B 连接到设备 A:

1. B → A: sync_hello {deviceId, cursors: {logs: "2024-...", tasks: "2024-..."}}
2. A → B: sync_changes {collection: "logs", records: [...], eventId: "..."}
   A → B: sync_changes {collection: "alarm_rules", records: [...]}
   A → B: settings_sync {vesselName, skHost, alarmRules, notifyChannel, ...}
   A → B: mob {data: alert}  (if active)
   A → B: mob_rule_sync {data: rule}  (for each rule)
3. B → A: sync_changes {collection: "logs", records: [...]}  (B's data)
```

#### 游标增量同步

- 每个设备维护 per-collection 的 `updatedAt` 高水位游标 (SharedPreferences)
- 连接时只发送 peer 游标之后的新记录
- SyncEngine.missingFor() 计算增量

#### LWW 冲突解决

```dart
SyncEngine.merge(existing, incoming):
  1. incoming.ua > existing.ua → 用 incoming
  2. ua 相等 → 软删除(del=true)优先
  3. ua 相等 + del 相等 → sourceDeviceId 字典序大的优先
```

### 4.3 广播函数

```dart
lanBroadcastProvider = (msg) {
  msg['_sv'] = stateVersion;     // 嵌入状态版本
  msg['_id'] = deviceId;          // 嵌入设备 ID
  _platform.broadcastJson(msg);   // → 所有 WS 客户端
  _platform.sendJson(msg);        // → 上游 Host
};
```

## 5. 告警评估引擎

`AlarmEvaluator` 持续监听 VesselState 变化，对每条启用的 AlarmRule 评估条件:

```
VesselState 变化
  └── 遍历 activeAlarmRules
      └── 提取指标值 (extractMetric)
          └── 判断条件 (operator.evaluate)
              ├── 首次满足 → 记录 _conditionFirstTrueAt
              ├── 持续 ≥ sustainMs → 触发 AlarmInstance
              │   └── 检查冷却期 cooldownMs
              └── 恢复 (isRecovered with hysteresis) → 清除
```

## 6. MOB 系统

### 触发方式
1. **手动**: 首页 MOB 按钮长按 1.2s
2. **自动规则**: MobWatcherService 监听 Signal K raw delta，匹配 `notifications.*` 路径

### 状态管理
- `MobState`: activeMob + rules + history (最近 50 条)
- 触发时广播到所有设备，所有设备共同进入 MOB 页面
- 取消时广播 mob_cancel，所有设备更新状态

### MOB 按钮交互
- 触摸即开始计时 (环形进度 + 震动)
- 1.2s 后触发 MOB (重震动)
- 拖拽 > 8px 切换为移动按钮模式
- 短按 (150ms~1.2s) 打开 MOB 页面但不触发

## 7. 天气系统

### 数据获取
1. GPS 来源: Signal K vessel position 优先 → geolocator getLastKnownPosition → getCurrentPosition
2. API: Open-Meteo (免费, 全球) / MetService NZ (可选, 需 API key)
3. 自动刷新: 30 分钟间隔 + Signal K GPS 位置变化触发

### 天气视觉
- WMO 天气码 → WeatherCondition enum → WeatherSkyTheme
- 时段判定: 日出前后30分钟为 sunrise/sunset，白天/夜晚
- 渐变背景: TweenAnimationBuilder 3s 过渡动画
- 粒子特效: CustomPainter + RepaintBoundary (星星闪烁/云层漂移/雨滴/雪花/雾带/极光)

## 8. 路由

| 路径 | 页面 | 说明 |
|------|------|------|
| `/` | HomeScreen | 首页 launcher |
| `/dashboard` | DashboardScreen | 航行仪表盘 |
| `/signalk` | SignalKScreen | Signal K 连接管理 |
| `/power` | PowerScreen | 电力管理 |
| `/log` | LogScreen | 系统日志 |
| `/ais` | AisScreen | AIS 雷达 |
| `/voyage` | VoyageScreen | 航程管理 |
| `/voyage/:id` | VoyageDetailScreen | 航程详情 |
| `/kanban` | KanbanScreen | 船务看板 |
| `/mob` | MobScreen | MOB 落水警报 |
| `/alarm-center` | AlarmCenterScreen | 告警中心 |
| `/alarm-rule-edit` | AlarmRuleEditScreen | 告警规则编辑 |
| `/weather` | WeatherScreen | 天气详情 |
| `/settings` | SettingsScreen | 系统设置 |

所有非首页路由使用 220ms fade 过渡动画。

## 9. 主题系统

深色主题 (`AppColors`):
- 背景: `#0a0f1e` (深蓝黑)
- 卡片: `#111827` (深灰)
- 主色: `#22d3ee` (cyan)
- 模块色: 每个功能模块有独立强调色 (Signal K 蓝, Dashboard 绿, Power 黄, Safety 红, etc.)
- 玻璃效果: `GlassCard` (BackdropFilter blur + 半透明边框)

## 10. 启动流程

```
StartupScreen._runInit():
  1. 加载本地数据 (_loadLocalData)
     ├── 初始化 Telemetry
     ├── 加载 Settings, Safety, Device, Locale
     ├── 运行 SyncMigration
     ├── 加载 AlarmRules, NotifyChannel, AlarmInstances, AlarmActions
     ├── 并行加载 Voyage, Task, Issue, Log
     ├── 加载 MOB (rules + history)
     ├── 启动 AlarmEvaluator
     └── 绑定 LAN Sync 回调 (MOB, alarm, settings, etc.)
  2. 启动 LAN 同步
     ├── 启动 WS 服务器 (原生端)
     └── 启动 UDP 设备发现
  3. 设备搜索 (8 秒窗口)
  4. 连接 Signal K (如果已配置)
  5. 决策: 首次向导 or 进入应用
     ├── deviceName 为空 → 向导 (设备名 → [船名 → SK] or 自动加入)
     └── deviceName 已设置 → 直接进入
```

## 11. 国际化

- 中文 (zh) — 默认语言
- 英文 (en) — 保留支持
- 字符串表: `lib/core/l10n/strings.dart` (S 类, 约 200 个 key)
- 运行时切换: `localeProvider.setLanguage(code)` (变更会同步到 LAN 设备)
