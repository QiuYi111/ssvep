import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import { drawGlow, drawLightning, drawVignette } from '../utils/drawing';
import {
  TARGET_WARM_GOLD,
  DISTRACTOR_COLD_BLUE,
  DISTRACTOR_DEEP_VIOLET,
  hexToRgb,
} from '../utils/color';
import { noise2D } from '../utils/noise';

// ── Deterministic seeded PRNG ────────────────────────────────────────────────

function seededRandom(seed: number): () => number {
  let s = seed | 0;
  if (s === 0) s = 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

// ── Cloud definition ─────────────────────────────────────────────────────────

interface CloudDef {
  /** Horizontal position ratio (wraps around) */
  x: number;
  /** Vertical position ratio */
  y: number;
  /** Width in pixels */
  w: number;
  /** Height in pixels */
  h: number;
  /** Parallax speed multiplier */
  speed: number;
  /** Alpha multiplier */
  alpha: number;
  /** Noise seed offset for edge distortion */
  noiseSeed: number;
}

// ── Rain drop ────────────────────────────────────────────────────────────────

interface RainDrop {
  x: number;
  y: number;
  speed: number;
  length: number;
}

// ── Lightning state ──────────────────────────────────────────────────────────

interface LightningBolt {
  active: boolean;
  /** Start x (ratio 0..1) */
  x1: number;
  /** Start y (ratio 0..1) */
  y1: number;
  /** End x (ratio 0..1) */
  x2: number;
  /** End y (ratio 0..1) */
  y2: number;
  /** Remaining display time in seconds */
  timer: number;
  /** Max display duration */
  duration: number;
  /** Color */
  color: string;
}

// ── Level 5 — 飞燕破云 (Storm Swallow) ──────────────────────────────────────

export class StormSwallow extends LevelRenderer {
  readonly name = '飞燕破云';
  readonly subtitle = '风暴渐起，追踪灵燕';

  // Pre-generated cloud positions
  private clouds: CloudDef[] = [];

  // Pre-generated rain drops (pool, recycled)
  private rainPool: RainDrop[] = [];

  // Lightning state
  private lightningBolts: LightningBolt[] = [];
  private lightningCooldown = 0;

  // RNG
  private static readonly CLOUD_SEED = 5555;
  private static readonly RAIN_SEED = 9876;
  private static readonly LIGHTNING_COLORS = [DISTRACTOR_COLD_BLUE, DISTRACTOR_DEEP_VIOLET];

  enter(): void {
    super.enter();

    // ── Generate cloud layers (3 layers, 4-6 clouds each) ──
    const rng = seededRandom(StormSwallow.CLOUD_SEED);
    this.clouds = [];

    // Layer 0 — far, slow, wide
    const farCount = 4 + Math.floor(rng() * 3);
    for (let i = 0; i < farCount; i++) {
      this.clouds.push({
        x: rng() * 1.4 - 0.2,
        y: 0.10 + rng() * 0.35,
        w: 200 + rng() * 250,
        h: 60 + rng() * 60,
        speed: 0.008 + rng() * 0.006,
        alpha: 0.12 + rng() * 0.08,
        noiseSeed: rng() * 1000,
      });
    }

    // Layer 1 — mid
    const midCount = 4 + Math.floor(rng() * 3);
    for (let i = 0; i < midCount; i++) {
      this.clouds.push({
        x: rng() * 1.4 - 0.2,
        y: 0.20 + rng() * 0.40,
        w: 160 + rng() * 200,
        h: 50 + rng() * 50,
        speed: 0.014 + rng() * 0.010,
        alpha: 0.15 + rng() * 0.10,
        noiseSeed: rng() * 1000,
      });
    }

    // Layer 2 — near, fast
    const nearCount = 3 + Math.floor(rng() * 3);
    for (let i = 0; i < nearCount; i++) {
      this.clouds.push({
        x: rng() * 1.4 - 0.2,
        y: 0.30 + rng() * 0.45,
        w: 120 + rng() * 180,
        h: 40 + rng() * 40,
        speed: 0.022 + rng() * 0.014,
        alpha: 0.18 + rng() * 0.12,
        noiseSeed: rng() * 1000,
      });
    }

    // ── Pre-generate rain pool (will be recycled each frame) ──
    const rainRng = seededRandom(StormSwallow.RAIN_SEED);
    this.rainPool = [];
    for (let i = 0; i < 300; i++) {
      this.rainPool.push({
        x: rainRng(),
        y: rainRng(),
        speed: 0.6 + rainRng() * 0.8,
        length: 8 + rainRng() * 18,
      });
    }

    // ── Reset lightning ──
    this.lightningBolts = [];
    this.lightningCooldown = 1.5 + rng() * 2;
  }

  // ── Main draw ──────────────────────────────────────────────────────────────

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width: w, height: h } = rc;
    const t = this.levelTime;
    const attn = state.attention;
    const dt = 1 / 60; // approximate frame dt for updates

    // ── Dynamic subtitle ──
    this.updateSubtitle(attn);

    // ── Camera shake (low attention) ──
    const shakeAmount = (1 - attn) * 3;
    const shakeX = (noise2D(t * 5.7, 0) - 0.5) * shakeAmount;
    const shakeY = (noise2D(0, t * 5.7) - 0.5) * shakeAmount;

    ctx.save();
    ctx.translate(shakeX, shakeY);

    // 1 ── Background gradient ──────────────────────────────────────────────
    this.drawBackground(ctx, w, h, t);

    // 2 ── Cloud layers (parallax) ──────────────────────────────────────────
    this.drawClouds(ctx, w, h, t, attn);

    // 3 ── Rain ─────────────────────────────────────────────────────────────
    this.drawRain(ctx, w, h, t, attn);

    // 4 ── Lightning (distractor) ───────────────────────────────────────────
    this.updateLightning(dt, w, h, attn);
    this.drawLightningBolts(ctx, w, h, state);

    // 5 ── Spirit swallow (target) ──────────────────────────────────────────
    const swallowPos = this.getSwallowPosition(w, h, t);
    const wingAngle = state.reduceMotion ? 0 : Math.sin(t * 4) * 0.35;
    const chestOpacity = this.ssvep(t, state.targetFrequency, 0.55, 1.0);

    this.drawSwallow(ctx, swallowPos.x, swallowPos.y, wingAngle, chestOpacity);

    // 6 ── Vignette ─────────────────────────────────────────────────────────
    drawVignette(ctx, w, h, 0.5);

    ctx.restore();

    // 7 ── Target mask (outside transform, follows swallow position) ────────
    if (state.showTargetMask) {
      const maskPos = this.getSwallowPosition(w, h, t);
      const maskRadius = w * 0.06;
      ctx.save();
      ctx.strokeStyle = 'rgba(255, 80, 80, 0.6)';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.arc(maskPos.x + shakeX, maskPos.y + shakeY, maskRadius, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  private updateSubtitle(attention: number): void {
    if (attention > 0.7) {
      (this as { subtitle: string }).subtitle = '灵燕穿云，目光追随';
    } else if (attention > 0.3) {
      (this as { subtitle: string }).subtitle = '风暴渐起，追踪灵燕';
    } else {
      (this as { subtitle: string }).subtitle = '雷光闪烁，飞燕隐没';
    }
  }

  // ── 1. Background ──────────────────────────────────────────────────────────

  private drawBackground(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    t: number,
  ): void {
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    // Slightly turbulent: shift gradient stops with noise
    const turbulence = noise2D(t * 0.1, 0) * 0.05;
    grad.addColorStop(0, '#0d1f30');
    grad.addColorStop(0.4 + turbulence, '#0a1a2a');
    grad.addColorStop(0.7 + turbulence * 0.5, '#081520');
    grad.addColorStop(1, '#060e18');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);
  }

  // ── 2. Cloud layers ────────────────────────────────────────────────────────

  private drawClouds(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    t: number,
    attn: number,
  ): void {
    // Cloud alpha multiplier: high attn → less cloud cover
    const alphaMult = 0.5 + (1 - attn) * 0.5; // 0.5 at high attn, 1.0 at low

    for (const cloud of this.clouds) {
      // Move cloud left to right, wrapping
      const cx = ((cloud.x + t * cloud.speed) % 1.6) - 0.2;
      const px = cx * w;
      const py = cloud.y * h;

      const baseAlpha = cloud.alpha * alphaMult;
      this.drawSingleCloud(ctx, px, py, cloud.w, cloud.h, baseAlpha, cloud.noiseSeed, t);
    }
  }

  private drawSingleCloud(
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    cw: number,
    ch: number,
    alpha: number,
    seed: number,
    t: number,
  ): void {
    if (alpha < 0.01) return;

    ctx.save();
    ctx.globalAlpha = alpha;

    // Draw cloud as overlapping ellipses with noise-based edge distortion
    const blobCount = 5;
    for (let i = 0; i < blobCount; i++) {
      const blobAngle = (Math.PI * 2 * i) / blobCount;
      const distX = Math.cos(blobAngle) * cw * 0.25;
      const distY = Math.sin(blobAngle) * ch * 0.2;

      // Noise-based edge wobble
      const n = noise2D(seed + i * 7.3 + t * 0.15, t * 0.08 + i * 3.1);
      const wobbleX = (n - 0.5) * cw * 0.15;
      const wobbleY = (n - 0.5) * ch * 0.15;

      const bx = cx + distX + wobbleX;
      const by = cy + distY + wobbleY;
      const bw = cw * (0.5 + n * 0.3);
      const bh = ch * (0.5 + (1 - n) * 0.3);

      // Cloud color: dark grey
      const shade = 26 + Math.floor(n * 20); // #1a to #2e
      ctx.fillStyle = `rgb(${shade},${shade},${shade + 16})`;

      ctx.beginPath();
      ctx.ellipse(bx, by, Math.max(1, bw * 0.5), Math.max(1, bh * 0.5), 0, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.restore();
  }

  // ── 3. Rain ────────────────────────────────────────────────────────────────

  private drawRain(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    t: number,
    attn: number,
  ): void {
    // Density based on (1 - attention): more rain when less focused
    const density = (1 - attn) * 0.8 + 0.1; // 0.1 to 0.9
    const activeCount = Math.floor(this.rainPool.length * density);
    if (activeCount === 0) return;

    const [r, g, b] = hexToRgb('#3a5a8a');

    ctx.save();
    ctx.strokeStyle = `rgba(${r},${g},${b},0.15)`;
    ctx.lineWidth = 1;

    const windAngle = 0.15; // slight diagonal

    for (let i = 0; i < activeCount; i++) {
      const drop = this.rainPool[i];

      // Animate position (wrap vertically)
      const animY = ((drop.y + t * drop.speed * 0.5) % 1.1) - 0.05;
      const dx = Math.cos(windAngle) * drop.length;
      const dy = Math.sin(windAngle) * drop.length;

      const px = drop.x * w;
      const py = animY * h;

      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(px + dx, py + dy);
      ctx.stroke();
    }

    ctx.restore();
  }

  // ── 4. Lightning (distractor) ──────────────────────────────────────────────

  private updateLightning(
    dt: number,
    _w: number,
    _h: number,
    attn: number,
  ): void {
    // Update existing bolts
    for (const bolt of this.lightningBolts) {
      if (bolt.active) {
        bolt.timer -= dt;
        if (bolt.timer <= 0) {
          bolt.active = false;
        }
      }
    }

    // Cooldown for new bolt
    this.lightningCooldown -= dt;

    // More lightning at low attention
    const triggerChance = (1 - attn) * 0.6 + 0.15; // 0.15 to 0.75

    if (this.lightningCooldown <= 0 && Math.random() < triggerChance) {
      // Spawn a new bolt in peripheral area
      const side = Math.random(); // which edge region
      let x1: number, y1: number, x2: number, y2: number;

      if (side < 0.25) {
        // Left edge
        x1 = Math.random() * 0.15;
        y1 = Math.random() * 0.3;
        x2 = x1 + Math.random() * 0.08;
        y2 = y1 + 0.08 + Math.random() * 0.15;
      } else if (side < 0.5) {
        // Right edge
        x1 = 0.85 + Math.random() * 0.15;
        y1 = Math.random() * 0.3;
        x2 = x1 - Math.random() * 0.08;
        y2 = y1 + 0.08 + Math.random() * 0.15;
      } else if (side < 0.75) {
        // Top-left region
        x1 = Math.random() * 0.3;
        y1 = Math.random() * 0.15;
        x2 = x1 + 0.05 + Math.random() * 0.1;
        y2 = y1 + 0.1 + Math.random() * 0.1;
      } else {
        // Top-right region
        x1 = 0.7 + Math.random() * 0.3;
        y1 = Math.random() * 0.15;
        x2 = x1 - 0.05 - Math.random() * 0.1;
        y2 = y1 + 0.1 + Math.random() * 0.1;
      }

      const colorIdx = Math.random() < 0.6 ? 0 : 1;
      const duration = 0.1 + Math.random() * 0.2; // 0.1 to 0.3 seconds

      this.lightningBolts.push({
        active: true,
        x1, y1, x2, y2,
        timer: duration,
        duration,
        color: StormSwallow.LIGHTNING_COLORS[colorIdx],
      });

      // Reset cooldown: 2-5 seconds (shorter at low attn)
      const baseCooldown = 2 + Math.random() * 3;
      this.lightningCooldown = baseCooldown * (0.4 + attn * 0.6);
    }
  }

  private drawLightningBolts(
    ctx: CanvasRenderingContext2D,
    w: number,
    h: number,
    state: AppState,
  ): void {
    for (const bolt of this.lightningBolts) {
      if (!bolt.active) continue;

      // Fade out during the bolt's lifetime
      const lifeRatio = bolt.timer / bolt.duration;
      const fadeAlpha = Math.min(1, lifeRatio * 2); // quick fade-out

      // SSVEP modulation during active lightning
      const ssvepVal = this.ssvep(this.levelTime, state.distractorFrequency, 0.5, 1.0);
      const opacity = fadeAlpha * ssvepVal;

      const startX = bolt.x1 * w;
      const startY = bolt.y1 * h;
      const endX = bolt.x2 * w;
      const endY = bolt.y2 * h;

      drawLightning(ctx, startX, startY, endX, endY, 6, 15, opacity, bolt.color);
    }

    // Clean up expired bolts
    this.lightningBolts = this.lightningBolts.filter(b => b.active);
  }

  // ── 5. Swallow position ────────────────────────────────────────────────────

  private getSwallowPosition(w: number, h: number, t: number): { x: number; y: number } {
    // Figure-8 / sinusoidal path: Lissajous curve
    // Completes a full loop every ~10 seconds
    const x = w * 0.5 + Math.cos(t * 0.3) * w * 0.25;
    const y = h * 0.4 + Math.sin(t * 0.5) * h * 0.15;
    return { x, y };
  }

  private drawSwallow(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    wingAngle: number,
    chestOpacity: number,
  ): void {
    ctx.save();
    ctx.translate(x, y);

    const scale = 1.2;

    // ── Chest warm gold glow (SSVEP target) ──
    drawGlow(ctx, 3 * scale, 2 * scale, 18, TARGET_WARM_GOLD, chestOpacity * 0.8, 2);

    // ── Sleek Aerodynamic Body ──
    ctx.fillStyle = '#151525';
    ctx.beginPath();
    // Start at beak
    ctx.moveTo(14 * scale, 0);
    // Upper head and back
    ctx.bezierCurveTo(8 * scale, -4 * scale, -2 * scale, -3 * scale, -10 * scale, -1 * scale);
    // Upper tail fork
    ctx.bezierCurveTo(-15 * scale, -2 * scale, -20 * scale, -6 * scale, -20 * scale, -6 * scale);
    ctx.bezierCurveTo(-16 * scale, -1 * scale, -12 * scale, 1 * scale, -8 * scale, 1.5 * scale);
    // Lower tail fork
    ctx.bezierCurveTo(-14 * scale, 2 * scale, -20 * scale, 7 * scale, -20 * scale, 7 * scale);
    ctx.bezierCurveTo(-15 * scale, 3 * scale, -10 * scale, 3 * scale, -2 * scale, 4 * scale);
    // Belly and chest
    ctx.bezierCurveTo(6 * scale, 5 * scale, 12 * scale, 2 * scale, 14 * scale, 0);
    ctx.fill();

    // ── Eye ──
    ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
    ctx.beginPath();
    ctx.arc(9 * scale, -1 * scale, 1 * scale, 0, Math.PI * 2);
    ctx.fill();

    // ── Wings (Sleek curved paths) ──
    const drawWing = (isUpper: boolean) => {
      ctx.save();
      ctx.translate(-2 * scale, (isUpper ? -2 : 3) * scale);
      ctx.rotate(isUpper ? -wingAngle : wingAngle);
      
      ctx.fillStyle = '#151525';
      ctx.beginPath();
      ctx.moveTo(0, 0);
      const wLen = 22 * scale;
      const wWidth = 7 * scale;
      const dir = isUpper ? -1 : 1;
      
      ctx.bezierCurveTo(-wLen * 0.3, dir * wWidth, -wLen * 0.8, dir * wWidth * 1.2, -wLen, dir * wWidth * 0.2);
      ctx.bezierCurveTo(-wLen * 0.6, dir * wWidth * 0.3, -wLen * 0.2, 0, 4 * scale, dir * 1 * scale);
      ctx.fill();
      
      // Wing highlights
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
      ctx.lineWidth = 0.5;
      ctx.stroke();
      ctx.restore();
    };

    drawWing(true);  // Left/upper wing
    drawWing(false); // Right/lower wing

    // ── Chest Gold Overlay ──
    const [cr, cg, cb] = hexToRgb(TARGET_WARM_GOLD);
    ctx.globalAlpha = chestOpacity * 0.6;
    ctx.fillStyle = `rgb(${cr},${cg},${cb})`;
    ctx.beginPath();
    ctx.ellipse(4 * scale, 1.5 * scale, 4 * scale, 2.5 * scale, 0.2, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }
}
