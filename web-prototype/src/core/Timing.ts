export function ssvepOpacity(time: number, frequency: number, min = 0.60, max = 1.0): number {
  const phase = Math.sin(time * Math.PI * 2 * frequency) * 0.5 + 0.5;
  return min + (max - min) * phase;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}

export function smoothStep(edge0: number, edge1: number, x: number): number {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

export function safeDt(rawDt: number): number {
  return Math.min(rawDt, 0.033);
}
