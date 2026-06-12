import asyncio
import struct
import json
from typing import Callable, Optional, Awaitable, Dict, Any
from loguru import logger

class BCIIPCClient:
    def __init__(
        self, 
        host: str = "127.0.0.1", 
        port: int = 8000,
        on_connected: Optional[Callable[[], Awaitable[None]]] = None,
        on_disconnected: Optional[Callable[[], Awaitable[None]]] = None,
        on_message: Optional[Callable[[Dict[str, Any]], Awaitable[None]]] = None
    ):
        self.host = host
        self.port = port
        
        # 底层网络连接句柄
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._connected = False
        self._running = False
        
        # 异步任务流管理
        self._receive_task: Optional[asyncio.Task] = None
        self._loop_task: Optional[asyncio.Task] = None

        # 核心生命周期回调函数（需为异步函数）
        self.on_connected_cb = on_connected
        self.on_disconnected_cb = on_disconnected
        self.on_message_cb = on_message

        # 指数退避重连参数配置
        self.initial_backoff = 1.0
        self.max_backoff = 60.0
        self.backoff_factor = 2.0
        self.current_backoff = self.initial_backoff

    @property
    def is_connected(self) -> bool:
        """获取当前与官方 BCI APP 的连接状态"""
        return self._connected

    async def start(self):
        """启动 IPC 客户端后台连接与维护循环"""
        if self._running:
            return
        self._running = True
        self._loop_task = asyncio.create_task(self._connection_loop())
        logger.info("BCI IPC 客户端后台维护循环已启动")

    async def stop(self):
        """优雅关闭客户端连接并释放资源"""
        self._running = False
        if self._loop_task:
            self._loop_task.cancel()
            try:
                await self._loop_task
            except asyncio.CancelledError:
                pass
        await self._disconnect()
        logger.info("BCI IPC 客户端已完全停止")

    async def _connection_loop(self):
        """管理自动重连的主循环 (不阻塞服务器启动)"""
        while self._running:
            if not self._connected:
                try:
                    logger.info(f"正在尝试连接官方 BCI APP -> {self.host}:{self.port} ...")
                    self._reader, self._writer = await asyncio.open_connection(self.host, self.port)
                    
                    self._connected = True
                    self.current_backoff = self.initial_backoff  # 连接成功，重置退避时间
                    logger.info("与官方 BCI APP 的 TCP 连接建立成功")
                    
                    # 触发连接建立成功的回调
                    if self.on_connected_cb:
                        asyncio.create_task(self._safe_execute_callback(self.on_connected_cb))

                    # 开启非阻塞的读取数据流的任务
                    self._receive_task = asyncio.create_task(self._read_loop())
                except (OSError, Exception) as e:
                    logger.warning(f"连接失败原因: {e}。将在 {self.current_backoff} 秒后尝试重连...")
                    await asyncio.sleep(self.current_backoff)
                    # 指数递增退避延迟，最大不超过 60 秒
                    self.current_backoff = min(self.max_backoff, self.current_backoff * self.backoff_factor)
            else:
                # 状态正常，挂起当前循环，通过外部 read_loop 异常打破连接状态
                await asyncio.sleep(1)

    async def _read_loop(self):
        """异步数据读取循环，利用 4 字节大端头解决网络粘包、半包及断包问题"""
        buffer = bytearray()
        try:
            while self._running and self._connected:
                # 异步读取 chunk (4KB)
                chunk = await self._reader.read(4096)
                if not chunk:
                    logger.info("收到远端 TCP EOF，官方 BCI APP 已主动断开连接。")
                    break
                
                buffer.extend(chunk)

                # 循环解析缓冲区中的所有完整数据帧
                while len(buffer) >= 4:
                    # 1. 提取前 4 字节的长度头 (大端 32 位无符号整数 '>I')
                    length_header = buffer[:4]
                    frame_len = struct.unpack(">I", length_header)[0]

                    # 2. 检查缓冲区剩余数据是否满足一帧的长度
                    if len(buffer) < 4 + frame_len:
                        break  # 半包/分片情形，等待下一次接收

                    # 3. 提取完整的 JSON Payload 并从缓冲区抹去已读部分
                    payload_bytes = buffer[4:4 + frame_len]
                    del buffer[:4 + frame_len]

                    # 4. 反序列化并交由回调函数分发
                    try:
                        payload_str = payload_bytes.decode('utf-8')
                        message_dict = json.loads(payload_str)
                        
                        if self.on_message_cb:
                            asyncio.create_task(self._safe_execute_callback(self.on_message_cb, message_dict))
                    except json.JSONDecodeError as je:
                        logger.error(f"IPC JSON 解码失败: {je}. 原始字节流: {payload_bytes}")
                    except Exception as ex:
                        logger.error(f"处理数据帧时发生未知错误: {ex}")

        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"IPC 读取流发生异常中断: {e}")
        finally:
            await self._handle_disconnect()

    async def send_message(self, message: dict) -> bool:
        """
        向官方 BCI APP 发送 IPC JSON 控制指令。
        自动追加 4 字节大端长度前缀。
        """
        if not self._connected or not self._writer:
            logger.warning("发送指令失败：当前未与官方 BCI APP 建立连接")
            return False
        
        try:
            payload_str = json.dumps(message)
            payload_bytes = payload_str.encode('utf-8')
            # 组装 4 字节大端头
            length_header = struct.pack(">I", len(payload_bytes))
            
            self._writer.write(length_header + payload_bytes)
            await self._writer.drain()
            return True
        except Exception as e:
            logger.error(f"发送 IPC 消息时产生异常: {e}")
            # 发送失败通常意味着连接损坏，强制触发本地断连清理
            asyncio.create_task(self._disconnect())
            return False

    async def _handle_disconnect(self):
        """统一处理链路断开状态变更与事件广播"""
        if self._connected:
            self._connected = False
            logger.warning("与官方 BCI APP 的连接已断开")
            if self.on_disconnected_cb:
                asyncio.create_task(self._safe_execute_callback(self.on_disconnected_cb))
        
        if self._receive_task and not self._receive_task.done():
            self._receive_task.cancel()

    async def _disconnect(self):
        """底层实际关闭套接字操作"""
        await self._handle_disconnect()
        if self._writer:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except Exception:
                pass
            self._writer = None
        self._reader = None

    async def _safe_execute_callback(self, cb: Callable[..., Awaitable[None]], *args):
        """确保用户注册的回调函数报错时不会引发核心网络线程崩溃"""
        try:
            await cb(*args)
        except Exception as e:
            logger.error(f"回调函数 {cb.__name__} 执行时发生内部异常: {e}")