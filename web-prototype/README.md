# 星空与萤火 — Web Prototype

SSVEP visual attention training prototype. 6 canvas-rendered levels for validating target camouflage and attention-driven feedback.

## Quick Start

```bash
cd web-prototype
npm install
npm run dev
```

Browser opens automatically at `http://localhost:5173`.

## Controls

### Keyboard

| Key | Action |
|-----|--------|
| `1`–`6` | Switch level |
| `H` | Toggle debug panel |
| `Space` | Pause / Resume |
| `S` | Screenshot (PNG download) |

### Debug Panel (Inspector)

Right-side panel with sliders for real-time parameter tuning:

- **Attention** (0–1): Simulates user attention level. Drives visual feedback in each level.
- **Target Freq** (5–30 Hz): SSVEP frequency for the target stimulus (default 15 Hz).
- **Distractor Freq** (5–30 Hz): SSVEP frequency for distractor stimuli (default 20 Hz).
- **Bloom** (0–1): Glow intensity on emissive elements.
- **Particles** (0–1): Particle density (stars, fireflies).
- **Reduce Motion**: Slows all animation to 20% speed.
- **Show Target Mask**: Red circle outline around the SSVEP target area.

## Levels

| # | Chinese | English | Target | Distractor |
|---|---------|---------|--------|------------|
| 1 | 涟漪绽放 | Lotus Lake | Lotus stamen, warm gold, 15 Hz | — |
| 2 | 萤火引路 | Firefly Forest | Firefly cluster, bio green, 15 Hz | — |
| 3 | 星图寻迹 | Constellation Trace | Gold constellation, 15 Hz | Blue constellation, 20 Hz |
| 4 | 真假萤火 | Dual Fireflies | Yellow-green fireflies (inner), 15 Hz | Blue fireflies (outer), 20 Hz |
| 5 | 飞燕破云 | Storm Swallow | Swallow chest glow, 15 Hz | Lightning, 20 Hz |
| 6 | 流星试炼 | Meteor Trial | Star → Moon, 15 Hz | Meteors, aurora |

### Design Principles

- **No HUD**: No scores, bars, progress indicators, or game elements.
- **SSVEP range**: Opacity modulates 55–100% (never hard flash 0–100%).
- **Target area**: < 5% of screen. Local, natural-looking emission.
- **Attention feedback**: Environmental narrative (lotus opens, tree grows, fog clears) — not numerical UI.
- **Aesthetic**: Apple Weather / Apple Mindfulness quality. Quiet, layered, restrained.

## Architecture

```
src/
├── main.ts              Entry point, level registration
├── styles.css           Full-screen canvas + debug overlay styles
├── core/
│   ├── App.ts           Game loop, fade transitions, level management
│   ├── Controls.ts      Debug panel (DOM), keyboard shortcuts
│   ├── Renderer.ts      Canvas setup, DPR scaling
│   ├── Timing.ts        SSVEP opacity, lerp, clamp, safeDt
│   └── types.ts         AppState, RenderContext, LEVEL_NAMES
├── levels/
│   ├── LevelRenderer.ts Abstract base class
│   ├── LotusLake.ts     Level 1
│   ├── FireflyForest.ts Level 2
│   ├── ConstellationTrace.ts Level 3
│   ├── DualFireflies.ts Level 4
│   ├── StormSwallow.ts  Level 5
│   └── MeteorTrial.ts   Level 6
└── utils/
    ├── color.ts         Palette constants, hex↔rgb, lerp
    ├── drawing.ts       13 Canvas 2D drawing helpers
    ├── easing.ts        18 easing functions
    └── noise.ts         Simplex noise (2D/3D) + fBm
```

### Adding a Level

1. Create `src/levels/YourLevel.ts` extending `LevelRenderer`.
2. Implement `name`, `subtitle`, and `draw(ctx, state)`.
3. Register in `src/main.ts`: `app.registerLevel(index, new YourLevel())`.

### SSVEP Pattern

```typescript
// In your LevelRenderer subclass:
const opacity = this.ssvep(this.levelTime, state.targetFrequency, 0.55, 1.0);
// Returns sine wave between 55%–100% at the given frequency
```

## Tech Stack

- **Vite** — dev server, bundling
- **TypeScript** — strict mode, no `any`
- **Canvas 2D** — all rendering (no WebGL, no frameworks)
- **Zero dependencies** — no external packages in production

## Performance

- 1440×900 at 60 FPS, DPR=2 supported
- `state.particleDensity` controls particle count for lower-end devices
- `state.reduceMotion` slows all animation for motion-sensitive users

## Limitations

This is a **visual prototype only**. Browser `requestAnimationFrame` does not guarantee precise SSVEP frequency timing. Native implementation is required for clinical use. See `Designs/IMPLEMENTATION_PLAN.md` for the native migration path.
