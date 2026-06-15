import type { NeuroFrame } from "../NeuroFrame";
import type { LevelController } from "./LevelController";

export type RuntimeMode = "training" | "developer";

export type RuntimeTelemetryEvent<TState, TCommand> =
  | {
      type: "runtime_started";
      mode: RuntimeMode;
      timestampMs: number;
    }
  | {
      type: "runtime_stopped";
      timestampMs: number;
    }
  | {
      type: "neuro_frame";
      frame: NeuroFrame;
      timestampMs: number;
    }
  | {
      type: "controller_update";
      state: TState;
      command: TCommand;
      timestampMs: number;
      deltaMs: number;
    };

export interface TrainingRuntimeOptions<TState, TCommand> {
  /**
   * Runtime mode.
   *
   * training:
   *   Hide debug controls and internal telemetry UI.
   *
   * developer:
   *   Enable mock input, debug controls, and state inspection.
   */
  mode: RuntimeMode;

  /**
   * Level controller, e.g. L1Controller.
   */
  controller: LevelController<TState, TCommand>;

  /**
   * Source of standardized neural frames.
   */
  getNeuroFrame: () => NeuroFrame;

  /**
   * Dispatch command to the visual/video environment.
   */
  dispatchVisualCommand: (command: TCommand) => void;

  /**
   * Optional telemetry hook.
   */
  onTelemetry?: (event: RuntimeTelemetryEvent<TState, TCommand>) => void;

  /**
   * Optional frame scheduler.
   * If omitted, requestAnimationFrame will be used when available.
   */
  scheduler?: RuntimeScheduler;
}

export interface RuntimeScheduler {
  requestFrame(callback: () => void): number;
  cancelFrame(id: number): void;
}

function createDefaultScheduler(): RuntimeScheduler {
  if (
    typeof globalThis.requestAnimationFrame === "function" &&
    typeof globalThis.cancelAnimationFrame === "function"
  ) {
    return {
      requestFrame: (callback) => globalThis.requestAnimationFrame(callback),
      cancelFrame: (id) => globalThis.cancelAnimationFrame(id),
    };
  }

  return {
    requestFrame: (callback) => globalThis.setTimeout(callback, 16),
    cancelFrame: (id) => globalThis.clearTimeout(id),
  };
}

function nowMs(): number {
  if (typeof globalThis.performance?.now === "function") {
    return globalThis.performance.now();
  }

  return Date.now();
}

/**
 * TrainingRuntime wires NeuroFrame input, level controller update,
 * visual command dispatch, and telemetry.
 */
export class TrainingRuntime<TState, TCommand> {
  private running = false;
  private lastTimeMs = 0;
  private frameId: number | null = null;
  private readonly scheduler: RuntimeScheduler;

  constructor(private readonly options: TrainingRuntimeOptions<TState, TCommand>) {
    this.scheduler = options.scheduler ?? createDefaultScheduler();
  }

  start(): void {
    if (this.running) {
      return;
    }

    this.running = true;
    this.lastTimeMs = nowMs();

    this.emitTelemetry({
      type: "runtime_started",
      mode: this.options.mode,
      timestampMs: this.lastTimeMs,
    });

    this.frameId = this.scheduler.requestFrame(this.tick);
  }

  stop(): void {
    if (!this.running) {
      return;
    }

    this.running = false;

    if (this.frameId !== null) {
      this.scheduler.cancelFrame(this.frameId);
      this.frameId = null;
    }

    this.emitTelemetry({
      type: "runtime_stopped",
      timestampMs: nowMs(),
    });
  }

  isRunning(): boolean {
    return this.running;
  }

  isDeveloperMode(): boolean {
    return this.options.mode === "developer";
  }

  isTrainingMode(): boolean {
    return this.options.mode === "training";
  }

  private tick = (): void => {
    if (!this.running) {
      return;
    }

    const currentTimeMs = nowMs();
    const deltaMs = currentTimeMs - this.lastTimeMs;
    this.lastTimeMs = currentTimeMs;

    const frame = this.options.getNeuroFrame();

    this.emitTelemetry({
      type: "neuro_frame",
      frame,
      timestampMs: currentTimeMs,
    });

    const command = this.options.controller.update(frame, deltaMs);

    this.emitTelemetry({
      type: "controller_update",
      state: this.options.controller.state,
      command,
      timestampMs: currentTimeMs,
      deltaMs,
    });

    this.options.dispatchVisualCommand(command);

    this.frameId = this.scheduler.requestFrame(this.tick);
  };

  private emitTelemetry(event: RuntimeTelemetryEvent<TState, TCommand>): void {
    this.options.onTelemetry?.(event);
  }
}