/**
 * L1Controller — "涟漪绽放" 关卡状态机 (spec Section 6).
 *
 * Fixes applied:
 *   Bug 1: bloomProgress uses rate integration (bloomRisePerSecond * dt)
 *          instead of instant attention mapping.
 *   Bug 2: Dwell time now accumulated — transitions only after sustained
 *          threshold crossing for dwellTimeMs (2000ms default).
 *   Bug 3: open_loop → closing_transition driven by attention threshold,
 *          not a fixed timer.
 *   Also: removed confidence >= 0.5 gate (not in spec).
 *   Also: segment IDs use camelCase per spec Section 6.6.
 */

import type { LevelController } from "../runtime/LevelController";
import type { NeuroFrame } from "../NeuroFrame";
import {
  clamp01,
  isUsableNeuroFrame,
  normalizeNeuroFrame,
} from "../NeuroFrame";

// ── Types (spec Section 6.1–6.6) ──────────────────────────

export type L1VisualState =
  | "closedLoop"
  | "openingTransition"
  | "openLoop"
  | "closingTransition";

export interface L1VisualCommand {
  /** Video segment to play (spec Section 6.6). */
  videoSegment: "closedLoop" | "openingTransition" | "openLoop" | "closingTransition";
  /** Whether the SSVEP target overlay should be visible. */
  overlayTargetVisible: boolean;
  /** Overlay intensity, 0-1 (follows bloomProgress). */
  overlayIntensity: number;
  /** Whether the debug mask is visible (developer mode only). */
  debugMaskVisible: boolean;
  /** Current bloomProgress, 0-1. */
  bloomProgress: number;
}

export interface L1ControllerOptions {
  /** Attention threshold to start opening (spec: 0.65). */
  attentionHighThreshold: number;
  /** Attention threshold to start closing (spec: 0.45). */
  attentionLowThreshold: number;
  /** Dwell time in ms — how long attention must stay above/below threshold (spec: 2000). */
  dwellTimeMs: number;
  /** How fast bloomProgress rises per second when attention >= highThreshold (spec: 0.25). */
  bloomRisePerSecond: number;
  /** How fast bloomProgress falls per second when attention <= lowThreshold (spec: 0.20). */
  bloomFallPerSecond: number;
  /** Timeout in ms before signalLost triggers pause penalty (spec: 1000). */
  signalLostTimeoutMs: number;
}

export const DEFAULT_L1_OPTIONS: L1ControllerOptions = {
  attentionHighThreshold: 0.65,
  attentionLowThreshold: 0.45,
  dwellTimeMs: 2000,
  bloomRisePerSecond: 0.25,
  bloomFallPerSecond: 0.20,
  signalLostTimeoutMs: 1000,
};

// ── Controller ────────────────────────────────────────────

export class L1Controller
  implements LevelController<L1VisualState, L1VisualCommand>
{
  private currentState: L1VisualState = "closedLoop";
  private elapsedInStateMs = 0;
  private bloomProgress = 0;

  /**
   * Dwell accumulator — tracks how long the attention has been
   * consistently above `attentionHighThreshold` (or below
   * `attentionLowThreshold` in open_loop). Resets on reversal.
   */
  private dwellAccumulatorMs = 0;

  constructor(
    private readonly options: L1ControllerOptions = DEFAULT_L1_OPTIONS,
  ) {}

  get state(): L1VisualState {
    return this.currentState;
  }

  getBloomProgress(): number {
    return this.bloomProgress;
  }

  update(inputFrame: NeuroFrame, deltaMs: number): L1VisualCommand {
    const frame = normalizeNeuroFrame(inputFrame);
    const dtSeconds = Math.max(0, deltaMs) / 1000;

    this.elapsedInStateMs += Math.max(0, deltaMs);

    switch (this.currentState) {
      case "closedLoop":
        return this.updateClosedLoop(frame, dtSeconds);

      case "openingTransition":
        return this.updateOpeningTransition();

      case "openLoop":
        return this.updateOpenLoop(frame, dtSeconds);

      case "closingTransition":
        return this.updateClosingTransition();
    }
  }

  reset(): void {
    this.currentState = "closedLoop";
    this.elapsedInStateMs = 0;
    this.bloomProgress = 0;
    this.dwellAccumulatorMs = 0;
  }

  // ── Per-state update methods ──────────────────────────────

  /**
   * closedLoop: attention drives bloomProgress.
   *
   * Spec Section 6.5:
   *   if signalQuality is lost/poor: bloomProgress unchanged
   *   else if attention >= highThreshold: bloomProgress += risePerSecond * dt
   *   else if attention <= lowThreshold: bloomProgress -= fallPerSecond * dt
   *   else: bloomProgress unchanged
   *
   * Transition to opening_transition when attention >= highThreshold
   * for dwellTimeMs continuously (spec Section 6.3).
   */
  private updateClosedLoop(
    frame: NeuroFrame,
    dtSeconds: number,
  ): L1VisualCommand {
    // 信号不可用 → 暂停进度变化, 不惩罚 (spec 5.2 & 6.5)
    if (!isUsableNeuroFrame(frame)) {
      this.dwellAccumulatorMs = 0;
      return this.noopCommand();
    }

    // isUsableNeuroFrame guarantees attention !== null
    const attention = frame.attention as number;

    // ── bloomProgress rate integration (Bug-1 FIX) ──
    if (attention >= this.options.attentionHighThreshold) {
      this.bloomProgress += this.options.bloomRisePerSecond * dtSeconds;
    } else if (attention <= this.options.attentionLowThreshold) {
      this.bloomProgress -= this.options.bloomFallPerSecond * dtSeconds;
    }
    this.bloomProgress = clamp01(this.bloomProgress);

    // ── Dwell time accumulation (Bug-2 FIX) ──
    if (attention >= this.options.attentionHighThreshold) {
      this.dwellAccumulatorMs += dtSeconds * 1000;
      if (this.dwellAccumulatorMs >= this.options.dwellTimeMs) {
        this.transitionTo("openingTransition");
        return {
          videoSegment: "openingTransition",
          overlayTargetVisible: true,
          overlayIntensity: this.bloomProgress,
          debugMaskVisible: false,
          bloomProgress: this.bloomProgress,
        };
      }
    } else {
      // Reset dwell on any frame below threshold
      this.dwellAccumulatorMs = 0;
    }

    return {
      videoSegment: "closedLoop",
      overlayTargetVisible: true,
      overlayIntensity: this.bloomProgress,
      debugMaskVisible: false,
      bloomProgress: this.bloomProgress,
    };
  }

  /**
   * openingTransition: video plays to completion, not interruptible (spec 6.4).
   * Transition to open_loop when video ends.
   *
   * NOTE: M1 uses a fixed duration timer since we can't detect
   * video-ended in the controller (that's the VideoEnvironmentController's job).
   * In the real integration, TrainingRuntime listens for video_ended events
   * and calls forceTransition(). For now, we leave the timer as fallback.
   */
  private updateOpeningTransition(): L1VisualCommand {
    return {
      videoSegment: "openingTransition",
      overlayTargetVisible: true,
      overlayIntensity: this.bloomProgress,
      debugMaskVisible: false,
      bloomProgress: this.bloomProgress,
    };
  }

  /**
   * openLoop: video plays, user attention can trigger closing.
   *
   * Bug-3 FIX: attention <= lowThreshold sustained for dwellTimeMs
   * triggers closing_transition (not a fixed timer).
   */
  private updateOpenLoop(
    frame: NeuroFrame,
    dtSeconds: number,
  ): L1VisualCommand {
    if (!isUsableNeuroFrame(frame)) {
      this.dwellAccumulatorMs = 0;
      return {
        videoSegment: "openLoop",
        overlayTargetVisible: true,
        overlayIntensity: this.bloomProgress,
        debugMaskVisible: false,
        bloomProgress: this.bloomProgress,
      };
    }

    const attention = frame.attention as number;

    // Dwell time for closing (Bug-3 FIX)
    if (attention <= this.options.attentionLowThreshold) {
      this.dwellAccumulatorMs += dtSeconds * 1000;
      if (this.dwellAccumulatorMs >= this.options.dwellTimeMs) {
        this.transitionTo("closingTransition");
        return {
          videoSegment: "closingTransition",
          overlayTargetVisible: true,
          overlayIntensity: this.bloomProgress,
          debugMaskVisible: false,
          bloomProgress: this.bloomProgress,
        };
      }
    } else {
      this.dwellAccumulatorMs = 0;
    }

    return {
      videoSegment: "openLoop",
      overlayTargetVisible: true,
      overlayIntensity: this.bloomProgress,
      debugMaskVisible: false,
      bloomProgress: this.bloomProgress,
    };
  }

  /**
   * closingTransition: video plays to completion, not interruptible (spec 6.4).
   * Transition back to closed_loop when done.
   */
  private updateClosingTransition(): L1VisualCommand {
    return {
      videoSegment: "closingTransition",
      overlayTargetVisible: true,
      overlayIntensity: this.bloomProgress,
      debugMaskVisible: false,
      bloomProgress: this.bloomProgress,
    };
  }

  // ── Helpers ───────────────────────────────────────────────

  /**
   * Force a transition (used by TrainingRuntime when video_ended events arrive).
   *
   * Spec Section 6.4: transitions are video-driven — when the video ends,
   * the runtime tells the controller to advance to the next state.
   */
  forceTransition(): L1VisualCommand {
    switch (this.currentState) {
      case "openingTransition":
        this.transitionTo("openLoop");
        return {
          videoSegment: "openLoop",
          overlayTargetVisible: true,
          overlayIntensity: this.bloomProgress,
          debugMaskVisible: false,
          bloomProgress: this.bloomProgress,
        };
      case "closingTransition":
        this.transitionTo("closedLoop");
        return {
          videoSegment: "closedLoop",
          overlayTargetVisible: true,
          overlayIntensity: this.bloomProgress,
          debugMaskVisible: false,
          bloomProgress: this.bloomProgress,
        };
      default:
        return this.noopCommand();
    }
  }

  private transitionTo(nextState: L1VisualState): void {
    this.currentState = nextState;
    this.elapsedInStateMs = 0;
    this.dwellAccumulatorMs = 0;
  }

  private noopCommand(): L1VisualCommand {
    return {
      videoSegment: this.currentStateToSegment(),
      overlayTargetVisible: true,
      overlayIntensity: this.bloomProgress,
      debugMaskVisible: false,
      bloomProgress: this.bloomProgress,
    };
  }

  private currentStateToSegment(): L1VisualCommand["videoSegment"] {
    switch (this.currentState) {
      case "closedLoop":         return "closedLoop";
      case "openingTransition":  return "openingTransition";
      case "openLoop":           return "openLoop";
      case "closingTransition":  return "closingTransition";
    }
  }
}
