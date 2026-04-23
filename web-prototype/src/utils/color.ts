export const TARGET_WARM_GOLD = '#ffe9a6';
export const TARGET_BIO_GREEN = '#cddc39';
export const DISTRACTOR_COLD_BLUE = '#8ab4f8';
export const DISTRACTOR_DEEP_VIOLET = '#4a148c';

export const LEVEL_THEMES = [
  { bg: '#0a0e1a', accent: '#1a237e', name: 'deep blue' },
  { bg: '#0a1a0a', accent: '#1b5e20', name: 'deep green' },
  { bg: '#1a0a2e', accent: '#4a148c', name: 'dark purple' },
  { bg: '#1a0a0a', accent: '#b71c1c', name: 'dark red' },
  { bg: '#0a1a2a', accent: '#0d47a1', name: 'ice blue' },
  { bg: '#1a1a0a', accent: '#f57f17', name: 'gold' },
] as const;

export type LevelTheme = (typeof LEVEL_THEMES)[number];

export function hexToRgb(hex: string): [number, number, number] {
  const h = hex.startsWith('#') ? hex.slice(1) : hex;
  const full = h.length === 3
    ? h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
    : h;
  const n = parseInt(full, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function rgbToHex(r: number, g: number, b: number): string {
  const clamp = (v: number) => Math.max(0, Math.min(255, Math.round(v)));
  const toHex = (v: number) => clamp(v).toString(16).padStart(2, '0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}

export function rgba(hex: string, alpha: number): string {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${r},${g},${b},${Math.max(0, Math.min(1, alpha))})`;
}

export function lerpColor(hex1: string, hex2: string, t: number): string {
  const [r1, g1, b1] = hexToRgb(hex1);
  const [r2, g2, b2] = hexToRgb(hex2);
  const ct = Math.max(0, Math.min(1, t));
  return rgbToHex(
    r1 + (r2 - r1) * ct,
    g1 + (g2 - g1) * ct,
    b1 + (b2 - b1) * ct,
  );
}

export function multiplyBrightness(hex: string, factor: number): string {
  const [r, g, b] = hexToRgb(hex);
  return rgbToHex(r * factor, g * factor, b * factor);
}

export function withAlpha(hex: string, alpha: number): string {
  return rgba(hex, alpha);
}
