//
//  Starfield.metal
//  StarfieldFireflies
//
//  Background scene rendering: 7 scene modes for 6 SSVEP levels + default.
//

#include <metal_stdlib>
using namespace metal;
#include "Shared.metal"

// ── Helper: 2D value noise ──

inline float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise2D(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

inline float ellipseMask(float2 p, float2 center, float2 radius, float softness) {
    float2 q = (p - center) / radius;
    float d = length(q);
    return smoothstep(1.0, 1.0 - softness, d);
}

// ── Shared star rendering helper ──

inline float3 renderStars(float2 uv, float density, float brightness, float time) {
    float3 result = float3(0.0);
    if (density <= 0.0 || brightness <= 0.0) return result;

    float2 starUV = uv * density;
    float2 cellID = floor(starUV);
    float2 cellUV = fract(starUV) - 0.5;

    float starHash = hash(cellID);
    if (starHash > 0.7) {
        float2 starPos = hash2(cellID) - 0.5;
        float dist = length(cellUV - starPos);
        float twinkle = sin(time * (1.0 + starHash * 3.0) + starHash * 6.28) * 0.3 + 0.7;
        float starBright = smoothstep(0.03, 0.0, dist) * twinkle;
        float3 starColor = mix(
            float3(0.9, 0.92, 1.0),
            float3(1.0, 0.95, 0.85),
            hash(cellID + 0.1)
        );
        result = starColor * starBright * brightness;
    }
    return result;
}

// ── Background Vertex Shader ──

vertex BackgroundFragmentIn backgroundVertex(
    uint vid [[vertex_id]],
    constant float* vertexData [[buffer(kBufferVertices)]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]]
) {
    BackgroundFragmentIn out;
    float2 pos = float2(vertexData[vid * 4], vertexData[vid * 4 + 1]);
    float2 uv  = float2(vertexData[vid * 4 + 2], vertexData[vid * 4 + 3]);
    out.position = float4(pos, 0.0, 1.0);
    out.uv = uv;
    return out;
}

// ── Background Fragment Shader ──

fragment float4 backgroundFragment(
    BackgroundFragmentIn in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]],
    constant AttentionState& attention [[buffer(kBufferAttention)]],
    constant LevelSceneConfig& config [[buffer(kBufferLevelConfig)]]
) {
    float2 uv = in.uv;
    float time = uniforms.time;
    float attentionLevel = clamp(attention.level, 0.0, 1.0);
    float3 color = float3(0.0);

    switch (config.sceneMode) {

    // ═══════════════════════════════════════════
    // sceneMode 0: Default Starfield (original)
    // ═══════════════════════════════════════════
    default: {
        float3 bgColor = config.backgroundColor.rgb;
        color = mix(bgColor, bgColor * 1.5 + float3(0.01, 0.01, 0.02), uv.y);
        color += renderStars(uv, config.starDensity > 0.0 ? config.starDensity : 40.0,
                             config.starBrightness > 0.0 ? config.starBrightness : 0.8, time);

        float mountainHeight = config.mountainHeight > 0.0 ? config.mountainHeight : 0.12;
        float mn = hash(float2(uv.x * 4.0, 0.0)) * 0.15 + hash(float2(uv.x * 9.2, 0.0)) * 0.08;
        if (uv.y < mn * mountainHeight + 0.03) {
            color = float3(0.01, 0.01, 0.02);
        }
        if (config.fogDensity > 0.0) {
            float ff = config.fogHeightFalloff > 0.0 ? 1.0 / config.fogHeightFalloff : 1.0;
            color = mix(color, config.fogColor.rgb, config.fogDensity * smoothstep(0.0, ff, uv.y));
        }
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 1: L1 涟漪绽放 — Lake + Lotus
    // ═══════════════════════════════════════════
    case 1: {
        float3 skyLow  = float3(0.020, 0.034, 0.062);
        float3 skyMid  = float3(0.052, 0.073, 0.118);
        float3 skyHigh = float3(0.090, 0.106, 0.160);
        color = mix(skyLow, skyMid, smoothstep(0.28, 0.78, uv.y));
        color = mix(color, skyHigh, smoothstep(0.70, 1.0, uv.y) * 0.35);

        float moon = ellipseMask(uv, float2(0.78, 0.80), float2(0.035, 0.035), 0.16);
        float moonHalo = exp(-length(uv - float2(0.78, 0.80)) * length(uv - float2(0.78, 0.80)) * 34.0);
        color += float3(1.0, 0.92, 0.72) * moon * 0.95;
        color += float3(0.45, 0.50, 0.68) * moonHalo * 0.22;

        color += renderStars(uv, 34.0, 0.85, time);
        color += renderStars(uv + float2(0.37, 0.19), 58.0, 0.30, time * 0.7);

        float waterLvl = config.waterLevel;
        float horizon = waterLvl + 0.15;
        float farRidge = horizon + noise2D(float2(uv.x * 6.0, 2.0)) * 0.075 + 0.02;
        float nearRidge = horizon - 0.030 + noise2D(float2(uv.x * 11.0, 4.0)) * 0.060;
        if (uv.y > horizon - 0.035 && uv.y < farRidge) {
            color = mix(color, float3(0.012, 0.021, 0.038), 0.85);
        }
        if (uv.y > horizon - 0.050 && uv.y < nearRidge) {
            color = mix(color, float3(0.006, 0.017, 0.022), 0.92);
        }

        if (uv.y < waterLvl) {
            float depth = 1.0 - uv.y / max(waterLvl, 0.001);
            float2 waterUV = float2(
                uv.x + sin(uv.y * config.waterWaveFrequency * 9.0 + time * 1.5) * config.waterWaveAmplitude,
                uv.y
            );
            float2 lotusCenter = float2(0.5, waterLvl + 0.05);
            float ripDist = length(float2(uv.x, uv.y) - lotusCenter);
            float ripples = max(sin(ripDist * 56.0 - time * 3.4), 0.0) * exp(-ripDist * 3.8);
            float waveLines = pow(max(sin((waterUV.y * 92.0 + sin(waterUV.x * 18.0) * 1.7) - time * 1.25), 0.0), 10.0);
            float3 reflSky = mix(float3(0.020, 0.045, 0.070), float3(0.055, 0.105, 0.130), waterUV.y / max(waterLvl, 0.001));
            float3 waterColor = mix(float3(0.010, 0.027, 0.038), reflSky, 0.78);
            waterColor += float3(0.18, 0.34, 0.23) * ripples * mix(0.10, 0.30, attentionLevel);
            waterColor += float3(0.42, 0.60, 0.66) * waveLines * 0.055 * (1.0 - depth * 0.35);
            waterColor += float3(0.70, 0.78, 0.58) * moonHalo * 0.10 * smoothstep(0.0, waterLvl, uv.y);
            color = waterColor;
        }

        float2 lotusPos = float2(0.5, waterLvl + 0.05);
        float2 toLotus = uv - lotusPos;
        float lotusR = length(toLotus);
        float lotusAngle = atan2(toLotus.y, toLotus.x);

        float lotusSize = config.lotusSize * mix(0.55, 1.08, attentionLevel);
        float open = mix(0.58, 1.0, attentionLevel);

        float leaf1 = ellipseMask(uv, lotusPos + float2(-0.105, -0.050), float2(0.115, 0.035), 0.18);
        float leaf2 = ellipseMask(uv, lotusPos + float2(0.120, -0.040), float2(0.100, 0.032), 0.18);
        float leaf3 = ellipseMask(uv, lotusPos + float2(0.008, -0.078), float2(0.070, 0.025), 0.18);
        float leafMask = max(max(leaf1, leaf2), leaf3);
        color = mix(color, float3(0.020, 0.135, 0.090), leafMask * 0.68);
        color += float3(0.16, 0.32, 0.18) * leafMask * 0.12;

        float petal = 0.0;
        float3 petalColorAccum = float3(0.0);
        for (int i = 0; i < 12; i++) {
            float layer = i < 6 ? 0.0 : 1.0;
            float petalAngle = (float(i % 6) + layer * 0.5) * 6.2832 / 6.0;
            float angleDiff = abs(fmod(lotusAngle - petalAngle + 3.1416, 6.2832) - 3.1416);
            float width = mix(0.34, 0.22, layer) * open;
            float petalShape = smoothstep(width, 0.0, angleDiff);
            float outer = lotusSize * mix(1.28, 0.92, layer) * open;
            float inner = lotusSize * mix(0.18, 0.10, layer);
            float petalRadial = smoothstep(outer, outer * 0.62, lotusR) * smoothstep(inner, inner * 1.8, lotusR);
            float p = petalShape * petalRadial;
            petal = max(petal, p);
            petalColorAccum += mix(float3(1.0, 0.54, 0.72), float3(1.0, 0.86, 0.56), layer * 0.6) * p;
        }

        float center = ellipseMask(uv, lotusPos, float2(lotusSize * 0.22, lotusSize * 0.16), 0.25);
        color += petalColorAccum * mix(0.95, 1.65, attentionLevel);
        color += float3(1.0, 0.88, 0.48) * center * 1.45;

        float lotusAura = exp(-lotusR * lotusR / 0.020);
        color += float3(1.0, 0.86, 0.42) * lotusAura * mix(0.35, 0.82, attentionLevel);

        float rippleEffect = 0.0;
        for (int rr = 0; rr < 5; rr++) {
            float ringR = 0.070 + float(rr) * 0.065 + fract(time * 0.055 + float(rr) * 0.18) * 0.065;
            rippleEffect += smoothstep(0.009, 0.0, abs(lotusR - ringR)) * (1.0 - float(rr) * 0.13);
        }
        color += float3(0.65, 0.88, 0.62) * rippleEffect * mix(0.10, 0.30, attentionLevel);

        float horizonLine = smoothstep(0.008, 0.0, abs(uv.y - waterLvl));
        color += float3(0.50, 0.62, 0.68) * horizonLine * 0.32;

        if (config.fogDensity > 0.0) {
            float fogAmt = config.fogDensity * (1.0 - uv.y) * 0.18;
            color = mix(color, float3(0.045, 0.070, 0.082), fogAmt);
        }
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 2: L2 萤火引路 — Foggy Forest
    // ═══════════════════════════════════════════
    case 2: {
        // Very dark forest canopy background
        color = float3(0.005, 0.008, 0.005);

        // Ground
        if (uv.y < 0.15) {
            float groundNoise = noise2D(uv * 30.0) * 0.02;
            color = float3(0.01, 0.015, 0.008) + groundNoise;
        }

        // Tree trunks — dark vertical stripes at regular intervals
        for (int i = 0; i < 12; i++) {
            float trunkX = hash(float2(float(i), 0.0)) * 1.0;
            float trunkWidth = 0.008 + hash(float2(float(i), 1.0)) * 0.025;
            float trunkDist = abs(uv.x - trunkX);
            if (trunkDist < trunkWidth && uv.y > 0.1) {
                // Trunk darkens as it goes up
                float trunkFade = 1.0 - uv.y * 0.3;
                color = float3(0.01, 0.008, 0.005) * trunkFade;

                // Branches at various heights
                for (int j = 0; j < 4; j++) {
                    float branchY = 0.3 + hash(float2(float(i), float(j) + 2.0)) * 0.55;
                    float branchLen = 0.05 + hash(float2(float(i) + 5.0, float(j))) * 0.1;
                    float branchDir = hash(float2(float(i), float(j) + 10.0)) > 0.5 ? 1.0 : -1.0;
                    float branchDistY = abs(uv.y - branchY);
                    if (branchDistY < 0.003 && trunkDist < trunkWidth + branchLen * branchDir) {
                        color = float3(0.008, 0.006, 0.004);
                    }
                }
            }
        }

        // Stone monument
        float2 monPos = float2(0.5 + config.monumentX, 0.5 + config.monumentY);
        float2 monSize = float2(0.03, 0.08);
        float monMask = smoothstep(monSize.x, monSize.x - 0.005, abs(uv.x - monPos.x))
                      * smoothstep(monSize.y, monSize.y - 0.005, abs(uv.y - monPos.y));
        color = mix(color, float3(0.05, 0.05, 0.06), monMask);

        // Heavy fog — thins with height
        float fogAmount = config.fogDensity * exp(-uv.y * config.fogHeightFalloff) * mix(1.0, 0.18, attentionLevel);
        fogAmount = clamp(fogAmount, 0.0, 1.0);
        color = mix(color, config.fogColor.rgb, fogAmount);

        float runeGlow = exp(-length(uv - monPos) * length(uv - monPos) * 900.0) * attentionLevel;
        color += float3(0.80, 0.86, 0.22) * runeGlow * 0.5;
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 3: L3 星图寻迹 — Constellation Sky
    // ═══════════════════════════════════════════
    case 3: {
        // Deep space dark blue-black
        color = mix(float3(0.005, 0.005, 0.02), float3(0.02, 0.02, 0.06), uv.y);

        // Dense stars (density=80 → fine grid)
        color += renderStars(uv, 80.0, 0.8, time);

        // Constellation lines between bright stars
        // Predefined star positions (8 anchor points)
        float2 starPts[8];
        starPts[0] = float2(0.2, 0.7);
        starPts[1] = float2(0.3, 0.8);
        starPts[2] = float2(0.45, 0.75);
        starPts[3] = float2(0.55, 0.85);
        starPts[4] = float2(0.7, 0.7);
        starPts[5] = float2(0.35, 0.6);
        starPts[6] = float2(0.6, 0.6);
        starPts[7] = float2(0.5, 0.55);

        // Draw connecting lines for a constellation shape
        int linePairs[14] = {0,1, 1,2, 2,3, 3,4, 2,5, 2,6, 6,7};
        for (int li = 0; li < 7; li++) {
            int ia = linePairs[li * 2];
            int ib = linePairs[li * 2 + 1];
            float2 pa = starPts[ia];
            float2 pb = starPts[ib];
            float2 ab = pb - pa;
            float2 ap = uv - pa;
            float t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
            float2 closest = pa + ab * t;
            float lineDist = length(uv - closest);
            float lineGlow = smoothstep(0.003, 0.0, lineDist) * mix(0.10, 0.45, attentionLevel);
            color += float3(0.3, 0.35, 0.6) * lineGlow;
        }

        // Bright anchor star dots
        for (int si = 0; si < 8; si++) {
            float dist = length(uv - starPts[si]);
            float starGlow = exp(-dist * dist * 2000.0) * 0.8;
            float twinkle = sin(time * (2.0 + float(si) * 0.7) + float(si) * 1.3) * 0.15 + 0.85;
            color += float3(0.7, 0.8, 1.0) * starGlow * twinkle;
        }

        // Subtle distractor blue tint at edges
        float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        color += config.distractorColor.rgb * 0.02 * smoothstep(0.3, 0.0, edgeDist);
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 4: L4 真假萤火 — Dual-Color Forest
    // ═══════════════════════════════════════════
    case 4: {
        // Dark forest floor background
        color = float3(0.008, 0.012, 0.006);

        // Ground with grass-like noise
        if (uv.y < 0.2) {
            float grassNoise = noise2D(float2(uv.x * 40.0, uv.y * 20.0 + time * 0.5));
            float grass = smoothstep(0.3, 0.6, grassNoise);
            color = mix(float3(0.01, 0.02, 0.008), float3(0.02, 0.05, 0.015), grass * (1.0 - uv.y / 0.2));
        }

        // Tree trunks (fewer, less foggy than sceneMode 2)
        for (int i = 0; i < 8; i++) {
            float trunkX = hash(float2(float(i) + 10.0, 0.0));
            float trunkWidth = 0.01 + hash(float2(float(i) + 10.0, 1.0)) * 0.02;
            float trunkDist = abs(uv.x - trunkX);
            if (trunkDist < trunkWidth && uv.y > 0.15) {
                color = float3(0.015, 0.012, 0.008);
                // Canopy top
                if (uv.y > 0.75) {
                    float canopySpread = 0.05 + hash(float2(float(i) + 10.0, 3.0)) * 0.08;
                    if (trunkDist < canopySpread) {
                        color = float3(0.01, 0.025, 0.01);
                    }
                }
            }
        }

        // Tree of Life — central growing tree
        float treeX = config.treeOfLifeX + 0.5;
        float growth = max(config.treeOfLifeGrowth, smoothstep(0.35, 0.9, attentionLevel));

        // Trunk: tapered rectangle from bottom
        float trunkWidthBase = 0.015;
        float trunkHeight = 0.3 + growth * 0.4;
        float trunkWidthAtY = trunkWidthBase * (1.0 - (uv.y - 0.05) / trunkHeight * 0.5);

        if (abs(uv.x - treeX) < trunkWidthAtY && uv.y > 0.05 && uv.y < 0.05 + trunkHeight && growth > 0.05) {
            float trunkGlow = smoothstep(trunkWidthAtY, trunkWidthAtY * 0.3, abs(uv.x - treeX));
            color = mix(color, float3(0.08, 0.05, 0.02), trunkGlow * growth);
        }

        // Branches when growth > 0.3
        if (growth > 0.3) {
            float branchGrowth = (growth - 0.3) / 0.7;
            for (int b = 0; b < 5; b++) {
                float branchY = 0.2 + float(b) * 0.1;
                if (branchY > 0.05 + trunkHeight * 0.8) continue;
                float branchAngle = (b % 2 == 0 ? 1.0 : -1.0) * (0.3 + float(b) * 0.05);
                float branchLen = branchGrowth * 0.08 * (1.0 - float(b) * 0.1);

                // Line from (treeX, branchY) at angle
                float2 branchStart = float2(treeX, branchY);
                float2 branchDir = normalize(float2(branchAngle, 0.5));
                float2 bp = uv - branchStart;
                float bt = clamp(dot(bp, branchDir) / branchLen, 0.0, branchLen);
                float2 closest = branchStart + branchDir * bt;
                float bDist = length(uv - closest);
                if (bDist < 0.003 && bt > 0.0 && bt < branchLen) {
                    color = mix(color, float3(0.04, 0.06, 0.02), branchGrowth);
                }
            }

            // Canopy glow when fully grown
            if (growth > 0.7) {
                float canopyGlow = exp(-length(uv - float2(treeX, 0.6)) * length(uv - float2(treeX, 0.6)) * 15.0);
                color += float3(0.03, 0.06, 0.01) * canopyGlow * (growth - 0.7) / 0.3;
            }
        }

        // Light fog
        if (config.fogDensity > 0.0) {
            float fogAmt = config.fogDensity * exp(-uv.y * 2.0) * 0.5;
            color = mix(color, float3(0.02, 0.04, 0.02), fogAmt);
        }
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 5: L5 飞燕破云 — Storm
    // ═══════════════════════════════════════════
    case 5: {
        // Dark stormy sky gradient
        float3 stormLow  = float3(0.02, 0.01, 0.04);
        float3 stormHigh = float3(0.04, 0.02, 0.07);
        color = mix(stormLow, stormHigh, uv.y);

        // Turbulent clouds using layered noise
        float cloudNoise = fbm(uv * 3.0 + float2(time * 0.05, 0.0));
        float cloudMask = smoothstep(0.3, 0.7, cloudNoise);
        float3 cloudColor = mix(float3(0.02, 0.01, 0.03), float3(0.06, 0.04, 0.08), cloudMask);
        color = mix(color, cloudColor, 0.6);

        // Lightning flashes — intermittent bright flashes
        float flashPhase = floor(time * 2.0);
        float flashHash = hash(float2(flashPhase, 0.0));
        if (flashHash > 0.85) {
            float flashX = hash(float2(flashPhase, 1.0));
            float flashY = hash(float2(flashPhase, 2.0)) * 0.6 + 0.3;
            float flashDist = length(uv - float2(flashX, flashY));
            float flashIntensity = exp(-flashDist * flashDist * 8.0) * config.lightningIntensity;
            float flashFlicker = sin(time * 30.0) * 0.5 + 0.5; // rapid flicker
            color += float3(0.8, 0.85, 1.0) * flashIntensity * flashFlicker;
        }

        // Rain streaks — thin diagonal bright lines
        for (int r = 0; r < 20; r++) {
            float rainX = hash(float2(float(r), floor(time * 3.0 + float(r))));
            float rainY = fract(time * 0.8 + hash(float2(float(r), 5.0)));
            float2 rainPos = float2(rainX, 1.0 - rainY);
            float2 rainDrop = uv - rainPos;
            // Diagonal line: thin in x, elongated in y
            float rainDist = abs(rainDrop.x - rainDrop.y * 0.1);
            if (rainDist < 0.001 && abs(rainDrop.y) < 0.03) {
                color += float3(0.15, 0.15, 0.2) * (1.0 - abs(rainDrop.y) / 0.03);
            }
        }

        // Subtle purple/secondary tint
        color += config.secondaryColor.rgb * 0.02;
        break;
    }

    // ═══════════════════════════════════════════
    // sceneMode 6: L6 流星试炼 — Snow Mountain + Moon
    // ═══════════════════════════════════════════
    case 6: {
        // Clear dark night sky
        float3 nightLow  = float3(0.005, 0.008, 0.02);
        float3 nightHigh = float3(0.01, 0.015, 0.04);
        color = mix(nightLow, nightHigh, uv.y);

        // Dense starfield
        color += renderStars(uv, 60.0, 0.6, time);

        // Mountain — large triangular shape with noise for natural edges
        float peakHeight = config.snowPeakHeight;
        float mountainCenter = 0.5;
        float mtnDistFromCenter = abs(uv.x - mountainCenter);
        float mtnProfile = peakHeight * (1.0 - smoothstep(0.0, 0.4, mtnDistFromCenter));
        mtnProfile += noise2D(float2(uv.x * 8.0, 1.0)) * 0.03;
        float mtnBase = 0.08;

        if (uv.y < mtnProfile + mtnBase && uv.y > mtnBase * 0.5) {
            // Snow on upper parts of mountain
            float snowLine = mtnProfile * 0.5 + mtnBase;
            if (uv.y > snowLine) {
                color = mix(float3(0.03, 0.04, 0.06), float3(0.5, 0.55, 0.65),
                           smoothstep(snowLine, snowLine + 0.05, uv.y));
            } else {
                color = float3(0.03, 0.04, 0.06);
            }
        }
        // Ground below mountain
        if (uv.y < mtnBase) {
            color = float3(0.02, 0.025, 0.04);
        }

        // Moon at top center
        float2 moonPos = float2(0.5, 0.82);
        float moonDist = length(uv - moonPos);
        float moonRadius = 0.035;
        // Moon phase: 0 = thin crescent, 1 = full
        float moonFill = max(config.moonPhase, smoothstep(0.35, 0.95, attentionLevel));
        // Crescent effect: offset the fill circle
        float moonShape = smoothstep(moonRadius, moonRadius - 0.003, moonDist);
        float crescentOffset = moonRadius * 2.0 * (1.0 - moonFill);
        float crescentMask = smoothstep(moonRadius, moonRadius - 0.003,
            length(uv - float2(moonPos.x + crescentOffset, moonPos.y)));
        // Blend between crescent and full based on phase
        if (moonFill > 0.01) {
            float moonBody = mix(moonShape - crescentMask * 0.8, moonShape, moonFill);
            moonBody = clamp(moonBody, 0.0, 1.0);
            color += float3(0.85, 0.88, 0.95) * moonBody * 0.8;

            // Moon glow
            float moonGlow = exp(-moonDist * moonDist * 50.0) * 0.15;
            color += float3(0.3, 0.35, 0.5) * moonGlow;
        } else {
            // Phase 0: just a star point
            float starPt = exp(-moonDist * moonDist * 3000.0) * 0.5;
            color += float3(0.8, 0.85, 1.0) * starPt;
        }

        // Shooting stars — occasional diagonal streaks
        for (int s = 0; s < 3; s++) {
            float spawnTime = floor(time * 0.3 + float(s) * 7.0);
            float spawnHash = hash(float2(spawnTime, float(s) + 20.0));
            if (spawnHash > 0.6) {
                float life = fract(time * 0.3 + float(s) * 0.33);
                float2 startPt = float2(hash(float2(spawnTime, float(s))), 0.7 + hash(float2(float(s), spawnTime)) * 0.25);
                float2 endPt = startPt + float2(-0.15, -0.1) * life;
                float2 trailDir = endPt - startPt;
                float2 tp = uv - startPt;
                float t = clamp(dot(tp, trailDir) / dot(trailDir, trailDir), 0.0, 1.0);
                float2 closest = startPt + trailDir * t;
                float trailDist = length(uv - closest);
                float trailGlow = smoothstep(0.003, 0.0, trailDist) * (1.0 - life) * 0.5;
                color += float3(0.9, 0.7, 0.4) * trailGlow;
            }
        }
        break;
    }

    } // end switch

    // Global subtle breathing animation
    float breathe = sin(time * 0.5) * 0.005 + 1.0;
    color = color * breathe * 1.75 + float3(0.006, 0.007, 0.011);

    return float4(color, 1.0);
}
