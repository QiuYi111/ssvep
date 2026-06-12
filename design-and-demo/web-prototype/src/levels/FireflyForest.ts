import { LevelRenderer } from './LevelRenderer';
import type { AppState, RenderContext } from '../core/types';
import {
  drawFirefly,
  drawNoiseFog,
  drawStarField,
  drawTreeSilhouette,
  drawVignette,
  drawGlow,
  drawMountainSilhouette,
} from '../utils/drawing';
import { TARGET_BIO_GREEN, rgba } from '../utils/color';
import { noise2D } from '../utils/noise';

function seededRandom(seed: number): () => number {
  let s = seed | 0;
  if (s === 0) s = 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

interface TreeDef {
  xRatio: number;
  heightRatio: number;
  trunkWidth: number;
  canopyRadius: number;
  depth: number; // 0 = foreground (dark), 1 = background (foggy)
}

interface TargetFireflyDef {
  angleOffset: number;
  radiusRatio: number;
  speed: number;
  size: number;
  noiseOffsetX: number;
  noiseOffsetY: number;
}

interface AmbientFireflyDef {
  xRatio: number;
  yRatio: number;
  driftSpeed: number;
  driftAngle: number;
}

export class FireflyForest extends LevelRenderer {
  readonly name = '萤火引路';
  readonly subtitle = '萤火轻舞，雾气弥漫';

  private trees: TreeDef[] = [];
  private targetFireflies: TargetFireflyDef[] = [];
  private ambientFireflies: AmbientFireflyDef[] = [];

  private static readonly TREE_SEED = 71;
  private static readonly FIREFLY_SEED = 1337;
  private static readonly AMBIENT_SEED = 2048;

  enter(): void {
    super.enter();

    const treeRng = seededRandom(FireflyForest.TREE_SEED);
    this.trees = [];
    
    // Background layer (depth ~ 0.8)
    for (let i = 0; i < 8; i++) {
      this.trees.push({
        xRatio: treeRng() * 1.2 - 0.1,
        heightRatio: 0.35 + treeRng() * 0.15,
        trunkWidth: 6 + treeRng() * 3,
        canopyRadius: 15 + treeRng() * 10,
        depth: 0.8,
      });
    }

    // Midground layer (depth ~ 0.4)
    for (let i = 0; i < 6; i++) {
      this.trees.push({
        xRatio: treeRng() * 1.2 - 0.1,
        heightRatio: 0.45 + treeRng() * 0.20,
        trunkWidth: 10 + treeRng() * 5,
        canopyRadius: 25 + treeRng() * 15,
        depth: 0.4,
      });
    }

    // Foreground layer (depth ~ 0.0)
    for (let i = 0; i < 4; i++) {
      this.trees.push({
        xRatio: treeRng() * 1.2 - 0.1,
        heightRatio: 0.60 + treeRng() * 0.25,
        trunkWidth: 16 + treeRng() * 8,
        canopyRadius: 40 + treeRng() * 20,
        depth: 0.0,
      });
    }
    
    // Sort by depth (draw background first)
    this.trees.sort((a, b) => b.depth - a.depth);

    const ffRng = seededRandom(FireflyForest.FIREFLY_SEED);
    const ffCount = 8 + Math.floor(ffRng() * 8);
    this.targetFireflies = [];
    for (let i = 0; i < ffCount; i++) {
      this.targetFireflies.push({
        angleOffset: (Math.PI * 2 * i) / ffCount + (ffRng() - 0.5) * 0.6,
        radiusRatio: 0.6 + ffRng() * 0.8,
        speed: 0.15 + ffRng() * 0.20,
        size: 3 + ffRng() * 3,
        noiseOffsetX: ffRng() * 100,
        noiseOffsetY: ffRng() * 100,
      });
    }

    const ambRng = seededRandom(FireflyForest.AMBIENT_SEED);
    const ambCount = 5 + Math.floor(ambRng() * 6);
    this.ambientFireflies = [];
    for (let i = 0; i < ambCount; i++) {
      let xRatio = ambRng();
      const yRatio = 0.2 + ambRng() * 0.6;
      if (Math.abs(xRatio - 0.5) < 0.15 && Math.abs(yRatio - 0.45) < 0.15) {
        xRatio = xRatio < 0.5 ? xRatio * 0.5 : 0.5 + xRatio * 0.5;
      }
      this.ambientFireflies.push({
        xRatio,
        yRatio,
        driftSpeed: 0.05 + ambRng() * 0.10,
        driftAngle: ambRng() * Math.PI * 2,
      });
    }
  }

  draw(rc: RenderContext, state: AppState): void {
    const { ctx, width: w, height: h } = rc;
    const t = this.levelTime;
    const attn = state.attention;

    if (attn > 0.7) {
      (this as { subtitle: string }).subtitle = '萤火汇聚，石碑微光';
    } else if (attn > 0.3) {
      (this as { subtitle: string }).subtitle = '萤火轻舞，雾气弥漫';
    } else {
      (this as { subtitle: string }).subtitle = '萤火散去，夜色深沉';
    }

    // ── 1. Background ──
    ctx.save();
    const bgGrad = ctx.createLinearGradient(0, 0, 0, h);
    bgGrad.addColorStop(0, '#0a1a0a');
    bgGrad.addColorStop(0.6, '#081408');
    bgGrad.addColorStop(1, '#050f05');
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, w, h);
    ctx.restore();

    // ── 2. Stars ──
    drawStarField(ctx, w, h, state.particleDensity * 0.15, 42);

    // ── 3. Mountain silhouette ──
    drawMountainSilhouette(ctx, w, h * 0.85, h * 0.08, '#0c180c');

    // ── 4. Trees (Parallax) ──
    const baseY = h * 0.95;
    for (const tree of this.trees) {
      // Color fades to dark green fog based on depth
      const shade = Math.floor(5 + tree.depth * 20); // 5 to 25
      const green = Math.floor(5 + tree.depth * 40); // 5 to 45
      const color = `rgb(${shade},${green},${shade})`;
      
      // Slight parallax movement
      const parallaxX = (tree.xRatio * w) + (w * 0.5 - (tree.xRatio * w)) * tree.depth * 0.1;
      
      drawTreeSilhouette(ctx, parallaxX, baseY + tree.depth * 50, tree.heightRatio * h, tree.trunkWidth, tree.canopyRadius, color);
    }

    // ── 5. Background fog ──
    const fogBaseOpacity = 0.03 + (1 - attn) * 0.03;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, h * 0.3, w, h * 0.3);
    ctx.clip();
    drawNoiseFog(ctx, w, h, t * 0.3, fogBaseOpacity, '#1b3a1b');
    ctx.restore();

    // ── 6. Stone monument ──
    const monX = w * 0.5;
    const monBaseY = h * 0.55;
    const monW = Math.max(4, w * 0.025);
    const monH = Math.max(8, h * 0.07);

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(monX - monW * 0.5, monBaseY);
    ctx.lineTo(monX - monW * 0.35, monBaseY - monH);
    ctx.lineTo(monX + monW * 0.35, monBaseY - monH);
    ctx.lineTo(monX + monW * 0.5, monBaseY);
    ctx.closePath();

    const monGrad = ctx.createLinearGradient(monX, monBaseY, monX, monBaseY - monH);
    monGrad.addColorStop(0, '#2a2a2a');
    monGrad.addColorStop(0.7, '#333333');
    monGrad.addColorStop(1, '#3a3a3a');
    ctx.fillStyle = monGrad;
    ctx.fill();

    ctx.beginPath();
    ctx.moveTo(monX - monW * 0.35, monBaseY - monH);
    ctx.lineTo(monX + monW * 0.35, monBaseY - monH);
    ctx.strokeStyle = 'rgba(255,255,255,0.08)';
    ctx.lineWidth = 1;
    ctx.stroke();
    ctx.restore();

    // ── 6b. Monument glow at high attention ──
    if (attn > 0.5) {
      drawGlow(ctx, monX, monBaseY - monH * 0.5, monH * 0.8, TARGET_BIO_GREEN, (attn - 0.5) * 2 * 0.15, 1);
    }

    // ── 7. Target firefly cluster ──
    const clusterBaseRadius = w * 0.04;
    const attnRadiusMult = 1.0 - attn * 0.4;
    const ssvepOpacity = this.ssvep(t, state.targetFrequency, 0.50, 1.0);

    for (const ff of this.targetFireflies) {
      const orbitRadius = clusterBaseRadius * ff.radiusRatio * attnRadiusMult;
      const angle = ff.angleOffset + t * ff.speed;
      const noiseX = (noise2D(ff.noiseOffsetX + t * 0.2, 0) - 0.5) * clusterBaseRadius * 0.3;
      const noiseY = (noise2D(0, ff.noiseOffsetY + t * 0.2) - 0.5) * clusterBaseRadius * 0.3;

      const fx = monX + Math.cos(angle) * orbitRadius + noiseX;
      const fy = (monBaseY - monH * 0.4) + Math.sin(angle) * orbitRadius * 0.7 + noiseY;

      drawFirefly(ctx, fx, fy, ff.size, TARGET_BIO_GREEN, ssvepOpacity, state.bloomStrength);
    }

    // ── 8. Ambient fireflies ──
    for (const af of this.ambientFireflies) {
      const driftX = Math.cos(af.driftAngle + t * af.driftSpeed) * 15;
      const driftY = Math.sin(af.driftAngle * 1.3 + t * af.driftSpeed * 0.7) * 10;
      const ax = af.xRatio * w + driftX;
      const ay = af.yRatio * h + driftY;
      const ambientAlpha = 0.10 + noise2D(af.xRatio * 10 + t * 0.1, af.yRatio * 10) * 0.10;

      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = rgba(TARGET_BIO_GREEN, ambientAlpha);
      ctx.beginPath();
      ctx.arc(ax, ay, 1.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    // ── 9. Foreground fog ──
    const fgFogOpacity = 0.04 + (1 - attn) * 0.04;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, h * 0.6, w, h * 0.4);
    ctx.clip();
    drawNoiseFog(ctx, w, h, t * 0.15 + 50, fgFogOpacity, '#0d1f0d');
    ctx.restore();

    // ── 10. Vignette ──
    drawVignette(ctx, w, h, 0.5);

    // ── 11. Target mask ──
    if (state.showTargetMask) {
      ctx.save();
      ctx.strokeStyle = '#ff0000';
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.arc(monX, monBaseY - monH * 0.3, w * 0.08, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
    }
  }
}
