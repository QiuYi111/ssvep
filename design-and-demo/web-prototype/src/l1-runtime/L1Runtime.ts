import { MockNeuroSource } from "./bci/MockNeuroSource";
import type { NeuroFrame } from "./NeuroFrame";
import { L1Controller, DEFAULT_L1_OPTIONS } from "./levels/L1Controller";
import type { L1VisualCommand, L1VisualState } from "./levels/L1Controller";
import { SSVEPOverlay } from "./overlay/SSVEPOverlay";
import { TrainingRuntime } from "./runtime/TrainingRuntime";
import type { RuntimeMode, RuntimeTelemetryEvent } from "./runtime/TrainingRuntime";
import { TelemetrySystem } from "./telemetry/TelemetrySystem";
import {
  VideoEnvironmentController,
  type LevelVideoConfig,
  type VideoSegmentKey,
} from "./video/VideoEnvironmentController";

type LevelConfig = LevelVideoConfig & {
  id?: string;
  target?: {
    x: number;
    y: number;
    radius: number;
    frequencyHz: number;
    color: string;
    opacityMin: number;
    opacityMax: number;
    modulation: "smooth_sine";
  };
  controller?: Partial<typeof DEFAULT_L1_OPTIONS>;
  debug?: {
    showMaskByDefault?: boolean;
    showTelemetryByDefault?: boolean;
  };
};

export interface L1RuntimeOptions {
  levelBasePath?: string;
  mode?: RuntimeMode;
}

export interface L1RuntimeHandle {
  pause(): void;
  resume(): void;
  stop(): void;
  dumpTelemetry(): string;
  getState(): L1VisualState;
  getBloomProgress(): number;
}

export async function mountL1Runtime(
  container: HTMLElement,
  options: L1RuntimeOptions = {},
): Promise<L1RuntimeHandle> {
  const levelBasePath = normalizeBasePath(
    options.levelBasePath ?? new URL("levels/l1", document.baseURI).toString(),
  );
  const runtimeMode = options.mode ?? "developer";

  container.innerHTML = "";
  container.classList.add("l1-runtime-host");

  const videoEl = document.createElement("video");
  videoEl.id = "l1-ssvep-video";
  videoEl.muted = true;
  videoEl.playsInline = true;
  videoEl.style.cssText = "position:absolute;inset:0;width:100%;height:100%;object-fit:contain;";

  const canvasEl = document.createElement("canvas");
  canvasEl.id = "l1-ssvep-overlay";
  canvasEl.style.cssText = "position:absolute;inset:0;width:100%;height:100%;pointer-events:none;";

  const devPanel = document.createElement("div");
  devPanel.id = "l1-dev-panel";
  devPanel.style.cssText =
    "position:absolute;top:12px;right:12px;background:rgba(0,0,0,.75);color:#fff;" +
    "padding:12px 16px;border-radius:8px;font:12px monospace;z-index:20;max-width:280px;";
  devPanel.style.display = "none";

  container.append(videoEl, canvasEl, devPanel);

  let latestNeuroFrame: NeuroFrame | null = null;
  let lastState: L1VisualState | null = null;

  const levelConfig = await loadLevelConfig(levelBasePath);
  const videoCtrl = new VideoEnvironmentController(videoEl, levelBasePath);
  await videoCtrl.loadLevel(levelConfig);

  const overlay = new SSVEPOverlay(canvasEl, videoEl);
  configureOverlayFromLevel(overlay, levelConfig);

  const neuroSource = new MockNeuroSource();
  const controller = new L1Controller({
    ...DEFAULT_L1_OPTIONS,
    ...levelConfig.controller,
  });
  const telemetry = new TelemetrySystem();
  const sessionStartMs = performance.now();

  const recordTransition = (from: L1VisualState, to: L1VisualState, reason: string): void => {
    telemetry.record("l1_state_transition", {
      type: "l1_state_transition",
      timestampMs: performance.now(),
      from,
      to,
      reason,
      bloomProgress: controller.getBloomProgress(),
    });
  };

  videoCtrl.onEvent((event) => {
    telemetry.record(event.type, event);
    if (event.type !== "video_ended") return;

    if (event.segment === "openingTransition" || event.segment === "closingTransition") {
      const from = controller.state;
      const cmd = controller.forceTransition();
      if (from !== controller.state) {
        recordTransition(from, controller.state, `video_ended:${event.segment}`);
      }
      dispatchCommand(cmd);
    }
  });

  neuroSource.subscribe((frame) => {
    latestNeuroFrame = frame;
  });

  const runtime = new TrainingRuntime<L1VisualState, L1VisualCommand>({
    mode: runtimeMode,
    controller,
    getNeuroFrame: () => latestNeuroFrame ?? createDefaultFrame(),
    dispatchVisualCommand: (cmd) => dispatchCommand(cmd),
    onTelemetry: (event) => recordRuntimeEvent(event),
  });

  function dispatchCommand(cmd: L1VisualCommand): void {
    const currentSegment = videoCtrl.getCurrentSegment();
    if (cmd.videoSegment !== currentSegment) {
      const segmentKey = cmd.videoSegment as VideoSegmentKey;
      const loop = segmentKey === "closedLoop" || segmentKey === "openLoop";
      videoCtrl.playSegment(segmentKey, { loop }).catch((err: unknown) => {
        telemetry.record("runtime_error", {
          type: "runtime_error",
          timestampMs: performance.now(),
          code: "video_play_failed",
          message: String(err),
          context: { segment: segmentKey },
        });
      });
    }

    const targetConfig = levelConfig.target;
    overlay.target.setConfig({
      opacityMin: targetConfig
        ? targetConfig.opacityMin * (0.3 + cmd.overlayIntensity * 0.7)
        : 0.08 + cmd.overlayIntensity * 0.2,
      opacityMax: targetConfig
        ? targetConfig.opacityMax * (0.25 + cmd.overlayIntensity * 0.75)
        : 0.25 + cmd.overlayIntensity * 0.55,
    });
    updateDevPanel();
  }

  function recordRuntimeEvent(
    event: RuntimeTelemetryEvent<L1VisualState, L1VisualCommand>,
  ): void {
    telemetry.record(event.type, event);

    if (event.type === "controller_update") {
      if (lastState !== null && lastState !== event.state) {
        recordTransition(lastState, event.state, "controller_update");
      }
      lastState = event.state;
    }
  }

  function createDevPanel(): void {
    if (runtimeMode !== "developer") return;
    devPanel.style.display = "block";
    devPanel.innerHTML = `
      <div style="font-weight:bold;margin-bottom:8px;">L1 Dev Controls</div>
      <label>Attention: <span id="l1-dev-att-val">0.50</span></label>
      <input type="range" id="l1-dev-att" min="0" max="1" step="0.01" value="0.5" style="width:100%;">
      <label style="display:block;margin-top:6px;">Signal:
        <select id="l1-dev-signal" style="margin-left:4px;">
          <option value="good">good</option>
          <option value="poor">poor</option>
          <option value="lost">lost</option>
        </select>
      </label>
      <label style="display:block;margin-top:4px;">
        <input type="checkbox" id="l1-dev-debug-mask"> Show Debug Mask
      </label>
      <label style="display:block;margin-top:4px;">
        <input type="checkbox" id="l1-dev-deterministic"> Deterministic Mode
      </label>
      <hr style="border-color:#444;margin:6px 0;">
      <div>State: <span id="l1-dev-state" style="color:#ffe9a6;">closedLoop</span></div>
      <div>Bloom: <span id="l1-dev-bloom">0.000</span></div>
      <button id="l1-dev-reset" style="margin-top:6px;">Reset</button>
      <button id="l1-dev-dump" style="margin-top:6px;">Dump Telemetry</button>
    `;

    const attSlider = devPanel.querySelector<HTMLInputElement>("#l1-dev-att");
    const attVal = devPanel.querySelector<HTMLElement>("#l1-dev-att-val");
    attSlider?.addEventListener("input", () => {
      const value = Number(attSlider.value);
      if (attVal) attVal.textContent = value.toFixed(2);
      neuroSource.manualAttention = value;
    });

    devPanel.querySelector<HTMLSelectElement>("#l1-dev-signal")?.addEventListener("change", (event) => {
      neuroSource.manualQuality = (event.currentTarget as HTMLSelectElement).value as typeof neuroSource.manualQuality;
    });

    devPanel.querySelector<HTMLInputElement>("#l1-dev-debug-mask")?.addEventListener("change", (event) => {
      overlay.setDebugMask((event.currentTarget as HTMLInputElement).checked);
    });

    devPanel.querySelector<HTMLInputElement>("#l1-dev-deterministic")?.addEventListener("change", (event) => {
      neuroSource.isDeterministic = (event.currentTarget as HTMLInputElement).checked;
    });

    devPanel.querySelector("#l1-dev-reset")?.addEventListener("click", () => {
      controller.reset();
      videoCtrl.playSegment("closedLoop", { loop: true });
      updateDevPanel();
    });

    devPanel.querySelector("#l1-dev-dump")?.addEventListener("click", () => {
      const jsonl = telemetry.dumpSessionJSONL();
      console.log("=== L1 TELEMETRY JSONL ===\n" + jsonl);
      alert(`Telemetry: ${jsonl.split("\n").filter(Boolean).length} events dumped to console.`);
    });
  }

  function updateDevPanel(): void {
    if (runtimeMode !== "developer") return;
    const stateEl = devPanel.querySelector<HTMLElement>("#l1-dev-state");
    const bloomEl = devPanel.querySelector<HTMLElement>("#l1-dev-bloom");
    if (stateEl) stateEl.textContent = controller.state;
    if (bloomEl) bloomEl.textContent = controller.getBloomProgress().toFixed(3);
  }

  telemetry.record("session_start", {
    type: "session_start",
    timestampMs: sessionStartMs,
    levelId: levelConfig.id ?? "l1",
    runtimeMode,
  });

  createDevPanel();
  neuroSource.start();
  overlay.start();
  runtime.start();
  try {
    await videoCtrl.playSegment("closedLoop", { loop: true });
  } catch (err) {
    runtime.stop();
    overlay.stop();
    neuroSource.stop();
    telemetry.dispose();
    throw err;
  }

  return {
    pause: () => videoCtrl.pause(),
    resume: () => videoCtrl.resume(),
    stop: () => {
      runtime.stop();
      overlay.stop();
      neuroSource.stop();
      videoCtrl.pause();
      telemetry.record("session_end", {
        type: "session_end",
        timestampMs: performance.now(),
        levelId: levelConfig.id ?? "l1",
        durationMs: performance.now() - sessionStartMs,
      });
      telemetry.dispose();
      container.innerHTML = "";
      container.classList.remove("l1-runtime-host");
    },
    dumpTelemetry: () => telemetry.dumpSessionJSONL(),
    getState: () => controller.state,
    getBloomProgress: () => controller.getBloomProgress(),
  };
}

async function loadLevelConfig(levelBasePath: string): Promise<LevelConfig> {
  const response = await fetch(`${levelBasePath}/level.json`);
  if (!response.ok) {
    throw new Error(`LevelResourceError: l1 missing level.json (${response.status})`);
  }
  return response.json() as Promise<LevelConfig>;
}

function configureOverlayFromLevel(overlay: SSVEPOverlay, levelConfig: LevelConfig): void {
  const target = levelConfig.target;
  if (!target) return;

  overlay.setTargetPos(target.x, target.y);
  overlay.setConfig({
    frequencyHz: target.frequencyHz,
    opacityMin: target.opacityMin,
    opacityMax: target.opacityMax,
    color: target.color,
    radius: target.radius,
    modulation: target.modulation,
  });
  overlay.setDebugMask(Boolean(levelConfig.debug?.showMaskByDefault));
}

function createDefaultFrame(): NeuroFrame {
  return {
    timestampMs: performance.now(),
    source: "mock",
    attention: null,
    signalQuality: "unknown",
  };
}

function normalizeBasePath(path: string): string {
  return path.replace(/\/+$/, "");
}
