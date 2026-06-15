// src/bci/MockNeuroSource.ts
// 同学 D — 模拟神经数据源，适配统一 NeuroFrame 契约
import {
  NeuroFrame,
  NeuroSourceClient,
  SignalQuality,
  clamp01,
} from "../NeuroFrame";

export class MockNeuroSource implements NeuroSourceClient {
  private callbacks: Set<(frame: NeuroFrame) => void> = new Set();
  private intervalId: ReturnType<typeof setInterval> | null = null;

  // Developer-mode manual controls (0-1 range, per spec Section 5)
  public manualAttention: number = 0.5;
  public manualQuality: SignalQuality = "good";
  public isDeterministic: boolean = false;
  private frameCount: number = 0;

  start(): void {
    if (this.intervalId) return;
    // 10 Hz emission (100ms interval)
    this.intervalId = setInterval(() => {
      let attention: number | null = this.manualAttention;

      if (this.isDeterministic) {
        // Deterministic sine wave for reproducible testing (~20s cycle)
        // Maps the original 0-100 sine to 0-1 range
        const raw = 50 + 30 * Math.sin(this.frameCount * 0.1);
        attention = clamp01(raw / 100);
      }

      const frame: NeuroFrame = {
        timestampMs: performance.now(),
        source: "mock",
        attention: attention === null ? null : clamp01(attention),
        signalQuality: this.manualQuality,
      };

      this.frameCount++;
      this.emit(frame);
    }, 100);
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /** Subscribe to NeuroFrames. Returns unsubscribe function (spec 5.3). */
  subscribe(callback: (frame: NeuroFrame) => void): () => void {
    this.callbacks.add(callback);
    return () => {
      this.callbacks.delete(callback);
    };
  }

  // ── private ──────────────────────────────────────────────
  private emit(frame: NeuroFrame): void {
    this.callbacks.forEach((cb) => cb(frame));
    // 不变量 #10: all reviewable behaviour recorded via telemetry
    window.dispatchEvent(
      new CustomEvent("telemetry_event", {
        detail: { type: "neuro_frame", data: frame },
      })
    );
  }
}
