// SSVEPOverlay.ts
import { TargetLight } from "./TargetLight";
import { DebugMask } from "./DebugMask";

export class SSVEPOverlay {
  public target: TargetLight;
  public debugMask: DebugMask;
  private frameId: number | null = null;
  private running = false;

  constructor(canvas: HTMLCanvasElement, video: HTMLVideoElement) {
    // 初始化目标
    this.target = new TargetLight(canvas, video);

    // 初始化调试遮罩
    this.debugMask = new DebugMask(this.target.gl);
  }

  // 统一更新（一帧更新所有）
  update() {
    // 1. 更新目标
    this.target.update();

    // 2. 用目标的坐标画遮罩（完全对齐）
    const { cssX, cssY, cssRadius } = this.target.getRenderedTargetRect();
    const { glX, glY, glScale } = this.target.toWebGLCoords(cssX, cssY, cssRadius);
    this.debugMask.draw(glX, glY, glScale);
  }

  // 统一启动
  start() {
    if (this.running) return;
    this.running = true;

    const loop = () => {
      if (!this.running) return;
      this.update();
      this.frameId = requestAnimationFrame(loop);
    };
    this.frameId = requestAnimationFrame(loop);
  }

  stop() {
    this.running = false;
    if (this.frameId !== null) {
      cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
  }

  // 外部开关调试遮罩
  setDebugMask(enabled: boolean) {
    this.debugMask.enabled = enabled;
  }

  // 外部设置目标位置
  setTargetPos(x: number, y: number) {
    this.target.targetPos.x = x;
    this.target.targetPos.y = y;
  }

  // 外部设置配置
  setConfig(config: any) {
    this.target.setConfig(config);
  }
}
