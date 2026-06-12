# 实现计划: BCI 桥接服务器

## 输入来源

| 来源         | 引用                                 |
|-------------|--------------------------------------|
| 规格文档     | `specs/001-bci-bridge/spec.md`       |
| PRD         | 无                                   |
| 关联契约     | `specs/001-bci-bridge/spec.md`（IPC 协议定义在 spec 参考文档中） |

## 技术上下文

| 维度         | 值                                   |
|-------------|--------------------------------------|
| 语言         | Python 3.11+                         |
| 框架         | FastAPI + uvicorn                    |
| 存储         | 无（全内存，无状态）                   |
| 外部依赖     | fastapi[standard], uvicorn, loguru   |

## 架构影响

这是 HybridBCI 仓库中的**全新项目**，不修改任何现有代码。

### DDD 分层影响

| 层              | 变更                                               |
|-----------------|----------------------------------------------------|
| `bridge-server/` | **新增** — 独立服务，与现有 PyQt5 执行器零耦合    |

### 契约影响

- **新增**: WebSocket 协议 — JSON 消息。所有 IPC 消息透传。内部消息: `{"type":"auth",...}`, `{"type":"error",...}`, `{"msg":"bci_connected"}`, `{"msg":"bci_disconnected"}`
- **新增**: REST 端点 — `GET /status`, `POST /command`
- **不变**: IPC 协议 — 桥接层作为透明代理，与官方 BCI APP 的现有契约完全保持不变

### 数据模型影响

- **无** — 无数据库、无持久化。所有状态为内存存储、进程级生命周期。

## 爆炸半径分级

| 字段     | 值                                                                     |
|---------|------------------------------------------------------------------------|
| 等级     | `branch`                                                               |
| 原因     | 新功能模块，多文件，新增外部可见端点（REST + WebSocket）。不涉及现有部署/CI/CD/数据库 schema，不修改现有鉴权/会话/权限系统（token 鉴权仅是简单门禁）。 |
| 必需关卡 | spec, plan, tests, review_agent                                        |

## 原则检查

| 检查项         | 通过  | 说明                                                         |
|---------------|-------|--------------------------------------------------------------|
| 契约优先       | 是    | Spec 中定义了 WS 协议和 REST 契约，在实现之前完成设计       |
| DDD 方向      | 不适用 | 全新独立项目，无现有领域层需遵循                             |
| TDD/BDD       | 是    | Mock BCI 服务器支持无需真实硬件的测试；压测脚本验证 spec 验收场景 |
| 可观测性       | 是    | loguru 结构化日志，同时输出到 stdout 和本地文件（支持 rotation） |
| 安全性         | 是    | Bearer token 鉴权覆盖所有端点，token 硬编码（32+ 字符）     |

## 实现策略

自底向上构建: 基础层 → 核心逻辑 → 对外集成 → 验证。每个阶段的文件无相互依赖，可并行创建。

### 阶段一: 项目骨架 + IPC 客户端（基础层）

文件: `pyproject.toml`, `ipc_client.py`, `models.py`

1. 创建 `bridge-server/pyproject.toml`，依赖: `fastapi[standard]`, `uvicorn`, `loguru`
2. 创建 `bridge-server/models.py` — Pydantic 模型，包含所有 IPC 消息类型、内部状态消息、鉴权消息
3. 创建 `bridge-server/ipc_client.py` — 纯 Python `asyncio` TCP 客户端，实现 IPC 协议:
   - 4 字节大端长度头 + JSON payload（从 `基础篇鼠标模块/ipc_socket/tcp_socket_client.py` 移植，去除 PyQt5 依赖）
   - 异步 connect/disconnect/send/recv
   - 指数退避自动重连（初始 1s，每次翻倍，上限 60s）
   - 回调接口: `on_connected`, `on_disconnected`, `on_message`

移植参考实现: `基础篇鼠标模块/ipc_socket/tcp_socket_client.py:6-70` (HNNKTcpSocketClient)

### 阶段二: 事件总线 + 状态管理（核心逻辑）

文件: `event_bus.py`

4. 创建 `bridge-server/event_bus.py` — 简易异步发布/订阅:
   - 基于 topic 的订阅模型
   - `bci_message` 主题 — 所有来自官方 APP 的 IPC 消息
   - `bci_status` 主题 — 连接状态变化
   - 控制权管理（内存字典: `{owner_id: client_id}`）
   - 面向单 asyncio 事件循环设计

### 阶段三: FastAPI 服务器 + 对接（集成层）

文件: `server.py`

5. 创建 `bridge-server/server.py`:
   - **启动**: 初始化 IPC 客户端和事件总线，启动重连循环（非阻塞）
   - **REST 端点**:
     - `GET /status` — 返回 `{bci_connected, ws_clients, control_owner}`
     - `POST /command` — 接收 IPC JSON 指令，需鉴权 + 持有控制权。首次发送指令时自动获得控制权
   - **WebSocket `/ws`**:
     - 首条消息必须为 `{"type":"auth","token":"xxx"}`
     - 鉴权成功后: 订阅 `bci_message` 和 `bci_status` 主题
     - 将所有事件以 JSON 格式转发给客户端
     - 客户端断开时: 若该客户端持有控制权则自动释放
   - **鉴权中间件**: REST 端点均需 Bearer token 校验。token 常量按用户需求直接写在代码中
   - **日志**: loguru 配置 stdout + 文件轮转（默认: `logs/bridge_{time}.log`，10MB 轮转，7 天保留）

### 阶段四: 参考文档 + 压测工具（验证层）

6. 将参考文件复制到 `bridge-server/doc/`:
   - `基础篇鼠标模块/ipc_socket/tcp_socket_client.py` → `bridge-server/doc/ipc_socket/tcp_socket_client.py`
   - `基础篇鼠标模块/ipc_socket/local_socket_client.py` → `bridge-server/doc/ipc_socket/local_socket_client.py`
   - `.claude/skills/hybrid-bci/references/ipc-protocol.md` → `bridge-server/doc/ipc-protocol.md`

7. 创建 `bridge-server/stress_test/mock_bci_server.py`:
   - 模拟官方 BCI APP 的 TCP Server 行为
   - 接受连接，解析 IPC 协议，以可配置频率发送模拟 `ipc_algorithm_test` 消息
   - 响应 `ipc_test_start`/`ipc_test_stop`

8. 创建 `bridge-server/stress_test/stress_client.py`:
   - 场景 1 消息吞吐: mock server 以 N msg/s 发送，验证桥接层完整转发给 M 个 WS 客户端
   - 场景 2 控制互斥: 2 个 WS 客户端抢夺控制权，验证只有 1 个获胜
   - 场景 3 断线重连: 杀掉 mock server，验证桥接指数退避重连
   - 场景 4 长时运行: 连续运行 2 小时，验证无内存泄漏

## 测试策略

### 单元测试

- `ipc_client.py`: 帧编码/解码（长度头 + payload）、连接状态转换、重连退避计算
- `event_bus.py`: 订阅/取消订阅、广播投递、控制权生命周期
- `models.py`: 所有消息类型的 JSON 序列化/反序列化往返测试

### 集成测试

- 全链路: mock BCI 服务器 → 桥接 → WebSocket 客户端，验证消息透传
- 鉴权失败: 无 token 连接 / 错误 token → 验证拒绝
- 控制互斥: 客户端 A 持有控制权 → B 发指令被拒 → A 断开 → B 获得控制权
- 断线重连: 杀掉 mock server → 验证桥接广播 `bci_disconnected` → 重启 mock → 验证 `bci_connected`

### 边界情况

| 边界情况 | 预期行为 |
|---------|---------|
| TCP 半开连接 | asyncio 超时检测，触发重连 |
| 帧分片（跨 TCP 包拆分） | IPC 客户端通过长度头缓冲重组 |
| 单次读取含多帧 | IPC 客户端循环处理所有完整帧 |
| 客户端发送非 JSON 内容 | 返回 `{"type":"error","reason":"invalid_message_format"}` |
| 控制指令发送时 BCI 未连接 | 返回 503，"BCI not connected" |
| WebSocket 客户端鉴权中途断连 | 无状态泄漏，订阅未被创建 |

### 压力测试（对应 Spec SC-5）

通过 `stress_test/` 脚本执行。所有结果记录日志。阈值:
- 50 msg/s + 10 WS 客户端: 0 消息丢失，广播延迟 p50 < 10ms
- 2 小时连续运行: 内存增长 < 10MB，日志文件无超出 rotation 限制的膨胀

## 回滚方案

桥接服务器是**独立的新服务**。回滚 = 停止进程:

1. `Ctrl+C` 或 `kill <pid>` 停止桥接服务器
2. 如果配置了 Tailscale Funnel: `tailscale funnel off` 关闭公网暴露
3. 现有的 PyQt5 执行器（直连官方 APP 的 TCP）**完全不受影响** — 继续正常运行

无需数据迁移、无 schema 变更、无配置残留需清理。

## 复杂度评估

| 字段   | 值       |
|-------|----------|
| 预估   | `低`     |
| 理由   | ~300 行新 Python 代码。纯 asyncio 标准库 + FastAPI。无数据库、无分布式协调、无 schema 变更。唯一的外部复杂度是 Tailscale Funnel（一行 CLI 命令）。IPC 协议已明确定义且有参考实现可供移植。 |
