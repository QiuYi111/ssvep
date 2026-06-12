import type { AppState, RenderContext } from '../core/types';

export abstract class LevelRenderer {
  abstract name: string;
  abstract subtitle: string;
  protected levelTime = 0;

  update(dt: number, state: AppState): void {
    this.levelTime += state.reduceMotion ? dt * 0.2 : dt;
  }

  abstract draw(ctx: RenderContext, state: AppState): void;

  enter(): void { this.levelTime = 0; }
  leave(): void {}

  protected ssvep(time: number, freq: number, min = 0.60, max = 1.0): number {
    const phase = Math.sin(time * Math.PI * 2 * freq) * 0.5 + 0.5;
    return min + (max - min) * phase;
  }
}
