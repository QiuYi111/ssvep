import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import {
  drawFirefly,
  drawGlow,
  drawNoiseFog,
  drawStarField,
  drawTreeSilhouette,
  drawVignette,
} from '../utils/drawing';
import {
  TARGET_BIO_GREEN,
  TARGET_WARM_GOLD,
  DISTRACTOR_COLD_BLUE,
  LEVEL_THEMES,
  rgba,
  lerpColor,
} from '../utils/color';
import { noise2D } from '../utils/noise';

function seededRandom(seed: number): () => number {
  let s = seed | 0;
  if (s === 0) s = 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

interface FireflyData {
  baseX: number;
  baseY: number;
  angle: number;
  orbitRadius: number;
  speed: number;
  size: number;
}

export class DualFireflies extends LevelRenderer {
  readonly name = '真假萤火';
  private _subtitle = '真假交织，保持专注';
  get subtitle(): string { return this._subtitle; }

  private targetFireflies: FireflyData[] = [];
  private distractorFireflies: FireflyData[] = [];
  private framingTrees: { x: number; h: number; tw: number; cr: number }[] = [];
  private rand = seededRandom(0x4d4f43);

  enter(): void {
    super.enter();
    this.rand = seededRandom(0x4d4f43);

    const targetCount = 6 + Math.floor(this.rand() * 5);
    this.targetFireflies = [];
    for (let i = 0; i < targetCount; i++) {
      const a = this.rand() * Math.PI * 2;
      const d = this.rand() * 0.12;
      this.targetFireflies.push({
        baseX: 0.5 + Math.cos(a) * d,
        baseY: 0.48 + Math.sin(a) * d,
        angle: this.rand() * Math.PI * 2,
        orbitRadius: 0.01 + this.rand() * 0.025,
        speed: 0.15 + this.rand() * 0.2,
        size: 4 + this.rand() * 3,
      });
    }

    const distractorCount = 8 + Math.floor(this.rand() * 5);
    this.distractorFireflies = [];
    for (let i = 0; i < distractorCount; i++) {
      const a = this.rand() * Math.PI * 2;
      const d = 0.30 + this.rand() * 0.15;
      this.distractorFireflies.push({
        baseX: 0.5 + Math.cos(a) * d,
        baseY: 0.48 + Math.sin(a) * d,
        angle: this.rand() * Math.PI * 2,
        orbitRadius: 0.02 + this.rand() * 0.04,
        speed: 0.8 + this.rand() * 1.2,
        size: 3 + this.rand() * 2.5,
      });
    }

    this.framingTrees = [
      { x: 0.08, h: 0.35, tw: 12, cr: 40 },
      { x: 0.92, h: 0.30, tw: 10, cr: 35 },
    ];
    if (this.rand() > 0.4) {
      this.framingTrees.push({ x: 0.78, h: 0.25, tw: 8, cr: 28 });
    }
  }

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width, height } = rc;
    const t = this.levelTime;
    const att = state.attention;
    const theme = LEVEL_THEMES[3];

    // 1. Background gradient
    const bgGrad = ctx.createLinearGradient(0, 0, 0, height);
    bgGrad.addColorStop(0, '#0d0505');
    bgGrad.addColorStop(0.5, theme.bg);
    bgGrad.addColorStop(1, '#0a0404');
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, width, height);

    // 2. Sparse stars
    drawStarField(ctx, width, height, state.particleDensity * 0.2, 37);

    // 3. Framing tree silhouettes
    ctx.globalAlpha = 0.7;
    for (const tree of this.framingTrees) {
      drawTreeSilhouette(ctx, tree.x * width, height * 0.95, tree.h * height, tree.tw, tree.cr, '#0a0404');
    }
    ctx.globalAlpha = 1;

    // 4. Background fog
    drawNoiseFog(ctx, width, height, t, 0.03, theme.bg);

    // 5. Life tree (recursive fractal, depth=4..6 based on attention)
    this.drawLifeTree(ctx, width * 0.5, height * 0.92, height * 0.5, att, t);

    // 6. Distractor fireflies — blue, outer ring, erratic
    const distractorPush = att > 0.5 ? 0 : (0.5 - att) * 0.06;
    for (const fly of this.distractorFireflies) {
      const nx = noise2D(fly.angle + t * fly.speed * 0.7, 0) - 0.5;
      const ny = noise2D(0, fly.angle + t * fly.speed * 0.7) - 0.5;
      const jitter = 0.03;
      const px = fly.baseX + nx * jitter + Math.sin(t * fly.speed + fly.angle) * fly.orbitRadius;
      const py = fly.baseY + ny * jitter + Math.cos(t * fly.speed * 0.8 + fly.angle) * fly.orbitRadius;

      const dx = px - 0.5;
      const dy = py - 0.48;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const pushX = dist > 0.001 ? (dx / dist) * distractorPush : 0;
      const pushY = dist > 0.001 ? (dy / dist) * distractorPush : 0;

      const fx = (px + pushX) * width;
      const fy = (py + pushY) * height;

      const brightness = this.ssvep(t, state.distractorFrequency, 0.50, 1.0);
      drawFirefly(ctx, fx, fy, fly.size, DISTRACTOR_COLD_BLUE, brightness, 1.0);
    }

    // 7. Target fireflies — yellow-green, inner area, slow clustered
    const clusterFactor = 1 - att * 0.5;
    for (const fly of this.targetFireflies) {
      const px = fly.baseX + Math.sin(t * fly.speed + fly.angle) * fly.orbitRadius * clusterFactor;
      const py = fly.baseY + Math.cos(t * fly.speed * 0.7 + fly.angle) * fly.orbitRadius * clusterFactor * 0.8;

      const fx = px * width;
      const fy = py * height;

      const brightness = this.ssvep(t, state.targetFrequency, 0.50, 1.0);
      const color = lerpColor(TARGET_BIO_GREEN, TARGET_WARM_GOLD, 0.4);
      drawFirefly(ctx, fx, fy, fly.size * 1.1, color, brightness, state.bloomStrength * 2 + 1);
    }

    // 8. Foreground fog (denser at bottom)
    ctx.save();
    const fogGrad = ctx.createLinearGradient(0, height * 0.5, 0, height);
    fogGrad.addColorStop(0, 'rgba(26,10,10,0)');
    fogGrad.addColorStop(1, 'rgba(26,10,10,0.15)');
    ctx.fillStyle = fogGrad;
    ctx.fillRect(0, 0, width, height);
    ctx.restore();
    drawNoiseFog(ctx, width, height, t * 0.3, 0.02, '#1a0a0a');

    // 9. Vignette
    drawVignette(ctx, width, height, 0.45);

    // 10. Target mask
    if (state.showTargetMask) {
      ctx.save();
      ctx.strokeStyle = rgba(TARGET_BIO_GREEN, 0.25);
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.arc(width * 0.5, height * 0.48, Math.min(width, height) * 0.16, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }

    if (att > 0.7) {
      this._subtitle = '萤火归心，生命之树生长';
    } else if (att > 0.3) {
      this._subtitle = '真假交织，保持专注';
    } else {
      this._subtitle = '蓝光侵袭，树影渐淡';
    }
  }

  private drawLifeTree(
    ctx: CanvasRenderingContext2D,
    x: number,
    baseY: number,
    treeHeight: number,
    attention: number,
    time: number,
  ): void {
    const maxDepth = 4 + Math.round(attention * 2);

    if (attention > 0.3) {
      const glowOpacity = (attention - 0.3) * 0.3;
      drawGlow(ctx, x, baseY, treeHeight * 0.25, '#ff8f00', glowOpacity, 1.5);
    }

    const trunkLen = treeHeight * (0.2 + attention * 0.05);
    this.drawBranch(ctx, x, baseY, -Math.PI / 2, trunkLen, maxDepth, 0, attention, time);
  }

  private drawBranch(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    angle: number,
    length: number,
    maxDepth: number,
    depth: number,
    attention: number,
    time: number,
  ): void {
    if (depth > maxDepth || length < 2) return;

    const endX = x + Math.cos(angle) * length;
    const endY = y + Math.sin(angle) * length;

    const depthRatio = depth / maxDepth;
    const branchColor = lerpColor('#3e2723', '#1a0a0a', depthRatio * 0.6);
    const thickness = Math.max(0.5, (maxDepth - depth + 1) * 1.2);
    const sway = Math.sin(time * 0.5 + depth * 0.7 + x * 0.01) * 0.02 * depth;

    ctx.save();
    ctx.strokeStyle = branchColor;
    ctx.lineWidth = thickness;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(x, y);
    const cpX = x + Math.cos(angle) * length * 0.5 + Math.sin(sway) * length * 0.2;
    const cpY = y + Math.sin(angle) * length * 0.5;
    ctx.quadraticCurveTo(cpX, cpY, endX + Math.cos(angle + sway) * length * 0.05, endY + Math.sin(angle + sway) * length * 0.05);
    ctx.stroke();
    ctx.restore();

    if (depth === maxDepth && attention > 0.5) {
      const leafOpacity = (attention - 0.5) * 1.5;
      ctx.save();
      ctx.globalAlpha = Math.min(1, leafOpacity);
      ctx.fillStyle = lerpColor('#2e7d32', '#cddc39', 0.3);
      const leafSize = 2 + (attention - 0.5) * 3;
      ctx.beginPath();
      ctx.arc(endX, endY, leafSize, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    if (depth < maxDepth) {
      const spread = (25 + Math.random() * 10) * (Math.PI / 180);
      const shrink = 0.62 + attention * 0.08;
      this.drawBranch(ctx, endX, endY, angle - spread, length * shrink, maxDepth, depth + 1, attention, time);
      this.drawBranch(ctx, endX, endY, angle + spread, length * shrink, maxDepth, depth + 1, attention, time);
    }
  }
}
