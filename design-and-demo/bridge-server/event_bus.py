import asyncio
from typing import Dict, Set, Any, Optional
from loguru import logger

class EventBus:
    def __init__(self):
        # 内部主题订阅者字典：Topic -> Set[asyncio.Queue]
        self._subscribers: Dict[str, Set[asyncio.Queue]] = {}
        
        # 内存级独占控制权状态
        self._control_owner: Optional[str] = None
        self._lock = asyncio.Lock()

    async def subscribe(self, topic: str) -> asyncio.Queue:
        """
        订阅特定主题 (例如 'bci_message' 或 'bci_status')
        返回一个属于该客户端专属的异步队列，用于接收消息广播
        """
        queue = asyncio.Queue()
        if topic not in self._subscribers:
            self._subscribers[topic] = set()
        self._subscribers[topic].add(queue)
        logger.debug(f"新客户端已订阅主题 [{topic}], 当前该主题活跃订阅数: {len(self._subscribers[topic])}")
        return queue

    async def unsubscribe(self, topic: str, queue: asyncio.Queue):
        """取消订阅并清理内存中的队列实例"""
        if topic in self._subscribers and queue in self._subscribers[topic]:
            self._subscribers[topic].remove(queue)
            if not self._subscribers[topic]:
                del self._subscribers[topic]
            logger.debug(f"客户端已取消订阅主题 [{topic}]")

    async def publish(self, topic: str, message: Any):
        """向订阅了特定主题的所有客户端队列非阻塞地并发广播消息"""
        if topic not in self._subscribers:
            return
        
        # 使用 asyncio.gather 并发将消息塞入所有客户端的队列，
        # 避免单个慢连接或串行循环导致整体性能下降
        tasks = []
        for queue in self._subscribers[topic]:
            # 如果队列是无限的，put 实际上是同步完成的，但为了安全，采用 create_task 或 gather
            if queue.full():
                # 如果某个客户端队列满了（设置了上限），可以抛弃旧包避免拖垮全局
                try:
                    queue.get_nowait() # 剔除一个旧包
                except asyncio.QueueEmpty:
                    pass
            
            try:
                queue.put_nowait(message) # 改用非阻塞推入，确保绝对不卡死上游 TCP 接收器
            except asyncio.QueueFull:
                tasks.append(asyncio.create_task(queue.put(message)))

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def acquire_control(self, client_id: str) -> bool:
        """
        尝试抢占排他性控制权
        - 返回 True: 成功夺取控制权，或者原本就由该客户端持有
        - 返回 False: 被拒绝，控制权已被其他远程客户端独占
        """
        async with self._lock:
            if self._control_owner is None:
                self._control_owner = client_id
                logger.info(f"排他性控制权锁：客户端 [{client_id}] 成功获取控制权")
                return True
            elif self._control_owner == client_id:
                return True
            else:
                logger.warning(f"排他性控制权锁：客户端 [{client_id}] 尝试获取控制权被拒，当前由 [{self._control_owner}] 独占")
                return False

    async def release_control(self, client_id: str) -> bool:
        """
        释放控制权锁
        只有当前的控制权持有者才有权限释放。成功释放返回 True
        """
        async with self._lock:
            if self._control_owner == client_id:
                self._control_owner = None
                logger.info(f"排他性控制权锁：客户端 [{client_id}] 已主动释放控制权")
                return True
            return False

    @property
    def control_owner(self) -> Optional[str]:
        """查询当前霸占控制权的客户端 ID"""
        return self._control_owner