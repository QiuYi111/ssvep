//
//  SSVEPStimulus.metal
//  StarfieldFireflies
//
//  Per-level SSVEP stimulus overlay.
//  Each level has distinct target/distractor geometry.
//  Uses additive blending. Opacity modulates sinusoidally via
//  ssvep.targetOpacity / ssvep.distractorOpacity (60%-100%).
//
//  Design constraints:
//  - "局部高光闪烁(占屏幕面积<5%)配合透明度正弦波形变(60%~100%波动)"
//  - "绝对禁止大面积0~100%的方波硬闪"
//  - No discard_fragment(); all branches return valid float4.
//

#include <metal_stdlib>
using namespace metal;
#include "Shared.metal"

inline float3 guidingPulseContribution(float dist, float time, float enabled) {
    if (enabled < 0.5) return float3(0.0);
    float breathPhase = sin(time * 2.0 * 3.14159 * 2.0) * 0.5 + 0.5;
    float sigma = 0.08 + breathPhase * 0.04;
    float guideGlow = exp(-dist * dist / (2.0 * sigma * sigma)) * breathPhase * 0.3;
    return float3(1.0, 1.0, 0.9) * guideGlow;
}

inline float gaussian(float d, float sigma) {
    return exp(-d * d / (2.0 * sigma * sigma));
}

// ── SSVEP Overlay Vertex Shader ──

vertex VertexOut ssvepOverlayVertex(
    uint vid [[vertex_id]],
    constant float* vertexData [[buffer(kBufferVertices)]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]]
) {
    VertexOut out;
    float2 pos = float2(vertexData[vid * 4], vertexData[vid * 4 + 1]);
    float2 uv  = float2(vertexData[vid * 4 + 2], vertexData[vid * 4 + 3]);
    out.position = float4(pos, 0.0, 1.0);
    out.uv = uv;
    return out;
}

// ── SSVEP Overlay Fragment Shader ──

fragment float4 ssvepOverlayFragment(
    VertexOut in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]],
    constant SSVEPParams& ssvep [[buffer(kBufferSSVEP)]],
    constant LevelSceneConfig& config [[buffer(kBufferLevelConfig)]]
) {
    float2 uv = in.uv;
    float time = uniforms.time;

    float3 targetColor = config.themeColor.rgb;
    float3 distractorColor = config.distractorColor.rgb;

    // Initialize outputs
    float3 color = float3(0.0);
    float targetMod = 0.0;
    float distractorMod = 0.0;

    if (ssvep.riftMode > 0.5) {
        float dist = length(uv - float2(0.5));
        float phase = ssvep.targetOpacity * 2.0 - (0.95 + 1.0);
        float subtleShift = phase * 10.0 + 0.5;
        subtleShift = clamp(subtleShift, 0.0, 1.0);
        float3 warmTint = float3(1.0, 0.95, 0.85);
        float3 coolTint = float3(0.85, 0.95, 1.0);
        float3 riftColor = mix(coolTint, warmTint, subtleShift);
        float riftGlow = gaussian(dist, 0.15) * 0.04;
        color = riftColor * riftGlow;
        float alpha = riftGlow;
        return float4(color * alpha, alpha);
    }

    switch (config.sceneMode) {

    // ═══════════════════════════════════════════
    // Default (sceneMode 0): Centered Gaussian + ring
    // ═══════════════════════════════════════════
    default: {
        float centerDist = length(uv - float2(0.5));
        float targetGlow = exp(-centerDist * centerDist * 80.0);

        float ringDist = abs(length(uv - float2(0.5)) - 0.35);
        float distractorGlow = exp(-ringDist * ringDist * 200.0) * 0.5;

        float advancedGlow = 0.15;

        targetColor = float3(0.804, 0.863, 0.224);
        distractorColor = float3(0.541, 0.706, 0.973);

        targetMod = ssvep.targetOpacity * targetGlow;
        distractorMod = ssvep.distractorOpacity * distractorGlow;
        float advancedMod = ssvep.advancedOpacity * advancedGlow;

        color = targetColor * targetMod
              + distractorColor * distractorMod
              + float3(0.7, 0.7, 0.9) * advancedMod
              + guidingPulseContribution(centerDist, time, ssvep.guidingPulse);
        float alpha = targetMod + distractorMod + advancedMod;
        return float4(color * alpha, alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 1 (L1): Central lotus glow — NO distractor
    // ═══════════════════════════════════════════
    case 1: {
        float2 lotusPos = float2(0.5, 0.45);
        float2 toLotus = uv - lotusPos;
        float lotusDist = length(toLotus);
        float angle = atan2(toLotus.y, toLotus.x);

        float petalGlow = 0.0;
        for (int i = 0; i < 10; i++) {
            float layer = i < 5 ? 0.0 : 1.0;
            float petalAngle = (float(i % 5) + layer * 0.5) * 6.2832 / 5.0;
            float angleDiff = abs(fmod(angle - petalAngle + 3.1416, 6.2832) - 3.1416);
            float angular = smoothstep(mix(0.42, 0.26, layer), 0.0, angleDiff);
            float outer = config.lotusSize * mix(1.85, 1.35, layer);
            float inner = config.lotusSize * mix(0.20, 0.10, layer);
            float radial = smoothstep(outer, outer * 0.42, lotusDist) * smoothstep(inner, inner * 1.8, lotusDist);
            petalGlow = max(petalGlow, angular * radial);
        }

        float centerGlow = gaussian(lotusDist, config.lotusSize * 0.24);
        float halo = gaussian(lotusDist, config.lotusSize * 1.90) * 0.35;
        float targetGlow = min(petalGlow * 1.25 + centerGlow + halo, 1.0);

        targetMod = ssvep.targetOpacity * targetGlow * 1.25;

        color = mix(float3(1.0, 0.52, 0.72), targetColor, 0.48) * targetMod
              + guidingPulseContribution(lotusDist, time, ssvep.guidingPulse);
        float alpha = min(targetMod, 1.0);
        return float4(color * min(alpha, 0.88), alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 2 (L2): Firefly cluster — NO distractor
    // ═══════════════════════════════════════════
    case 2: {
        float totalGlow = 0.0;
        for (int i = 0; i < 5; i++) {
            float2 dotPos = float2(
                0.45 + hash(float2(float(i), 10.0)) * 0.1,
                0.4 + hash(float2(float(i), 11.0)) * 0.15
            );
            float d = length(uv - dotPos);
            totalGlow += exp(-d * d * 500.0);
        }
        totalGlow = min(totalGlow, 1.5);

        targetMod = ssvep.targetOpacity * totalGlow;

        float clusterDist = length(uv - float2(0.5, 0.475));
        color = targetColor * targetMod
              + guidingPulseContribution(clusterDist, time, ssvep.guidingPulse);
        float alpha = targetMod;
        return float4(color * alpha, alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 3 (L3): Sequential stars + blue distractor dots
    // ═══════════════════════════════════════════
    case 3: {
        float2 starPts[8];
        starPts[0] = float2(0.2, 0.7);
        starPts[1] = float2(0.3, 0.8);
        starPts[2] = float2(0.45, 0.75);
        starPts[3] = float2(0.55, 0.85);
        starPts[4] = float2(0.7, 0.7);
        starPts[5] = float2(0.35, 0.6);
        starPts[6] = float2(0.6, 0.6);
        starPts[7] = float2(0.5, 0.55);

        int idx = int(floor(time * 0.3)) % 8;
        float2 activeStar = starPts[idx];

        float starDist = length(uv - activeStar);
        float targetGlow = exp(-starDist * starDist * 800.0);

        targetMod = ssvep.targetOpacity * targetGlow;

        float distractorGlow = 0.0;
        for (int di = 0; di < 12; di++) {
            float2 dpos = float2(
                hash(float2(float(di), 20.0)),
                hash(float2(float(di), 21.0))
            );
            float dd = length(uv - dpos);
            distractorGlow += exp(-dd * dd * 1500.0) * 0.3;
        }
        distractorGlow = min(distractorGlow, 1.0);
        distractorMod = ssvep.distractorOpacity * distractorGlow;

        color = targetColor * targetMod
              + distractorColor * distractorMod
              + guidingPulseContribution(starDist, time, ssvep.guidingPulse);
        float alpha = targetMod + distractorMod;
        return float4(color * alpha, alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 4 (L4): Dual fireflies (green target + blue distractor)
    // ═══════════════════════════════════════════
    case 4: {
        float targetGlow = 0.0;
        for (int ti = 0; ti < 5; ti++) {
            float2 tpos = float2(
                0.3 + hash(float2(float(ti), 30.0)) * 0.4,
                0.35 + hash(float2(float(ti), 31.0)) * 0.3
            );
            float td = length(uv - tpos);
            targetGlow += exp(-td * td * 600.0);
        }
        targetGlow = min(targetGlow, 1.5);
        targetMod = ssvep.targetOpacity * targetGlow;

        float distractorGlow = 0.0;
        for (int di = 0; di < 5; di++) {
            float2 dpos = float2(
                0.2 + hash(float2(float(di), 40.0)) * 0.6,
                0.3 + hash(float2(float(di), 41.0)) * 0.4
            );
            float dd = length(uv - dpos);
            distractorGlow += exp(-dd * dd * 600.0);
        }
        distractorGlow = min(distractorGlow, 1.5);
        distractorMod = ssvep.distractorOpacity * distractorGlow;

        float clusterDist = length(uv - float2(0.5, 0.5));
        color = targetColor * targetMod
              + distractorColor * distractorMod
              + guidingPulseContribution(clusterDist, time, ssvep.guidingPulse);
        float alpha = targetMod + distractorMod;
        return float4(color * alpha, alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 5 (L5): Moving swallow + lightning distractor
    // ═══════════════════════════════════════════
    case 5: {
        float2 swallowPos = float2(
            0.5 + sin(time * 0.5) * 0.3,
            0.5 + cos(time * 0.3) * 0.2
        );
        float swallowDist = length(uv - swallowPos);
        float targetGlow = exp(-swallowDist * swallowDist * 400.0);
        targetMod = ssvep.targetOpacity * targetGlow;

        float distractorGlow = 0.0;
        float flashPhase = floor(time * 4.0);
        float flashHash = hash(float2(flashPhase, 50.0));
        if (flashHash > 0.7) {
            float2 flashPos = float2(
                hash(float2(flashPhase, 51.0)),
                hash(float2(flashPhase, 52.0)) * 0.6 + 0.3
            );
            float fd = length(uv - flashPos);
            float flashLife = fract(time * 4.0);
            float flashIntensity = (1.0 - flashLife) * 0.5;
            distractorGlow = exp(-fd * fd * 300.0) * flashIntensity;
        }
        distractorMod = ssvep.distractorOpacity * distractorGlow;

        color = targetColor * targetMod
              + config.secondaryColor.rgb * distractorMod
              + guidingPulseContribution(swallowDist, time, ssvep.guidingPulse);
        float alpha = targetMod + distractorMod;
        return float4(color * alpha, alpha);
    }

    // ═══════════════════════════════════════════
    // sceneMode 6 (L6): Peak star/moon + shooting star distractors
    // ═══════════════════════════════════════════
    case 6: {
        float2 peakPos = float2(0.5, 0.75);
        float peakDist = length(uv - peakPos);

        float baseSigma = 0.02;
        float maxSigma = 0.05;
        float sigma = mix(baseSigma, maxSigma, ssvep.attentionLevel);
        float targetGlow = exp(-peakDist * peakDist / (2.0 * sigma * sigma));
        targetMod = ssvep.targetOpacity * targetGlow;

        float distractorGlow = 0.0;
        for (int s = 0; s < 3; s++) {
            float spawnPhase = floor(time * 0.5 + float(s) * 3.3);
            float spawnHash = hash(float2(spawnPhase, float(s) + 60.0));
            if (spawnHash > 0.5) {
                float life = fract(time * 0.5 + float(s) * 0.33);
                float2 startPt = float2(
                    hash(float2(spawnPhase, float(s) + 61.0)),
                    0.6 + hash(float2(float(s) + 60.0, spawnPhase)) * 0.35
                );
                float2 endPt = startPt + float2(-0.12, -0.08) * life;
                float2 trailDir = endPt - startPt;
                float2 tp = uv - startPt;
                float t = clamp(dot(tp, trailDir) / max(dot(trailDir, trailDir), 0.0001), 0.0, 1.0);
                float2 closest = startPt + trailDir * t;
                float trailDist = length(uv - closest);
                float trailGlow = smoothstep(0.004, 0.0, trailDist) * (1.0 - life) * 0.4;
                distractorGlow += trailGlow;
            }
        }
        distractorGlow = min(distractorGlow, 1.0);
        distractorMod = ssvep.distractorOpacity * distractorGlow;

        color = targetColor * targetMod
              + distractorColor * distractorMod
              + guidingPulseContribution(peakDist, time, ssvep.guidingPulse);
        float alpha = targetMod + distractorMod;
        return float4(color * alpha, alpha);
    }

    } // end switch

    return float4(0.0);
}
