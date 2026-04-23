import type { RenderContext } from './types';

export class Renderer {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;
  private _width = 0;
  private _height = 0;
  private _dpr = 1;

  constructor(canvasId: string) {
    const el = document.getElementById(canvasId);
    if (!el || !(el instanceof HTMLCanvasElement)) {
      throw new Error(`Canvas element #${canvasId} not found`);
    }
    this.canvas = el;
    const ctx = el.getContext('2d');
    if (!ctx) throw new Error('Failed to acquire 2D context');
    this.ctx = ctx;
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  private resize(): void {
    this._dpr = window.devicePixelRatio || 1;
    this._width = window.innerWidth;
    this._height = window.innerHeight;
    this.canvas.width = this._width * this._dpr;
    this.canvas.height = this._height * this._dpr;
    this.ctx.setTransform(this._dpr, 0, 0, this._dpr, 0, 0);
  }

  get renderContext(): RenderContext {
    return {
      ctx: this.ctx,
      width: this._width,
      height: this._height,
      dpr: this._dpr,
    };
  }

  get width(): number { return this._width; }
  get height(): number { return this._height; }
  get dpr(): number { return this._dpr; }

  clear(bgColor = '#000000'): void {
    const { ctx } = this;
    ctx.setTransform(this._dpr, 0, 0, this._dpr, 0, 0);
    ctx.fillStyle = bgColor;
    ctx.fillRect(0, 0, this._width, this._height);
  }
}
