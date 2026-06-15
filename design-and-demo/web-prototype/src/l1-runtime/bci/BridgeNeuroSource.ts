// src/bci/BridgeNeuroSource.ts
// 同学 D — Bridge 桥接数据源，适配统一 NeuroFrame 契约
import {
  NeuroFrame,
  NeuroSourceClient,
  SignalQuality,
  clamp01,
} from "../NeuroFrame";

/** Hardcoded config for M1 — will be configuration-driven in M2. */
const BRIDGE_WS_URL = "ws://127.0.0.1:8001/ws";
const AUTH_TOKEN = "tsinghua_bci_secure_token_2026";
const RECONNECT_DELAY_MS = 5000;

export class BridgeNeuroSource implements NeuroSourceClient {
  private callbacks: Set<(frame: NeuroFrame) => void> = new Set();
  private ws: WebSocket | null = null;
  private currentQuality: SignalQuality = "lost";
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private started = false;

  start(): void {
    this.started = true;
    this.connect();
  }

  stop(): void {
    this.started = false;
    this.clearReconnect();
    this.ws?.close();
    this.ws = null;
  }

  /** Subscribe to NeuroFrames. Returns unsubscribe function (spec 5.3). */
  subscribe(callback: (frame: NeuroFrame) => void): () => void {
    this.callbacks.add(callback);
    return () => {
      this.callbacks.delete(callback);
    };
  }

  // ── WebSocket lifecycle ─────────────────────────────────

  private connect(): void {
    if (!this.started) return;
    this.ws = new WebSocket(BRIDGE_WS_URL);

    this.ws.onopen = () => {
      this.log("WebSocket connected, sending auth...");
      this.ws?.send(
        JSON.stringify({ type: "auth", token: AUTH_TOKEN })
      );
    };

    this.ws.onmessage = (event: MessageEvent) => {
      try {
        const data = JSON.parse(event.data);
        this.log(`Received: ${JSON.stringify(data)}`);

        // 不变量 #9: bridge raw → standardized NeuroFrame
        if (data.msg === "ipc_algorithm_test") {
          this.currentQuality = "good";

          // Parse focus_level (e.g. "86%" → 0.86)
          const rawLevel = data.result_args?.focus_level;
          const attentionNum = rawLevel
            ? clamp01(parseInt(String(rawLevel)) / 100)
            : null;

          const frame: NeuroFrame = {
            timestampMs: performance.now(),
            source: "bridge",
            attention: attentionNum,
            signalQuality: this.currentQuality,
            raw: data, // dev-only raw payload (spec 5.1)
          };
          this.emit(frame);
        }
      } catch (e) {
        this.log(`Parse error: ${e}`);
      }
    };

    this.ws.onerror = () => {
      this.log("WebSocket error");
      // Signal quality degrades on error
      this.currentQuality = "lost";
      this.emitLostFrame();
    };

    this.ws.onclose = () => {
      // 核心要求: 断连或超时时强制标记为 lost, 不得判定为用户分心
      this.currentQuality = "lost";
      this.emitLostFrame();
      this.log("Connection lost — signalQuality set to 'lost'");

      // 指数退避重连
      if (this.started) {
        this.reconnectTimer = setTimeout(
          () => this.connect(),
          RECONNECT_DELAY_MS
        );
      }
    };
  }

  private clearReconnect(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  // ── private ──────────────────────────────────────────────

  private emit(frame: NeuroFrame): void {
    this.callbacks.forEach((cb) => cb(frame));
  }

  private emitLostFrame(): void {
    this.emit({
      timestampMs: performance.now(),
      source: "bridge",
      attention: null, // null = unavailable, NOT distracted (spec 5.2)
      signalQuality: "lost",
    });
  }

  private log(msg: string): void {
    console.log(`[Bridge Stub Log]: ${msg}`);
  }
}
