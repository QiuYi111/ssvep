import { hexToRgb, rgba } from './color';
import { noise2D } from './noise';

function seededRandom(seed: number): () => number {
  let s = seed | 0;
  if (s === 0) s = 1;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

export function drawGlow(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
  color: string,
  opacity: number,
  bloomStrength: number = 2,
): void {
  const [r, g, b] = hexToRgb(color);
  const layers = Math.max(1, Math.min(5, Math.round(bloomStrength * 2)));

  ctx.save();
  ctx.globalCompositeOperation = 'screen';

  for (let i = 0; i < layers; i++) {
    const layerRadius = radius * Math.pow(1.6, i);
    const layerOpacity = opacity * Math.pow(0.5, i + 1);

    const grad = ctx.createRadialGradient(x, y, 0, x, y, layerRadius);
    grad.addColorStop(0, `rgba(${r},${g},${b},${layerOpacity})`);
    grad.addColorStop(0.3, `rgba(${r},${g},${b},${layerOpacity * 0.5})`);
    grad.addColorStop(1, `rgba(${r},${g},${b},0)`);

    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, layerRadius, 0, Math.PI * 2);
    ctx.fill();
  }

  // Intense center core
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = `rgba(255,255,255,${opacity * 0.3})`;
  ctx.beginPath();
  ctx.arc(x, y, radius * 0.3, 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();
}

export function drawSoftCircle(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
  color: string,
  opacity: number,
): void {
  ctx.save();
  ctx.globalAlpha = opacity;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

export function drawNoiseFog(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  time: number,
  opacity: number,
  color: string,
  noiseFn: (x: number, y: number) => number = noise2D,
): void {
  const cols = 24;
  const rows = 18;
  const cellW = width / cols;
  const cellH = height / rows;
  const [r, g, b] = hexToRgb(color);

  ctx.save();
  ctx.globalCompositeOperation = 'lighter';

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const nx = col * 0.08 + time * 0.05;
      const ny = row * 0.08;
      const n = noiseFn(nx, ny);
      const cellOpacity = opacity * n;

      if (cellOpacity < 0.005) continue;

      ctx.fillStyle = `rgba(${r},${g},${b},${cellOpacity.toFixed(3)})`;
      ctx.fillRect(col * cellW, row * cellH, cellW + 1, cellH + 1);
    }
  }

  ctx.restore();
}

export function drawStarField(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  density: number,
  seed: number,
): void {
  const count = Math.floor(density * 300);
  if (count === 0) return;

  const rand = seededRandom(seed);

  ctx.save();

  for (let i = 0; i < count; i++) {
    const sx = rand() * width;
    const sy = rand() * height;
    const alpha = 0.2 + rand() * 0.6;
    const size = rand() < 0.01 ? 1.5 + rand() * 1.0 : 0.5 + rand() * 1.0;
    const blue = rand() > 0.85;

    ctx.globalAlpha = alpha;
    ctx.fillStyle = blue ? '#b0c4de' : '#ffffff';

    if (size < 1.2) {
      ctx.fillRect(sx, sy, size, size);
    } else {
      ctx.beginPath();
      ctx.arc(sx, sy, size, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  ctx.restore();
}

export function drawWaterReflection(
  ctx: CanvasRenderingContext2D,
  y: number,
  width: number,
  height: number,
  time: number,
  attention: number,
): void {
  const lineCount = 10 + Math.floor(attention * 10);
  const spacing = height / lineCount;
  const [r, g, b] = hexToRgb('#8ab4f8');

  ctx.save();
  ctx.strokeStyle = `rgba(${r},${g},${b},1)`;
  ctx.lineWidth = 0.5 + attention * 0.5;

  for (let i = 0; i < lineCount; i++) {
    const lineY = y + i * spacing;
    const lineAlpha = 0.05 + (1 - i / lineCount) * 0.1;
    ctx.globalAlpha = lineAlpha;
    ctx.beginPath();

    for (let x = 0; x <= width; x += 4) {
      const waveAmp = 2 + attention * 4;
      const waveFreq = 0.02 + attention * 0.01;
      const dy = Math.sin(x * waveFreq + time * 1.5 + i * 0.5) * waveAmp;

      if (x === 0) {
        ctx.moveTo(x, lineY + dy);
      } else {
        ctx.lineTo(x, lineY + dy);
      }
    }

    ctx.stroke();
  }

  ctx.restore();
}

export function drawPetal(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  angle: number,
  length: number,
  petalWidth: number,
  openness: number,
  color: string,
  opacity: number,
): void {
  const spread = openness * 0.7 + 0.15;

  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(angle);
  ctx.globalAlpha = opacity;

  const tipX = Math.cos(spread) * length;
  const tipY = Math.sin(spread) * length;
  const cpDist = length * 0.6;
  const halfW = petalWidth * 0.5;

  const grad = ctx.createLinearGradient(0, 0, tipX, tipY);
  grad.addColorStop(0, rgba(color, 0.9));
  grad.addColorStop(0.5, color);
  grad.addColorStop(1, rgba(color, 0.6));

  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.moveTo(0, 0);

  ctx.quadraticCurveTo(
    cpDist * 0.3, -halfW,
    tipX, tipY,
  );
  ctx.quadraticCurveTo(
    cpDist * 0.3, halfW,
    0, 0,
  );

  ctx.fill();

  ctx.globalAlpha = opacity * 0.4;
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 0.5;
  ctx.stroke();

  ctx.restore();
}

export function drawFirefly(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  size: number,
  color: string,
  opacity: number,
  bloomStrength: number = 1.5,
): void {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';

  const [r, g, b] = hexToRgb(color);

  const outerRadius = size * bloomStrength;
  const grad = ctx.createRadialGradient(x, y, 0, x, y, outerRadius);
  grad.addColorStop(0, `rgba(${r},${g},${b},${opacity})`);
  grad.addColorStop(0.2, `rgba(${r},${g},${b},${opacity * 0.5})`);
  grad.addColorStop(1, `rgba(${r},${g},${b},0)`);

  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.arc(x, y, outerRadius, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = `rgba(255,255,255,${opacity * 0.8})`;
  ctx.beginPath();
  ctx.arc(x, y, Math.max(0.5, size * 0.15), 0, Math.PI * 2);
  ctx.fill();

  ctx.restore();

  ctx.save();
  ctx.globalAlpha = opacity * 0.25;
  ctx.strokeStyle = color;
  ctx.lineWidth = 0.5;
  ctx.beginPath();
  ctx.moveTo(x - size * 0.3, y - size * 0.2);
  ctx.lineTo(x - size * 0.7, y - size * 0.5);
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(x + size * 0.3, y - size * 0.2);
  ctx.lineTo(x + size * 0.7, y - size * 0.5);
  ctx.stroke();
  ctx.restore();
}

export function drawLightning(
  ctx: CanvasRenderingContext2D,
  startX: number,
  startY: number,
  endX: number,
  endY: number,
  segments: number = 8,
  spread: number = 20,
  opacity: number = 0.8,
  color: string = '#8ab4f8',
): void {
  if (segments < 2) return;

  const dx = endX - startX;
  const dy = endY - startY;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len < 1) return;

  const nx = -dy / len;
  const ny = dx / len;

  const points: [number, number][] = [[startX, startY]];
  for (let i = 1; i < segments - 1; i++) {
    const t = i / (segments - 1);
    const baseX = startX + dx * t;
    const baseY = startY + dy * t;
    const offset = (Math.random() - 0.5) * 2 * spread;
    points.push([baseX + nx * offset, baseY + ny * offset]);
  }
  points.push([endX, endY]);

  ctx.save();
  ctx.globalCompositeOperation = 'lighter';

  ctx.globalAlpha = opacity * 0.3;
  ctx.strokeStyle = color;
  ctx.lineWidth = 4;
  ctx.shadowColor = color;
  ctx.shadowBlur = 15;
  ctx.beginPath();
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i++) {
    ctx.lineTo(points[i][0], points[i][1]);
  }
  ctx.stroke();

  ctx.shadowBlur = 0;
  ctx.globalAlpha = opacity;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i++) {
    ctx.lineTo(points[i][0], points[i][1]);
  }
  ctx.stroke();

  ctx.restore();
}

export function drawAurora(
  ctx: CanvasRenderingContext2D,
  width: number,
  y: number,
  height: number,
  time: number,
  opacity: number,
): void {
  const bandCount = 4;

  ctx.save();
  ctx.globalCompositeOperation = 'lighter';

  const colors: [string, string][] = [
    ['#4caf50', '#64b5f6'],
    ['#66bb6a', '#42a5f5'],
    ['#81c784', '#90caf9'],
    ['#a5d6a7', '#bbdefb'],
  ];

  for (let band = 0; band < bandCount; band++) {
    const bandY = y + (band / bandCount) * height;
    const bandH = height / bandCount;
    const phase = time * 0.3 + band * 1.2;
    const bandAlpha = opacity * (0.08 + 0.04 * Math.sin(time * 0.5 + band));

    const [c1, c2] = colors[band % colors.length];
    const [r1, g1, b1] = hexToRgb(c1);
    const [r2, g2, b2] = hexToRgb(c2);

    ctx.globalAlpha = bandAlpha;

    ctx.beginPath();
    ctx.moveTo(0, bandY + bandH);

    for (let x = 0; x <= width; x += 20) {
      const t = x / width;
      const wave = Math.sin(t * 4 + phase) * bandH * 0.3
                 + Math.sin(t * 7 + phase * 0.7) * bandH * 0.15;
      ctx.lineTo(x, bandY + wave);
    }

    ctx.lineTo(width, bandY + bandH);
    ctx.closePath();

    const grad = ctx.createLinearGradient(0, bandY, width, bandY);
    grad.addColorStop(0, `rgba(${r1},${g1},${b1},0.4)`);
    grad.addColorStop(0.3, `rgba(${r2},${g2},${b2},0.3)`);
    grad.addColorStop(0.7, `rgba(${r1},${g1},${b1},0.25)`);
    grad.addColorStop(1, `rgba(${r2},${g2},${b2},0.15)`);
    ctx.fillStyle = grad;

    ctx.fill();
  }

  ctx.restore();
}

export function drawVignette(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  strength: number,
): void {
  if (strength <= 0) return;

  const cx = width * 0.5;
  const cy = height * 0.5;
  const minDim = Math.min(width, height);
  const innerR = minDim * 0.4;
  const outerR = minDim * 0.7;

  const grad = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR);
  grad.addColorStop(0, 'rgba(0,0,0,0)');
  grad.addColorStop(1, `rgba(0,0,0,${Math.min(1, strength)})`);

  ctx.save();
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);
  ctx.restore();
}

export function drawMountainSilhouette(
  ctx: CanvasRenderingContext2D,
  width: number,
  baseY: number,
  peakHeight: number,
  color: string,
  fogColor: string = 'transparent',
): void {
  const rand = seededRandom(Math.round(width * 7 + peakHeight * 3));
  const peakCount = 5 + Math.floor(rand() * 4);

  ctx.save();
  
  const grad = ctx.createLinearGradient(0, baseY - peakHeight * 1.5, 0, baseY);
  grad.addColorStop(0, color);
  grad.addColorStop(1, fogColor === 'transparent' ? color : fogColor);

  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.moveTo(0, baseY);

  let currentX = 0;
  const segW = width / peakCount;

  for (let i = 0; i < peakCount; i++) {
    const peakX = currentX + segW * (0.3 + rand() * 0.4);
    const peakY = baseY - peakHeight * (0.4 + rand() * 0.6);
    const valleyX = currentX + segW;

    ctx.quadraticCurveTo(peakX, peakY, valleyX, baseY - rand() * peakHeight * 0.1);
    currentX = valleyX;
  }

  ctx.lineTo(width, baseY);
  ctx.lineTo(width, baseY + 10);
  ctx.lineTo(0, baseY + 10);
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

export function drawTreeSilhouette(
  ctx: CanvasRenderingContext2D,
  x: number,
  baseY: number,
  height: number,
  trunkWidth: number,
  canopyRadius: number,
  color: string,
): void {
  ctx.save();
  ctx.fillStyle = color;

  // Trunk
  ctx.fillRect(
    x - trunkWidth * 0.5,
    baseY - height * 0.3,
    trunkWidth,
    height * 0.3,
  );

  // Pine tree branches (4 tiers)
  const tiers = 4;
  for (let i = 0; i < tiers; i++) {
    const tierY = baseY - height * (0.15 + 0.85 * (i / tiers));
    const tierW = canopyRadius * (1 - (i / tiers) * 0.5);
    const tierH = height * 0.4;

    ctx.beginPath();
    ctx.moveTo(x, tierY - tierH * 0.8);
    // Left jagged edge
    ctx.lineTo(x - tierW * 0.8, tierY);
    ctx.lineTo(x - tierW * 0.5, tierY - tierH * 0.15);
    ctx.lineTo(x - tierW * 1.1, tierY + tierH * 0.25);
    // Bottom
    ctx.lineTo(x, tierY + tierH * 0.1);
    // Right jagged edge
    ctx.lineTo(x + tierW * 1.1, tierY + tierH * 0.25);
    ctx.lineTo(x + tierW * 0.5, tierY - tierH * 0.15);
    ctx.lineTo(x + tierW * 0.8, tierY);
    ctx.closePath();
    ctx.fill();
  }

  ctx.restore();
}

export function drawMoon(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  radius: number,
  phase: number,
  color: string = '#ffe9a6',
  opacity: number = 1,
): void {
  ctx.save();

  drawGlow(ctx, x, y, radius * 3, color, opacity * 0.2, 1);

  ctx.globalAlpha = opacity;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.fill();

  if (phase < 0.99) {
    const offset = radius * 2 * (1 - phase);
    ctx.fillStyle = '#0a0e1a';
    ctx.beginPath();
    ctx.arc(x + offset, y, radius * 0.95, 0, Math.PI * 2);
    ctx.fill();
  }

  if (phase > 0.4) {
    ctx.globalAlpha = opacity * 0.08;
    ctx.fillStyle = '#000000';

    const craters: [number, number, number][] = [
      [0.2, -0.15, 0.12],
      [-0.25, 0.2, 0.08],
      [0.05, 0.3, 0.06],
    ];

    for (const [cx, cy, cr] of craters) {
      ctx.beginPath();
      ctx.arc(x + cx * radius, y + cy * radius, cr * radius, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  ctx.restore();
}
