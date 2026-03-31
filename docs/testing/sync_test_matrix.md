# Yokuli 同步测试矩阵（原子操作 Pub/Sub）

> 目标：把“所有原子操作都发布订阅 + item 级时间戳合并 + 入网先同步”拆成可持续补齐的可执行用例。
>  
> 状态标记：`✅ 已自动化` / `🟡 部分自动化` / `⬜ 待补齐`

## 1) 入网与会话阶段

| ID | 场景 | 预期 | 自动化状态 | 位置 |
|---|---|---|---|---|
| JOIN-001 | `networkJoinInProgress=true` | 全局禁止编辑遮罩显示 | ✅ | `integration_test/app_join_sync_test.dart` |
| JOIN-002 | 入网开始 | 自动导航到 `/settings` | 🟡（需补路由断言） | `lib/app.dart` |
| JOIN-003 | 入网完成 | 解除编辑锁 | ⬜ | 待补 |
| JOIN-004 | 入网失败/断开 | 解除编辑锁并提示 | ⬜ | 待补 |

## 2) 设置与连接配置

| ID | 场景 | 预期 | 自动化状态 | 位置 |
|---|---|---|---|---|
| SET-001 | 仅改 `deviceName` | 不广播全局字段，避免覆盖其他设备 | ✅ | `test/settings_provider_sync_test.dart` |
| SET-002 | 改 `vesselName` | 只发变更字段 | ✅ | `test/settings_provider_sync_test.dart` |
| SET-003 | 改 `skUrl/skHost` | 远端可自动应用并连接 | ⬜ | 待补（集成） |
| SET-004 | 新设备入网后默认值不反向覆盖 | 全局字段保持已有最新值 | ⬜ | 待补（双端） |

## 3) Peer 发现与连接策略（P2P）

| ID | 场景 | 预期 | 自动化状态 | 位置 |
|---|---|---|---|---|
| PEER-001 | 自己发现自己 | 不连接 | ✅（策略层） | `test/lan_sync_connect_policy_test.dart` |
| PEER-002 | 已连接状态再次发现 | 不重复连接 | ✅（策略层） | `test/lan_sync_connect_policy_test.dart` |
| PEER-003 | 冷却窗口内重复发现 | 节流不重连 | ✅（策略层） | `test/lan_sync_connect_policy_test.dart` |
| PEER-004 | 首次发现可连接 peer | 发起连接 | ✅（策略层） | `test/lan_sync_connect_policy_test.dart` |
| PEER-005 | 两端同版本同时上线 | 仍可建连并开始同步 | ⬜（需双端集成） | 待补 |

## 4) 原子操作发布订阅（模块级）

| 模块 | 原子操作 | 期望事件 | 合并语义 | 自动化状态 |
|---|---|---|---|---|
| MOB | 触发/解除 | `mob` / `mob_cancel` | 实时广播 + 状态落库 | ⬜ |
| MOB 规则 | 增删改开关 | `mob_rule_sync` | LWW（`updatedAt`） | ⬜ |
| 告警设置（Safety） | 水深/速度开关与阈值 | `settings_sync` 子字段 | LWW（字段级） | ⬜ |
| 告警规则 | upsert/delete | `alarm_rules_sync` | LWW（item 级） | ⬜ |
| 告警实例 | trigger/ack/snooze/clear | `alarm_instance_sync` | LWW（item 级） | ⬜ |
| 告警动作 | append | `alarm_action_sync` | 追加 + LWW | ⬜ |
| 通知 | append/dismiss | `notification_sync` / `notification_receipt_sync` | LWW（item 级） | ⬜ |
| 任务 | create/update/complete/skip | `task_upsert` | LWW（item 级） | ⬜ |
| Issue | create/status/note | `issue_upsert` | LWW（item 级） | ⬜ |
| Voyage | start/end/rename/notes/delete | `voyage_upsert` | LWW（item 级） | ⬜ |
| Log | append/delete | `log_append` | LWW（item 级） | ⬜ |

## 5) 断线重连与增量追赶

| ID | 场景 | 预期 | 自动化状态 |
|---|---|---|---|
| CATCH-001 | A 编辑，B 离线后加入 | B 自动追到最新（不手动点同步） | ⬜ |
| CATCH-002 | 同一 item 双端并发编辑 | 按 `ua` + tombstone + src 规则收敛 | ⬜ |
| CATCH-003 | 全量重同步 | 清 cursor 后可完整恢复 | ⬜ |

## 6) 每次提交必跑

- CI 已配置：
  - `flutter analyze`
  - `flutter test`
  - `flutter test integration_test`
- 文件：`.github/workflows/flutter-tests.yml`

---

## 下一步补齐顺序（建议）

1. **双端集成基座**：创建 host/client 测试夹具（同进程双容器或 mock transport）。  
2. **优先补最痛点**：`MOB`、`Safety 告警设置`、`断线追赶` 3 条主链路。  
3. **再铺模块**：Task/Issue/Voyage/Notification/Alarm 实例动作。  
4. **最后补并发冲突**：同 item 双写收敛验证（严格 LWW）。

