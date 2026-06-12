import os
import uuid
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, status
from loguru import logger

# 导入你前几个阶段编写并验证成功的核心组件
from ipc_client import BCIIPCClient
from event_bus import EventBus
from models import BridgeStatusResponse

# =============================================================================
# 0. 基础配置与全局状态初始化
# =============================================================================
BRIDGE_TOKEN = os.getenv("BRIDGE_TOKEN", "tsinghua_bci_secure_token_2026")
TOPIC_BCI_STREAM = "bci_stream"

# 初始化全内存发布订阅与排他锁中心
event_bus = EventBus()

# 全局模块级变量，用于追踪网关与物理硬件/官方 APP 的真实 TCP 连接状态
bci_connected_state = False


# =============================================================================
# 1. 注册 IPC 客户端底层回调，联动事件总线与全局状态
# =============================================================================
async def on_ipc_message_received(msg: dict):
    """当从官方 BCI APP 收到透传算法数据帧时"""
    
    logger.info(f"【真机调试】官方 APP 发来的完整原始消息内容 -> {msg}")

    # --- 【核心修复：自动完成官方用户信息协议双向握手】 ---
    if msg.get("msg") == "ipc_user_info":
        logger.info(f"收到官方 APP 用户会话信息: 用户名={msg.get('user_name')}, ID={msg.get('user_id')}")
        
        # 严格构建回传确认帧 (根据 ipc通信协议.docx 的契约要求)
        # 确保包含必填的 msg 以及平台用来校验会话合法性的 user_token / user_id
        confirm_frame = {
            "msg": "ipc_user_info",
            "user_id": msg.get("user_id"),
            "user_token": msg.get("user_token"),
            "win_id": 0,
            "layout_type": 0,
            "result": True  # 或者是官方要求的特定握手成功标志
        }
        
        logger.info("正在向官方 APP 自动回传 ipc_user_info 协议确认帧...")
        
        # 【核心检查点】: 必须确保调用的是封装好大端长度头的 ipc_client 方法
        # 假设你在 lifespan 或全局持有这个 client 实例
        await bci_client.send_message(confirm_frame)
        
    # 保持原有的全网 WebSocket 异步非阻塞广播
    await event_bus.publish(TOPIC_BCI_STREAM, msg)


async def on_ipc_connected():
    """当桥接服务器成功连接到官方 BCI APP 时，触发此回调"""
    global bci_connected_state
    bci_connected_state = True
    logger.success("✅ 系统联动：与官方 BCI APP 的 TCP 网络链路已成功建立！开始向全网广播状态...")
    await event_bus.publish(TOPIC_BCI_STREAM, {"msg": "bci_connected"})


async def on_ipc_disconnected():
    """当与官方 BCI APP 的 TCP 链路意外断开时，触发此回调"""
    global bci_connected_state
    bci_connected_state = False
    logger.warning("❌ 系统联动：与官方 BCI APP 的网络断开，触发指数退避重连，全网广播断连告警...")
    await event_bus.publish(TOPIC_BCI_STREAM, {"msg": "bci_disconnected"})


# =============================================================================
# 2. 核心实例化：创建官方 BCI APP IPC 异步客户端
# =============================================================================
# 显式对齐官方 APP 运行的 :8000 端口，并将上面定义的生命周期回调函数强绑定挂载
bci_client = BCIIPCClient(
    host="127.0.0.1",
    port=8000,
    on_connected=on_ipc_connected,
    on_disconnected=on_ipc_disconnected,
    on_message=on_ipc_message_received
)


# =============================================================================
# 3. FastAPI Lifespan 生命周期管理（点火与安全回收机制）
# =============================================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    """管理网关的整机生命周期，确保 IPC 守护协程随 Web 服务同步启停"""
    logger.info("🚀 [Lifespan] 正在拉起官方 BCI APP IPC 守护客户端进程...")
    # 将客户端的常驻重连监听循环作为后台非阻塞 Task 运行
    bci_task = asyncio.create_task(bci_client.start())
    
    yield  # Web 服务器在此处提供对外服务
    
    logger.info("🛑 [Lifespan] 检测到网关关闭指令，正在优雅释放官方 APP IPC 链路...")
    await bci_client.stop()
    bci_task.cancel()
    try:
        await bci_task
    except asyncio.CancelledError:
        pass
    logger.info("✨ [Lifespan] 桥接网关系统安全退出，内存已全部清理。")


# 初始化 FastAPI 实例并注入生命周期上下文
app = FastAPI(
    title="Tsinghua HybridBCI Bridge Gateway",
    version="1.0.0",
    lifespan=lifespan
)


# =============================================================================
# 4. RESTful API 路由设计
# =============================================================================
@app.get("/status", response_model=BridgeStatusResponse)
async def get_status():
    """提供公网或本地查询当前网关与物理硬件/官方 APP 的实质连接状态"""
    current_owner = event_bus._control_owner if hasattr(event_bus, "_control_owner") else None
    active_subs = event_bus._subscribers.get(TOPIC_BCI_STREAM, [])
    return {
        "bci_connected": bci_connected_state,
        "control_owner": current_owner,
        "active_subscribers": len(active_subs)
    }


# =============================================================================
# 5. 高并发双向 WebSocket 核心长连接网关
# =============================================================================
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    client_id = f"client_{uuid.uuid4().hex[:8]}"
    logger.info(f"收到未鉴权物理连接，分配临时内部标识: [{client_id}]")

    try:
        # --- 环节 A: 强鉴权握手防御 ---
        raw_auth = await websocket.receive_json()
        if raw_auth.get("type") != "auth" or raw_auth.get("token") != BRIDGE_TOKEN:
            logger.warning(f"拒绝非法连接 [{client_id}]: Token 鉴权失败")
            await websocket.send_json({"type": "error", "message": "Authentication failed. Invalid Token."})
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        logger.success(f"🔒 客户端 [{client_id}] 鉴权成功！正式接入脑电全双工数据通道。")
        await websocket.send_json({"type": "auth_result", "status": "success", "client_id": client_id})

        # 动态订阅全局脑电波算法流
        client_queue = await event_bus.subscribe(TOPIC_BCI_STREAM)

        # 状态对齐：如果连接时官方 APP 已经在线，主动向新进来的客户端补发一帧在线通知
        if bci_connected_state:
            await websocket.send_json({"msg": "bci_connected"})

        # --- 环节 B: 双向并发流协同逻辑 ---
        async def downstream_broadcast_task():
            """下行广播流：从事件总线抓取脑电算法 JSON 并推向远程 WebSocket 客户端"""
            try:
                while True:
                    msg = await client_queue.get()
                    await websocket.send_json(msg)
                    client_queue.task_done()
            except asyncio.CancelledError:
                pass

        async def upstream_control_task():
            """上行控制流：接收远程客户端下发的指令，处理抢锁互斥，并透传给官方 BCI APP"""
            try:
                while True:
                    data = await websocket.receive_json()
                    msg_type = data.get("type")

                    # 场景 1：申请独占排他性控制权锁
                    if msg_type == "acquire_control_request":
                        success = await event_bus.acquire_control(client_id)
                        await websocket.send_json({
                            "type": "control_result",
                            "status": "success" if success else "failed"
                        })

                    # 场景 2：释放独占控制权锁
                    elif msg_type == "release_control_request":
                        released = await event_bus.release_control(client_id)
                        await websocket.send_json({
                            "type": "release_result",
                            "status": "success" if released else "failed"
                        })

                    # 场景 3：常规业务控制流指令（透传给官方 BCI APP）
                    else:
                        current_owner = event_bus._control_owner if hasattr(event_bus, "_control_owner") else None
                        if current_owner == client_id:
                            # 只有成功拿锁的客户端发出的常规 JSON 指令才允许被网关透传给真机 APP
                            logger.info(f"持有者 [{client_id}] 下发控制指令 -> 正在透传至官方 APP: {data}")
                            
                            # 协议兼容性转换：若外部客户端发来的 JSON 里使用 type 字段而没写 msg，自动进行转换兼容
                            if "type" in data and "msg" not in data:
                                data["msg"] = data.pop("type")
                                
                            sent = await bci_client.send_message(data)
                            if not sent:
                                await websocket.send_json({"type": "error", "message": "Failed to pass message to BCI APP. Network issue."})
                        else:
                            await websocket.send_json({
                                "type": "error",
                                "message": f"Control denied. You do not hold the lock. Current owner is [{current_owner}]."
                            })

            except asyncio.CancelledError:
                pass

        # 并发协同运行上下行双向任务流
        t1 = asyncio.create_task(downstream_broadcast_task())
        t2 = asyncio.create_task(upstream_control_task())

        await asyncio.gather(t1, t2)

    except WebSocketDisconnect:
        logger.info(f"远程客户端 [{client_id}] 主动断开 WebSocket 链路。")
    except Exception as e:
        logger.error(f"客户端 [{client_id}] 双向流通信产生异常: {e}")
    finally:
        # --- 环节 C: 完美的资源回收与垃圾清理 ---
        if 't1' in locals(): t1.cancel()
        if 't2' in locals(): t2.cancel()
        
        # 移除订阅队列，彻底杜绝内存泄漏
        if 'client_queue' in locals():
            await event_bus.unsubscribe(TOPIC_BCI_STREAM, client_queue)
        
        # 隐式安全：如果断开连接的客户端正死死占有着控制权，网关强制回收锁，为后续客户端疏通管道
        current_owner = event_bus._control_owner if hasattr(event_bus, "_control_owner") else None
        if current_owner == client_id:
            logger.warning(f"控制权持有者 [{client_id}] 异常掉线，网关已强制安全释放互斥锁！")
            if hasattr(event_bus, "_control_owner"):
                event_bus._control_owner = None