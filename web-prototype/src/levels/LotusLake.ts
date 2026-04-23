import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import {
  drawGlow,
  drawStarField,
  drawWaterReflection,
  drawPetal,
  drawNoiseFog,
  drawVignette,
  drawMoon,
  drawMountainSilhouette,
} from '../utils/drawing';
import { TARGET_WARM_GOLD, LEVEL_THEMES, rgba } from '../utils/color';
import { noise2D } from '../utils/noise';

function seededRandom(seed: number): () => number {
  let s = seed | 0;
  if (s === 0) s = 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

interface PetalDef {
  angle: number;
  lengthRatio: number;
  widthRatio: number;
  phase: number;
}

interface Ripple {
  radiusRatio: number;
  speed: number;
  maxRadius: number;
}

interface ParticleDef {
  xOffset: number;
  yOffset: number;
  speed: number;
  life: number;
  maxLife: number;
  size: number;
}

export class LotusLake extends LevelRenderer {
  name = '涟漪绽放';
  subtitle = '花苞微启，水面平静';

  private petals: PetalDef[] = [];
  private ripples: Ripple[] = [];
  private particles: ParticleDef[] = [];
  private static readonly PETAL_SEED = 88;
  private static readonly RIPPLE_SEED = 256;

  enter(): void {
    super.enter();

    const rng = seededRandom(LotusLake.PETAL_SEED);
    const petalCount = 14 + Math.floor(rng() * 5);
    this.petals = [];
    for (let i = 0; i < petalCount; i++) {
      this.petals.push({
        angle: (Math.PI * 2 * i) / petalCount + (rng() - 0.5) * 0.12,
        lengthRatio: 0.75 + rng() * 0.25,
        widthRatio: 0.7 + rng() * 0.3,
        phase: rng() * Math.PI * 2,
      });
    }

    const ripRng = seededRandom(LotusLake.RIPPLE_SEED);
    this.ripples = [];
    for (let i = 0; i < 4; i++) {
      this.ripples.push({
        radiusRatio: i * 0.08,
        speed: 0.3 + ripRng() * 0.2,
        maxRadius: 0.25 + ripRng() * 0.15,
      });
    }

    // Initialize particles
    this.particles = [];
    for (let i = 0; i < 15; i++) {
      this.particles.push({
        xOffset: (Math.random() - 0.5) * 60,
        yOffset: (Math.random() - 0.5) * 20,
        speed: 10 + Math.random() * 15,
        life: Math.random() * 2,
        maxLife: 2 + Math.random() * 2,
        size: 1 + Math.random() * 2,
      });
    }
  }

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width: w, height: h } = rc;
    const t = this.levelTime;
    const att = state.attention;

    if (att > 0.7) {
      this.subtitle = '花蕊绽放，湖面涟漪轻柔';
    } else if (att > 0.3) {
      this.subtitle = '花苞微启，水面平静';
    } else {
      this.subtitle = '花苞合拢，夜色渐浓';
    }

    const horizonY = h * 0.45;
    const lotusX = w * 0.5;
    const lotusY = horizonY + h * 0.08;

    // ── 1. Background gradient ──────────────────────────────────────────
    ctx.save();
    const bg = ctx.createLinearGradient(0, 0, 0, h);
    bg.addColorStop(0, '#080c16');
    bg.addColorStop(0.4, '#0a0e1a');
    bg.addColorStop(0.5, '#0c1220');
    bg.addColorStop(1, '#060a14');
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();

    // ── 2. Stars ────────────────────────────────────────────────────────
    drawStarField(ctx, w, h, state.particleDensity * 0.4, 17);

    // ── 3. Moon ─────────────────────────────────────────────────────────
    const moonX = w * 0.78;
    const moonY = h * 0.15;
    const moonBright = 0.7 + att * 0.3;
    drawMoon(ctx, moonX, moonY, 18, 0.3, TARGET_WARM_GOLD, moonBright * 0.9);

    // ── 4. Mountains ────────────────────────────────────────────────────
    drawMountainSilhouette(ctx, w, horizonY, h * 0.12, '#080810');

    // ── 5. Water ────────────────────────────────────────────────────────
    drawWaterReflection(ctx, horizonY, w, h - horizonY, t, att * 0.8);

    // Moon reflection in water
    ctx.save();
    const refGrad = ctx.createLinearGradient(moonX, horizonY, moonX, horizonY + h * 0.25);
    refGrad.addColorStop(0, rgba(TARGET_WARM_GOLD, 0.06 * att));
    refGrad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = refGrad;
    ctx.fillRect(moonX - 20, horizonY, 40, h * 0.25);
    ctx.restore();

    // ── 6. Lotus petals ─────────────────────────────────────────────────
    const openness = 0.15 + att * 0.75;
    const petalBaseLength = Math.min(w, h) * 0.06;
    const petalBaseWidth = petalBaseLength * 0.35;

    for (const petal of this.petals) {
      const len = petalBaseLength * petal.lengthRatio;
      const wid = petalBaseWidth * petal.widthRatio;
      const petalOpen = openness * (0.85 + 0.15 * Math.sin(t * 0.4 + petal.phase));
      const petalAlpha = 0.55 + att * 0.25;

      drawPetal(ctx, lotusX, lotusY, petal.angle, len, wid, petalOpen, '#ffb6c1', petalAlpha);
    }

    // ── 7. Stamen (SSVEP target) ────────────────────────────────────────
    const stamenOpacity = this.ssvep(t, state.targetFrequency, 0.55, 1.0);
    const stamenRadius = Math.min(w, h) * 0.012;

    // Outer glow
    drawGlow(ctx, lotusX, lotusY, stamenRadius * 4, TARGET_WARM_GOLD, stamenOpacity * 0.3 * openness, state.bloomStrength);

    // Inner stamen dots
    const stamenCount = 5;
    for (let i = 0; i < stamenCount; i++) {
      const a = (Math.PI * 2 * i) / stamenCount + t * 0.1;
      const r = stamenRadius * 0.5 * openness;
      const sx = lotusX + Math.cos(a) * r;
      const sy = lotusY + Math.sin(a) * r * 0.6;
      drawGlow(ctx, sx, sy, stamenRadius * 0.8, TARGET_WARM_GOLD, stamenOpacity * openness, 1);
    }

    // Center point
    drawGlow(ctx, lotusX, lotusY, stamenRadius * 1.5, TARGET_WARM_GOLD, stamenOpacity * openness * 0.8, 1);

    // Particles (pollen)
    const dt = 1 / 60;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    ctx.fillStyle = rgba(TARGET_WARM_GOLD, 0.6 * att);
    for (const p of this.particles) {
      p.life += dt;
      if (p.life > p.maxLife) {
        p.life = 0;
        p.xOffset = (Math.random() - 0.5) * 60 * openness;
        p.yOffset = 0;
      }
      p.yOffset -= p.speed * dt;
      p.xOffset += Math.sin(t * 2 + p.life) * 0.2;
      
      const pAlpha = Math.sin((p.life / p.maxLife) * Math.PI) * stamenOpacity * att;
      ctx.globalAlpha = Math.max(0, pAlpha);
      
      ctx.beginPath();
      ctx.arc(lotusX + p.xOffset, lotusY + p.yOffset, p.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    // ── 8. Ripples ──────────────────────────────────────────────────────
    const rippleAlpha = 0.04 + att * 0.06;
    ctx.save();
    ctx.strokeStyle = rgba('#8ab4f8', rippleAlpha);
    ctx.lineWidth = 0.8;
    for (const rip of this.ripples) {
      const progress = ((t * rip.speed + rip.radiusRatio) % rip.maxRadius);
      const ripRadius = progress * Math.min(w, h) * 0.5;
      const ripAlpha = rippleAlpha * (1 - progress / rip.maxRadius);
      if (ripAlpha < 0.005) continue;
      ctx.globalAlpha = ripAlpha;
      ctx.beginPath();
      ctx.ellipse(lotusX, lotusY + h * 0.02, ripRadius, ripRadius * 0.4, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.restore();

    // ── 9. Fog ──────────────────────────────────────────────────────────
    const fogOpacity = 0.02 + (1 - att) * 0.04;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, h * 0.65, w, h * 0.35);
    ctx.clip();
    drawNoiseFog(ctx, w, h, t * 0.1, fogOpacity, '#0a1020');
    ctx.restore();

    // ── 10. Vignette ────────────────────────────────────────────────────
    drawVignette(ctx, w, h, 0.4);

    // ── 11. Target mask ─────────────────────────────────────────────────
    if (state.showTargetMask) {
      ctx.save();
      ctx.strokeStyle = '#ff0000';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.arc(lotusX, lotusY, petalBaseLength * 1.2, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }
  }
}
