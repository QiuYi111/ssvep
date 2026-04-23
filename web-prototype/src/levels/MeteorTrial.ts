import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import {
  drawMoon,
  drawAurora,
  drawStarField,
  drawMountainSilhouette,
  drawVignette,
  drawGlow,
  drawNoiseFog,
} from '../utils/drawing';
import { TARGET_WARM_GOLD, LEVEL_THEMES, rgba } from '../utils/color';
import { noise2D } from '../utils/noise';

interface MeteorState {
  active: boolean;
  x: number;
  y: number;
  dx: number;
  dy: number;
  life: number;
  maxLife: number;
  length: number;
}

export class MeteorTrial extends LevelRenderer {
  readonly name = '流星试炼';
  readonly subtitle = '星光明灭，守望山巅';

  private meteor: MeteorState = {
    active: false,
    x: 0,
    y: 0,
    dx: 0,
    dy: 0,
    life: 0,
    maxLife: 0.4,
    length: 100,
  };
  private meteorCooldown = 3 + Math.random() * 3;
  private peakX = 0;
  private peakY = 0;
  private starSeed = 9999;

  enter(): void {
    super.enter();
    this.starSeed = Math.floor(Math.random() * 10000);
    this.meteorCooldown = 3 + Math.random() * 3;
    this.meteor.active = false;
  }

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width: w, height: h } = rc;
    const t = this.levelTime;
    const att = state.attention;
    const dt = state.reduceMotion ? 0.016 * 0.2 : 0.016;

    // ── Dynamic subtitle ────────────────────────────────────────────────
    if (att > 0.7) {
      (this as { subtitle: string }).subtitle = '月华如水，雪山静穆';
    } else if (att > 0.3) {
      (this as { subtitle: string }).subtitle = '星光明灭，守望山巅';
    } else {
      (this as { subtitle: string }).subtitle = '流星划过，星光暗淡';
    }

    const mountainBaseY = h * 0.60;
    const peakHeight = h * 0.28;
    this.peakX = w * 0.50;
    this.peakY = mountainBaseY - peakHeight;

    // ── 1. Background — darkest level ───────────────────────────────────
    const bgGrad = ctx.createLinearGradient(0, 0, 0, h);
    bgGrad.addColorStop(0, '#0a0a04');
    bgGrad.addColorStop(0.55, '#1a1a0a');
    bgGrad.addColorStop(0.7, '#14140a');
    bgGrad.addColorStop(1, '#0a0a04');
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, w, h);

    // ── 2. Sparse stars — top 40% only ──────────────────────────────────
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, w, h * 0.4);
    ctx.clip();
    drawStarField(ctx, w, h, state.particleDensity * 0.3, this.starSeed);
    ctx.restore();

    // ── 3. Aurora — barely visible hint at top 15% ──────────────────────
    const auroraOpacity = 0.03 + (1 - att) * 0.03;
    drawAurora(ctx, w, 0, h * 0.15, t, auroraOpacity);

    // ── 4. Mountain silhouette — single large mountain ──────────────────
    drawMountainSilhouette(ctx, w, mountainBaseY, peakHeight, '#080808');

    // ── 5. Snow highlight on mountain peak ──────────────────────────────
    const snowAlpha = 0.02 + att * 0.03;
    ctx.save();
    const snowGrad = ctx.createRadialGradient(
      this.peakX,
      this.peakY + 20,
      0,
      this.peakX,
      this.peakY + 40,
      h * 0.15,
    );
    snowGrad.addColorStop(0, rgba(TARGET_WARM_GOLD, snowAlpha));
    snowGrad.addColorStop(0.4, rgba(TARGET_WARM_GOLD, snowAlpha * 0.3));
    snowGrad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = snowGrad;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();

    // ── 6. Star/Moon (target) at mountain peak ──────────────────────────
    const radius = 4 + att * 12;
    const phase = 0.1 + att * 0.9;
    const ssvepOpacity = this.ssvep(t, state.targetFrequency, 0.60, 1.0);

    drawGlow(
      ctx,
      this.peakX,
      this.peakY - 10,
      radius * 4,
      TARGET_WARM_GOLD,
      ssvepOpacity * 0.08,
      1,
    );

    drawMoon(
      ctx,
      this.peakX,
      this.peakY - 10,
      radius,
      phase,
      TARGET_WARM_GOLD,
      ssvepOpacity,
    );

    // ── 7. Cloud cover at low attention ─────────────────────────────────
    if (att < 0.5) {
      const cloudAlpha = (0.5 - att) * 0.3;
      ctx.save();
      ctx.globalAlpha = cloudAlpha;
      ctx.fillStyle = '#0a0e1a';

      const cloudOffset = Math.sin(t * 0.3) * radius * 0.5;
      ctx.beginPath();
      ctx.arc(
        this.peakX + cloudOffset - radius * 0.3,
        this.peakY - 10 + radius * 0.1,
        radius * 0.7,
        0,
        Math.PI * 2,
      );
      ctx.fill();

      ctx.beginPath();
      ctx.arc(
        this.peakX + cloudOffset + radius * 0.4,
        this.peakY - 10 - radius * 0.15,
        radius * 0.5,
        0,
        Math.PI * 2,
      );
      ctx.fill();

      ctx.restore();
    }

    // ── 8. Meteor (distractor) ──────────────────────────────────────────
    this.updateMeteor(dt, att, w, h);
    if (this.meteor.active) {
      this.drawMeteor(ctx, this.meteor);
    }

    // ── 9. Very faint noise fog for depth ───────────────────────────────
    drawNoiseFog(ctx, w, h, t * 0.1, 0.015, LEVEL_THEMES[5].bg, noise2D);

    // ── 10. Vignette — strongest of all levels ──────────────────────────
    drawVignette(ctx, w, h, 0.6);

    // ── 11. Target mask ─────────────────────────────────────────────────
    if (state.showTargetMask) {
      ctx.save();
      ctx.strokeStyle = 'rgba(255, 80, 80, 0.6)';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.arc(this.peakX, this.peakY - 10, radius + 20, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }
  }

  private updateMeteor(dt: number, attention: number, w: number, h: number): void {
    if (this.meteor.active) {
      this.meteor.life -= dt;
      this.meteor.x += this.meteor.dx * dt;
      this.meteor.y += this.meteor.dy * dt;

      if (this.meteor.life <= 0) {
        this.meteor.active = false;
        this.meteorCooldown =
          attention < 0.3
            ? 2 + Math.random() * 1
            : 3 + Math.random() * 3;
      }
    } else {
      this.meteorCooldown -= dt;
      if (this.meteorCooldown <= 0) {
        this.spawnMeteor(w, h);
      }
    }
  }

  private spawnMeteor(w: number, h: number): void {
    const peakZoneX = w * 0.5;
    const peakZoneY = h * 0.35;

    let startX: number;
    let startY: number;
    let attempts = 0;
    do {
      startX = w * 0.2 + Math.random() * w * 0.7;
      startY = h * 0.05 + Math.random() * h * 0.25;
      attempts++;
    } while (
      attempts < 10 &&
      Math.abs(startX - peakZoneX) < w * 0.12 &&
      Math.abs(startY - peakZoneY) < h * 0.08
    );

    const maxLife = 0.3 + Math.random() * 0.2;
    const speed = 200 + Math.random() * 150;
    const angle = Math.PI * 0.65 + (Math.random() - 0.5) * 0.3;

    this.meteor = {
      active: true,
      x: startX,
      y: startY,
      dx: Math.cos(angle) * speed,
      dy: Math.sin(angle) * speed,
      life: maxLife,
      maxLife,
      length: 80 + Math.random() * 40,
    };
  }

  private drawMeteor(ctx: CanvasRenderingContext2D, m: MeteorState): void {
    const progress = 1 - m.life / m.maxLife;

    let alpha: number;
    if (progress < 0.15) {
      alpha = progress / 0.15;
    } else {
      alpha = 1 - (progress - 0.15) / 0.85;
    }
    alpha = Math.max(0, Math.min(1, alpha)) * 0.8;

    if (alpha < 0.01) return;

    const speed = Math.sqrt(m.dx * m.dx + m.dy * m.dy);
    const ndx = speed > 0 ? m.dx / speed : -0.7;
    const ndy = speed > 0 ? m.dy / speed : 0.7;

    const tailX = m.x - ndx * m.length;
    const tailY = m.y - ndy * m.length;

    ctx.save();
    ctx.globalCompositeOperation = 'lighter';

    const grad = ctx.createLinearGradient(tailX, tailY, m.x, m.y);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(0.7, rgba(TARGET_WARM_GOLD, alpha * 0.3));
    grad.addColorStop(1, `rgba(255,255,240,${alpha})`);

    ctx.strokeStyle = grad;
    ctx.lineWidth = 1.5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(tailX, tailY);
    ctx.lineTo(m.x, m.y);
    ctx.stroke();

    ctx.globalAlpha = alpha;
    ctx.fillStyle = '#fffef0';
    ctx.beginPath();
    ctx.arc(m.x, m.y, 1.5, 0, Math.PI * 2);
    ctx.fill();

    const headGrad = ctx.createRadialGradient(m.x, m.y, 0, m.x, m.y, 6);
    headGrad.addColorStop(0, `rgba(255,253,230,${alpha * 0.6})`);
    headGrad.addColorStop(1, 'rgba(255,253,230,0)');
    ctx.fillStyle = headGrad;
    ctx.beginPath();
    ctx.arc(m.x, m.y, 6, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }
}
