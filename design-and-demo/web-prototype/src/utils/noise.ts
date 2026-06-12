/**
 * 2D/3D Simplex Noise implementation for "星空与萤火" (Starfield & Fireflies).
 *
 * Based on Stefan Gustavson's simplex noise algorithm.
 * All functions are deterministic (fixed permutation table) and return values in [0, 1].
 * No allocations on the hot path — suitable for 60fps rendering.
 */

// ─── Fixed permutation table (seed = 42 via Fisher-Yates) ────────────────

const PERM: Uint8Array = new Uint8Array(512);
const PERM_MOD12: Uint8Array = new Uint8Array(512);

function initPermutation(): void {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;

  // Seeded Fisher-Yates shuffle (seed 42)
  let seed = 42;
  for (let i = 255; i > 0; i--) {
    seed = (seed * 16807 + 0) % 2147483647;
    const j = seed % (i + 1);
    const tmp = p[i];
    p[i] = p[j];
    p[j] = tmp;
  }

  for (let i = 0; i < 512; i++) {
    PERM[i] = p[i & 255];
    PERM_MOD12[i] = PERM[i] % 12;
  }
}

initPermutation();

// ─── Gradient tables ──────────────────────────────────────────────────────

const GRAD3: Float64Array = new Float64Array([
  1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1, 0,
  1, 0, 1, -1, 0, 1, 1, 0, -1, -1, 0, -1,
  0, 1, 1, 0, -1, 1, 0, 1, -1, 0, -1, -1,
]);

const F2 = 0.5 * (Math.sqrt(3) - 1); // ≈ 0.3660
const G2 = (3 - Math.sqrt(3)) / 6;   // ≈ 0.2115
const F3 = 1.0 / 3.0;
const G3 = 1.0 / 6.0;

// ─── Helpers (inlined-ish) ────────────────────────────────────────────────

function grad2(hash: number, x: number, y: number): number {
  const h = hash & 7;
  const u = h < 4 ? x : y;
  const v = h < 4 ? y : x;
  return ((h & 1) !== 0 ? -u : u) + ((h & 2) !== 0 ? -2.0 * v : 2.0 * v);
}

function grad3(hash: number, x: number, y: number, z: number): number {
  const idx = (hash % 12) * 3;
  return GRAD3[idx] * x + GRAD3[idx + 1] * y + GRAD3[idx + 2] * z;
}

function fastFloor(x: number): number {
  const xi = x | 0;
  return x < xi ? xi - 1 : xi;
}

// Remap from [-1, 1] → [0, 1]
function remap(n: number): number {
  return n * 0.5 + 0.5;
}

// ─── Public API ───────────────────────────────────────────────────────────

/**
 * 2D simplex noise.
 * Returns a value in [0, 1]. Deterministic for the same inputs.
 */
export function noise2D(xin: number, yin: number): number {
  const s = (xin + yin) * F2;
  const i = fastFloor(xin + s);
  const j = fastFloor(yin + s);
  const t = (i + j) * G2;

  const x0 = xin - (i - t);
  const y0 = yin - (j - t);

  const i1 = x0 > y0 ? 1 : 0;
  const j1 = x0 > y0 ? 0 : 1;

  const x1 = x0 - i1 + G2;
  const y1 = y0 - j1 + G2;
  const x2 = x0 - 1.0 + 2.0 * G2;
  const y2 = y0 - 1.0 + 2.0 * G2;

  const ii = i & 255;
  const jj = j & 255;

  let n0 = 0;
  let n1 = 0;
  let n2 = 0;

  let t0 = 0.5 - x0 * x0 - y0 * y0;
  if (t0 >= 0) {
    const gi0 = PERM_MOD12[ii + PERM[jj]];
    t0 *= t0;
    n0 = t0 * t0 * grad2(gi0, x0, y0);
  }

  let t1 = 0.5 - x1 * x1 - y1 * y1;
  if (t1 >= 0) {
    const gi1 = PERM_MOD12[ii + i1 + PERM[jj + j1]];
    t1 *= t1;
    n1 = t1 * t1 * grad2(gi1, x1, y1);
  }

  let t2 = 0.5 - x2 * x2 - y2 * y2;
  if (t2 >= 0) {
    const gi2 = PERM_MOD12[ii + 1 + PERM[jj + 1]];
    t2 *= t2;
    n2 = t2 * t2 * grad2(gi2, x2, y2);
  }

  // Scale to [-1, 1] then remap to [0, 1]
  return remap(70.0 * (n0 + n1 + n2));
}

/**
 * 3D simplex noise (for time-animated effects).
 * Returns a value in [0, 1]. Deterministic for the same inputs.
 */
export function noise3D(xin: number, yin: number, zin: number): number {
  const s = (xin + yin + zin) * F3;
  const i = fastFloor(xin + s);
  const j = fastFloor(yin + s);
  const k = fastFloor(zin + s);
  const t = (i + j + k) * G3;

  const x0 = xin - (i - t);
  const y0 = yin - (j - t);
  const z0 = zin - (k - t);

  let i1: number, j1: number, k1: number;
  let i2: number, j2: number, k2: number;

  if (x0 >= y0) {
    if (y0 >= z0) {
      i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
    } else if (x0 >= z0) {
      i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1;
    } else {
      i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1;
    }
  } else {
    if (y0 < z0) {
      i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1;
    } else if (x0 < z0) {
      i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1;
    } else {
      i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0;
    }
  }

  const x1 = x0 - i1 + G3;
  const y1 = y0 - j1 + G3;
  const z1 = z0 - k1 + G3;
  const x2 = x0 - i2 + 2.0 * G3;
  const y2 = y0 - j2 + 2.0 * G3;
  const z2 = z0 - k2 + 2.0 * G3;
  const x3 = x0 - 1.0 + 3.0 * G3;
  const y3 = y0 - 1.0 + 3.0 * G3;
  const z3 = z0 - 1.0 + 3.0 * G3;

  const ii = i & 255;
  const jj = j & 255;
  const kk = k & 255;

  let n0 = 0;
  let n1 = 0;
  let n2 = 0;
  let n3 = 0;

  let t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0;
  if (t0 >= 0) {
    const gi0 = PERM_MOD12[ii + PERM[jj + PERM[kk]]] * 3;
    t0 *= t0;
    n0 = t0 * t0 * (GRAD3[gi0] * x0 + GRAD3[gi0 + 1] * y0 + GRAD3[gi0 + 2] * z0);
  }

  let t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1;
  if (t1 >= 0) {
    const gi1 = PERM_MOD12[ii + i1 + PERM[jj + j1 + PERM[kk + k1]]] * 3;
    t1 *= t1;
    n1 = t1 * t1 * (GRAD3[gi1] * x1 + GRAD3[gi1 + 1] * y1 + GRAD3[gi1 + 2] * z1);
  }

  let t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2;
  if (t2 >= 0) {
    const gi2 = PERM_MOD12[ii + i2 + PERM[jj + j2 + PERM[kk + k2]]] * 3;
    t2 *= t2;
    n2 = t2 * t2 * (GRAD3[gi2] * x2 + GRAD3[gi2 + 1] * y2 + GRAD3[gi2 + 2] * z2);
  }

  let t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3;
  if (t3 >= 0) {
    const gi3 = PERM_MOD12[ii + 1 + PERM[jj + 1 + PERM[kk + 1]]] * 3;
    t3 *= t3;
    n3 = t3 * t3 * (GRAD3[gi3] * x3 + GRAD3[gi3 + 1] * y3 + GRAD3[gi3 + 2] * z3);
  }

  return remap(32.0 * (n0 + n1 + n2 + n3));
}

/**
 * Fractal Brownian motion — layered noise for natural detail.
 * Returns value in [0, 1].
 *
 * @param octaves     Number of noise layers (default 4)
 * @param lacunarity  Frequency multiplier per octave (default 2)
 * @param gain        Amplitude multiplier per octave (default 0.5)
 */
export function fbm(
  x: number,
  y: number,
  octaves: number = 4,
  lacunarity: number = 2,
  gain: number = 0.5,
): number {
  let value = 0;
  let amplitude = 1;
  let frequency = 1;
  let maxAmplitude = 0;

  for (let i = 0; i < octaves; i++) {
    value += amplitude * noise2D(x * frequency, y * frequency);
    maxAmplitude += amplitude;
    amplitude *= gain;
    frequency *= lacunarity;
  }

  // Normalise into [0, 1]
  return value / maxAmplitude;
}
