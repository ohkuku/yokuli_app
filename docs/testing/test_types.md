# 自动化测试类型说明（Yokuli）

你说的“开俩或仨应用点着测看结果”的测试，一般叫：

## 1) Integration Test（集成测试）
- 覆盖多个模块协作（状态、路由、同步入口）。
- 在 Flutter 里通常用 `integration_test`。

## 2) End-to-End Test / E2E（端到端测试）
- 从用户操作到最终结果的完整链路测试。
- 常见工具：`integration_test`（应用内）、Appium、Maestro。

## 3) Multi-Device E2E（多设备端到端）
- 重点验证你现在最关心的场景：A/B/C 多设备同步、断线重连、冲突收敛。
- 这是“开俩或仨应用互相操作”的标准叫法。

---

## 当前仓库已接入的自动化层级

- `flutter analyze`：静态检查
- `flutter test`：单元 + widget
- `flutter test integration_test`：应用级集成测试

CI 位置：`.github/workflows/flutter-tests.yml`

---

## 下一步（多设备 E2E）建议

1. 构建双端/三端测试夹具（Host + Client + Client）。  
2. 先覆盖 3 条主链路：
   - MOB 触发/解除与页面跳转广播
   - 告警设置（水深/速度）双端实时一致
   - 断线期间编辑、重连后自动追最新
3. 再补冲突场景（同一 item 并发写，验证 LWW 收敛）。

