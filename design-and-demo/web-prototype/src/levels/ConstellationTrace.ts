import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import { drawGlow, drawStarField, drawNoiseFog, drawVignette } from '../utils/drawing';
import { TARGET_WARM_GOLD, DISTRACTOR_COLD_BLUE, LEVEL_THEMES, rgba } from '../utils/color';
import { noise2D } from '../utils/noise';

interface ConstellationNode {
  /** Fraction of screen width [0..1] */
  x: number;
  /** Fraction of screen height [0..1] */
  y: number;
}

interface ConstellationLink {
  from: number;
  to: number;
}

/**
 * Level 3 — 星图寻迹 (Constellation Trace)
 *
 * Deep-space scene with two SSVEP-tagged constellations.
 * The player must focus on the warm-gold target constellation
 * while ignoring the cold-blue distractor.
 */
export class ConstellationTrace extends LevelRenderer {
  readonly name = '星图寻迹';
  readonly subtitle = '星光交织，辨别方向';

  // ── Pre-generated constellation data (screen-relative coords) ──────────
  private targetNodes: ConstellationNode[] = [];
  private targetLinks: ConstellationLink[] = [];
  private distractorNodes: ConstellationNode[] = [];
  private distractorLinks: ConstellationLink[] = [];

  // ── Starfield seed (stable per session) ────────────────────────────────
  private starSeed = 7749;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  enter(): void {
    super.enter();
    this.starSeed = 7749;

    // Target constellation — "bow / dipper" shape, organic curves
    // Centered ~35 % from left, ~45 % from top
    this.targetNodes = [
      { x: 0.22, y: 0.38 }, // leftmost tip
      { x: 0.27, y: 0.30 }, // upper curve
      { x: 0.33, y: 0.28 }, // peak
      { x: 0.38, y: 0.34 }, // descending
      { x: 0.40, y: 0.45 }, // lower bend
      { x: 0.34, y: 0.52 }, // tail start
      { x: 0.28, y: 0.50 }, // tail end
    ];
    this.targetLinks = [
      { from: 0, to: 1 },
      { from: 1, to: 2 },
      { from: 2, to: 3 },
      { from: 3, to: 4 },
      { from: 4, to: 5 },
      { from: 5, to: 6 },
      { from: 6, to: 0 }, // close the loop softly
    ];

    // Distractor constellation — "W / zigzag" shape, sharp angles
    // Centered ~70 % from left, ~40 % from top
    this.distractorNodes = [
      { x: 0.62, y: 0.28 }, // top-left of W
      { x: 0.65, y: 0.44 }, // first valley
      { x: 0.69, y: 0.30 }, // middle peak
      { x: 0.73, y: 0.46 }, // second valley
      { x: 0.76, y: 0.28 }, // top-right of W
      { x: 0.80, y: 0.50 }, // trailing point
    ];
    this.distractorLinks = [
      { from: 0, to: 1 },
      { from: 1, to: 2 },
      { from: 2, to: 3 },
      { from: 3, to: 4 },
      { from: 4, to: 5 },
    ];
  }

  // ── Drawing ────────────────────────────────────────────────────────────

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width: w, height: h } = rc;
    const t = this.levelTime;
    const att = state.attention;

    // Dynamic subtitle
    this.updateSubtitle(att);

    // 1 ── Background gradient ─────────────────────────────────────────
    this.drawBackground(ctx, w, h);

    // 2 ── Dense starfield ─────────────────────────────────────────────
    drawStarField(ctx, w, h, state.particleDensity * 0.8, this.starSeed);

    // 3 ── Nebula fog (very subtle purple tint) ────────────────────────
    drawNoiseFog(ctx, w, h, t, 0.03, LEVEL_THEMES[2].accent, noise2D);

    // 4 ── Distractor constellation (cold blue, distractorFrequency) ───
    const distractorBaseOpacity = this.ssvep(t, state.distractorFrequency, 0.55, 1.0);
    const distractorOpacity = distractorBaseOpacity * (1.0 - att * 0.35); // fades with high attention
    this.drawConstellation(
      ctx, w, h,
      this.distractorNodes,
      this.distractorLinks,
      DISTRACTOR_COLD_BLUE,
      distractorOpacity,
      8,       // node glow radius
      0.12,    // line alpha base
      1,       // line width
      att,
    );

    // 5 ── Target constellation (warm gold, targetFrequency) ───────────
    const targetBaseOpacity = this.ssvep(t, state.targetFrequency, 0.55, 1.0);
    const targetOpacity = targetBaseOpacity * (0.65 + att * 0.35); // brightens with high attention
    this.drawConstellation(
      ctx, w, h,
      this.targetNodes,
      this.targetLinks,
      TARGET_WARM_GOLD,
      targetOpacity,
      10,      // slightly larger nodes
      0.18,    // slightly brighter lines
      1.5,     // slightly thicker lines
      att,
    );

    // 6 ── Vignette ────────────────────────────────────────────────────
    drawVignette(ctx, w, h, 0.35);

    // 7 ── Target mask (debug helper) ──────────────────────────────────
    if (state.showTargetMask) {
      this.drawTargetMask(ctx, w, h);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────

  private updateSubtitle(attention: number): void {
    if (attention > 0.7) {
      (this as { subtitle: string }).subtitle = '星图清晰，目标闪耀';
    } else if (attention > 0.3) {
      (this as { subtitle: string }).subtitle = '星光交织，辨别方向';
    } else {
      (this as { subtitle: string }).subtitle = '星轨模糊，干扰渐强';
    }
  }

  private drawBackground(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
  ): void {
    const theme = LEVEL_THEMES[2];
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#0d0520');
    grad.addColorStop(0.5, theme.bg);
    grad.addColorStop(1, '#08031a');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
  }

  /**
   * Renders a single constellation: glow nodes + connecting lines.
   */
  private drawConstellation(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    nodes: ConstellationNode[],
    links: ConstellationLink[],
    color: string,
    opacity: number,
    nodeRadius: number,
    lineAlphaBase: number,
    lineWidth: number,
    attention: number,
    bloom: number = 1.5,
  ): void {
    // Pre-compute pixel positions
    const px: { x: number; y: number }[] = nodes.map((n) => ({
      x: n.x * w,
      y: n.y * h,
    }));

    // Draw connecting lines
    ctx.save();
    ctx.strokeStyle = rgba(color, lineAlphaBase * (0.6 + attention * 0.4));
    ctx.lineWidth = lineWidth;
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (const link of links) {
      ctx.moveTo(px[link.from].x, px[link.from].y);
      ctx.lineTo(px[link.to].x, px[link.to].y);
    }
    ctx.stroke();
    ctx.restore();

    // Draw glow nodes
    for (const p of px) {
      drawGlow(ctx, p.x, p.y, nodeRadius, color, opacity, bloom);
      
      // Star flare (cross)
      ctx.save();
      ctx.globalCompositeOperation = 'screen';
      ctx.fillStyle = rgba(color, opacity * 0.8);
      ctx.beginPath();
      ctx.ellipse(p.x, p.y, nodeRadius * 3, nodeRadius * 0.2, 0, 0, Math.PI * 2);
      ctx.ellipse(p.x, p.y, nodeRadius * 0.2, nodeRadius * 3, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }

  /**
   * Red circle outline around the target constellation area.
   */
  private drawTargetMask(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
  ): void {
    // Compute bounding box of target constellation
    let minX = 1, minY = 1, maxX = 0, maxY = 0;
    for (const n of this.targetNodes) {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    }
    const cx = ((minX + maxX) / 2) * w;
    const cy = ((minY + maxY) / 2) * h;
    const rx = ((maxX - minX) / 2 + 0.04) * w;
    const ry = ((maxY - minY) / 2 + 0.06) * h;
    const r = Math.max(rx, ry);

    ctx.save();
    ctx.strokeStyle = 'rgba(255, 80, 80, 0.6)';
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 4]);
    ctx.beginPath();
    ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.restore();
  }
}
