from typing import Optional, Any, Dict
from pydantic import BaseModel, Field

# ==========================================
# 1. 官方 BCI APP IPC 协议模型 (透明透传)
# ==========================================

class IPCMessage(BaseModel):
    """
    通用 IPC 消息基类。
    由于桥接层作为透明代理，因此允许携带任意未定义的额外字段。
    """
    msg: str

    model_config = {
        "extra": "allow"  # 允许接收和转发任何其他未显式定义的 JSON 字段
    }

class IPCAlgorithmTest(BaseModel):
    """在线输出算法结果契约 (如 SSVEP/P300 算法结果)"""
    msg: str = "ipc_algorithm_test"
    algorithm_name: str
    result_args: Dict[str, Any]  # 标准格式：{"data": "预测结果/状态"}

# ==========================================
# 2. 桥接服务器内部管理 & WebSocket 契约消息
# ==========================================

class WSAuthMessage(BaseModel):
    """WebSocket 客户端连接后的首条鉴权消息"""
    type: str = "auth"
    token: str

class WSErrorMessage(BaseModel):
    """向客户端推送的错误通知"""
    type: str = "error"
    reason: str

class BridgeStatusResponse(BaseModel):
    """GET /status 状态查询响应模型"""
    bci_connected: bool
    ws_clients: int
    control_owner: Optional[str] = None