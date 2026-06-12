# Feature Spec: BCI Bridge Server

## Metadata

| Field      | Value                        |
|------------|------------------------------|
| Feature ID | `FEAT-001`                   |
| Branch     | `feat/001-bci-bridge`        |
| Status     | Draft                        |
| Owner      | `qiujingyi.7`                |
| Date       | `2026-05-26`                 |

## Summary

将 HybridBCI 脑机接口数据从单机桌面应用的"孤岛"中解放出来。通过一个纯 Python 异步桥接服务器，以 TCP 客户端身份连接官方 BCI APP，接收 IPC 协议消息并通过 WebSocket/REST 透传给远程客户端。使用 Tailscale Funnel 实现公网 HTTPS 访问，使得 Web 前端、移动端、远程 AI 服务等任何公网客户端都能实时消费脑机接口数据并发送控制指令。

## User Scenarios

### US-001: 实时接收 BCI 算法结果 (P1)

**Priority**: P1

**Independent Test**:
1. 启动桥接服务器 `uv run server.py`
2. 启动官方 BCI APP，加载一个 BCI 范式（如 P300 或 SSVEP）
3. 用浏览器或 websocat 连接 `wss://<funnel-url>/ws`，发送鉴权消息 `{"type":"auth","token":"<token>"}`
4. 在官方 APP 中运行算法
5. 验证 WebSocket 收到 `{"msg":"ipc_algorithm_test","result_args":{"data":"..."}}` 格式的透传消息

**Acceptance Scenarios**:
- Given 桥接服务器已启动且官方 APP 已连接, When 算法输出一条结果, Then 所有已鉴权的 WebSocket 客户端收到透传的 `ipc_algorithm_test` 消息
- Given WebSocket 客户端未通过鉴权, When 客户端尝试接收数据, Then 连接被关闭，返回鉴权失败提示
- Given 官方 APP 未运行, When 客户端请求 WebSocket 连接并通过鉴权, Then 连接成功但收到 `{"msg":"bci_disconnected"}` 状态通知

### US-002: 远程发送控制指令 (P1)

**Priority**: P1

**Independent Test**:
1. 桥接已连接官方 APP
2. WebSocket 客户端 A 连接并通过鉴权
3. 客户端 A 发送 `{"msg":"ipc_test_start"}` → 桥接层透传到官方 APP
4. WebSocket 客户端 B 连接并通过鉴权
5. 客户端 B 发送 `{"msg":"ipc_test_stop"}` → 被拒绝，返回 `{"type":"error","reason":"control_owned_by_another_client"}`
6. 验证测试正常开始、只有控制权持有者能发指令

**Acceptance Scenarios**:
- Given 无人持有控制权, When 已鉴权客户端发送控制指令, Then 该客户端获得控制权，指令透传到官方 APP
- Given 客户端 A 持有控制权, When 客户端 B 发送控制指令, Then 指令被拒绝，返回错误消息
- Given 客户端 A 持有控制权, When 客户端 A 断开连接, Then 控制权自动释放
- Given REST 模式, When 已鉴权客户端 POST `/command`, Then 遵循相同的控制权互斥规则

### US-003: BCI 连接自动重连 (P1)

**Priority**: P1

**Independent Test**:
1. 桥接服务器已连接官方 APP
2. 强制关闭官方 APP（模拟崩溃）
3. 观察桥接日志：TCP 断开 → 指数退避重连（1s, 2s, 4s, 8s...）
4. WebSocket 客户端收到 `{"msg":"bci_disconnected"}`
5. 重新启动官方 APP → 桥接自动重连成功
6. WebSocket 客户端收到 `{"msg":"bci_connected"}`

**Acceptance Scenarios**:
- Given 官方 APP 正常运行, When 官方 APP 崩溃或关闭, Then 桥接层立即检测到断连，广播 `bci_disconnected`，进入指数退避重连
- Given 桥接层正在重连中, When 官方 APP 重新启动, Then 桥接层在下一个退避周期内重连成功，广播 `bci_connected`
- Given 桥接服务器刚启动, When 官方 APP 尚未运行, Then 桥接层持续重连，不阻塞 HTTP/WS 服务正常启动

### US-004: REST API 查询状态 (P2)

**Priority**: P2

**Independent Test**:
1. `GET /status` → 返回 JSON `{"bci_connected": false, "ws_clients": 0, "control_owner": null}`
2. TCP 连接建立后 → `bci_connected: true`

**Acceptance Scenarios**:
- Given 桥接服务器正常运行, When 客户端 GET `/status`, Then 返回当前连接状态、客户端数量、控制权持有者信息

## Requirements

### Functional Requirements

- **FR-001**: IPC TCP 客户端 — 使用纯 Python `asyncio` 实现与官方 BCI APP 的 TCP 连接，遵循 4 字节大端长度头 + JSON payload 协议格式
- **FR-002**: 协议透传 — 所有 IPC 消息原样转发，不做语义化转换
- **FR-003**: WebSocket 广播 — 从官方 APP 收到的所有消息广播给所有已鉴权的 WebSocket 客户端
- **FR-004**: 控制指令互斥 — 同一时间仅一个客户端持有控制权，其他客户端发送控制指令时收到错误响应。客户端断开时自动释放控制权
- **FR-005**: Token 鉴权 — REST 和 WebSocket 均需 `Authorization: Bearer <token>` 或等效鉴权。WebSocket 通过首条消息 `{"type":"auth","token":"xxx"}` 握手
- **FR-006**: 自动重连 — TCP 断开后自动以指数退避重连（初始 1s，倍增，上限 60s），重连后会广播 `bci_connected` 状态变化
- **FR-007**: REST 端点 — `GET /status` 查询状态，`POST /command` 发送 IPC 指令（需控制权）
- **FR-008**: 日志 — 使用 loguru 记录所有关键事件（连接/断开/重连/鉴权/指令），同时输出到 stdout 和本地文件，支持自动 rotation

### Non-Functional Requirements

- **NFR-001**: 可靠性 — 桥接服务器本身崩溃后应能快速重启恢复（进程管理由外部 systemd/launchd 负责，不在此 spec 范围内）
- **NFR-002**: 延迟 — WebSocket 消息从收到 IPC 数据到广播发出 < 10ms（单客户端场景）
- **NFR-003**: 吞吐 — 支持 50 msg/s 算法输出 + 10 个 WebSocket 客户端同时在线
- **NFR-004**: 安全 — Token 使用 32+ 字符随机字符串，鉴权失败时返回通用错误消息（不泄露 token 信息）

## Success Criteria

| #    | Criterion                                                    | Measured By              |
|------|--------------------------------------------------------------|--------------------------|
| SC-1 | WebSocket 客户端能实时收到 BCI 算法结果                       | US-001 独立测试通过      |
| SC-2 | 远程客户端能发送控制指令，控制权互斥生效                     | US-002 独立测试通过      |
| SC-3 | 官方 APP 崩溃后桥接自动重连成功                              | US-003 独立测试通过      |
| SC-4 | 公网通过 Tailscale Funnel 可访问桥接服务                     | 浏览器 wss:// 连接成功   |
| SC-5 | 压力测试：50 msg/s + 10 客户端 持续运行，无消息丢失/内存泄漏 | 压测脚本指标达标         |
| SC-6 | 非法 token 无法连接或发送指令                                | 鉴权测试通过             |

## Assumptions

- 官方 BCI APP 的 TCP 协议在可见版本内不会发生破坏性变更
- 官方 APP 在非分屏模式下不要求执行器回传窗口句柄（桥接服务器没有 GUI，无法提供 WinId）
- 算法输出频率不超过 ~50 msg/s
- Tailscale Funnel 服务本身稳定可用
- 桥接服务器与官方 APP 运行在同一台机器或同一局域网内（TCP 直连延迟 < 5ms）

## Clarifications

- 官方 APP TCP Server 的最大并发连接数未知 — 需实测验证。若仅支持单连接，桥接层作为唯一客户端的行为正确
- 分屏模式（`layout_type=1`）：已确认不支持。桥接服务器脱离单机且无 GUI，分屏无意义。收到 `ipc_user_info` 中 `layout_type=1` 时忽略，不回传窗口句柄

## Out of Scope

- 用户管理、多租户、RBAC 权限系统
- 数据库持久化、脑电数据历史存储
- Web 前端 UI / 可视化界面
- Docker 容器化部署
- 消息重放、断线数据补偿
- 多 BCI 设备（多官方 APP）支持
- IPC 消息语义化转换
- 速率限制、DDoS 防护
- 分屏布局模式支持（桥接服务器无 GUI）
- 移动端 SDK

## Risk Notes

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 官方 APP TCP 协议版本升级不兼容 | Low | High | IPC 客户端参考官方 `ipc_socket/` 库设计，适配成本低 |
| 官方 APP 不支持分屏模式下的无 GUI 客户端 | Medium | Medium | 优先测试默认布局模式，分屏模式标记为 out of scope |
| Tailscale Funnel 不可用 | Medium | Medium | 备选方案：直接走 Tailscale 内网 IP 访问 |
| Token 泄露导致未授权访问 | Low | High | Token 足够长（32+ 字符），使用范围极小（内部工具） |
| 压测消息频率超预期导致丢帧 | Low | Medium | asyncio 单线程处理，50 msg/s 远低于瓶颈 |
