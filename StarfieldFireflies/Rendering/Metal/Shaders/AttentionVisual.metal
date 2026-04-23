//
//  AttentionVisual.metal
//  StarfieldFireflies
//
//  Attention-driven visual effects per level:
//  - Default: vignette + color temperature
//  - L1: ripple rings when focused
//  - L2: fog density inversely proportional to attention
//  - L3: star-field brightening
//  - L4: warm glow at tree of life
//  - L5: flight smoothing / screen shake when distracted
//  - L6: moon cracks when distracted, glow when focused
//
//  All effects are No-HUD: purely visual, no UI overlays.
//

#include <metal_stdlib>
using namespace metal;
#include "Shared.metal"

// ── Attention Visual Vertex Shader ──

vertex VertexOut attentionVisualVertex(
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

// ── Attention Visual Fragment Shader ──

fragment float4 attentionVisualFragment(
    VertexOut in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]],
    constant AttentionState& attention [[buffer(kBufferAttention)]],
    constant LevelSceneConfig& config [[buffer(kBufferLevelConfig)]]
) {
    float2 uv = in.uv;
    float time = uniforms.time;
    float attentionLevel = attention.level;
    float3 resultColor = float3(1.0);
    float alpha = 0.0;

    switch (config.attentionEffectMode) {

    // ═══════════════════════════════════════════
    // Mode 0: Default — vignette + color temperature
    // ═══════════════════════════════════════════
    default: {
        float2 center = uv - float2(0.5);
        float vignetteDist = length(center);
        float vignetteStrength = mix(0.8, 0.2, attentionLevel);
        float vignette = 1.0 - smoothstep(0.3, 0.9, vignetteDist) * vignetteStrength;

        float warmAmount = smoothstep(0.4, 0.8, attentionLevel);
        float3 warmTint  = float3(1.05, 1.0, 0.9);
        float3 coolTint  = float3(0.9, 0.95, 1.1);
        float3 colorTemp = mix(coolTint, warmTint, warmAmount);

        float edgeGlow = 0.0;
        if (attentionLevel > 0.7) {
            float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
            float glowIntensity = (attentionLevel - 0.7) / 0.3;
            edgeGlow = smoothstep(0.15, 0.0, edgeDist) * glowIntensity * 0.1;
        }

        resultColor = colorTemp * vignette;
        resultColor += float3(0.85, 0.86, 0.22) * edgeGlow;
        alpha = mix(0.4, 0.05, attentionLevel) * smoothstep(0.3, 0.8, vignetteDist);
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 1: L1 — Ripple rings when focused
    // ═══════════════════════════════════════════
    case 1: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        float focusStrength = smoothstep(0.6, 0.9, attentionLevel);
        float ripple = sin(dist * 30.0 - time * 4.0) * smoothstep(0.8, 0.6, dist);
        ripple = max(ripple, 0.0) * focusStrength;

        float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        float edgeGlow = smoothstep(0.10, 0.0, edgeDist) * 0.05 * focusStrength;

        resultColor = float3(0.78, 0.92, 0.58) * ripple * 0.28
                    + float3(0.34, 0.52, 0.62) * edgeGlow;
        alpha = ripple * 0.18 + edgeGlow;
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 2: L2 — Fog clears when focused
    // ═══════════════════════════════════════════
    case 2: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        // Fog density INVERSELY proportional to attention
        // Focused → less fog, distracted → thick fog
        float fogAmount = mix(config.fogDensity, 0.0, attentionLevel);
        // Fog thins with height
        fogAmount *= exp(-uv.y * config.fogHeightFalloff);
        fogAmount = clamp(fogAmount, 0.0, 1.0);

        resultColor = config.fogColor.rgb;
        alpha = fogAmount * 0.7;

        // Vignette when distracted
        float vignette = smoothstep(0.3, 0.9, dist) * mix(0.5, 0.1, attentionLevel);
        alpha += vignette * 0.3;
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 3: L3 — Star brightening when focused
    // ═══════════════════════════════════════════
    case 3: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        // Brighten screen edges when focused (stars more visible)
        float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
        float edgeBright = smoothstep(0.3, 0.0, edgeDist) * attentionLevel * 0.15;

        // Subtle star-field brightening
        float brightBoost = 1.0 + attentionLevel * 0.3;
        resultColor = float3(0.7, 0.8, 1.0) * edgeBright * brightBoost;

        // Cool vignette when distracted
        float vignette = smoothstep(0.3, 0.9, dist) * mix(0.4, 0.05, attentionLevel);
        resultColor += float3(0.1, 0.12, 0.2) * vignette;

        alpha = edgeBright * 0.3 + vignette * 0.4;
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 4: L4 — Warm glow at tree of life
    // ═══════════════════════════════════════════
    case 4: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        // Warm glow at bottom center (tree of life position)
        float2 treePos = float2(config.treeOfLifeX + 0.5, 0.2);
        float treeDist = length(uv - treePos);
        float glowRadius = 0.25 + attentionLevel * 0.1;
        float treeGlow = exp(-treeDist * treeDist / (glowRadius * glowRadius)) * attentionLevel;

        // Green-gold color
        float3 glowColor = mix(float3(0.1, 0.2, 0.02), float3(0.4, 0.35, 0.05), attentionLevel);
        resultColor = glowColor * treeGlow;

        // Vignette when distracted
        float vignette = smoothstep(0.3, 0.9, dist) * mix(0.4, 0.05, attentionLevel);
        resultColor += float3(0.05, 0.05, 0.02) * vignette;

        alpha = treeGlow * 0.3 + vignette * 0.3;
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 5: L5 — Flight smoothing / screen shake
    // ═══════════════════════════════════════════
    case 5: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        // When distracted: heavy vignette + screen shake effect
        float shake = (1.0 - attentionLevel) * 0.01;
        float2 shakeOffset = float2(sin(time * 20.0), cos(time * 15.0)) * shake;
        float2 shakenUV = uv + shakeOffset;

        // Re-compute distance with shake
        float2 shakenCenter = shakenUV - float2(0.5);
        float shakenDist = length(shakenCenter);

        float vignetteStrength = mix(0.7, 0.1, attentionLevel);
        float vignette = 1.0 - smoothstep(0.2, 0.85, shakenDist) * vignetteStrength;

        resultColor = float3(vignette);

        // Storm tint when distracted
        resultColor = mix(resultColor, float3(0.85, 0.82, 0.9), (1.0 - attentionLevel) * 0.1);

        alpha = mix(0.5, 0.05, attentionLevel) * smoothstep(0.2, 0.85, dist);
        break;
    }

    // ═══════════════════════════════════════════
    // Mode 6: L6 — Moon cracks / moon glow
    // ═══════════════════════════════════════════
    case 6: {
        float2 center = uv - float2(0.5);
        float dist = length(center);

        // Moon glow proportional to attention
        float2 moonPos = float2(0.5, 0.82);
        float moonDist = length(uv - moonPos);
        float moonGlow = exp(-moonDist * moonDist * 30.0) * attentionLevel * 0.3;

        resultColor = float3(0.5, 0.55, 0.7) * moonGlow;

        // Cracks when distracted (Voronoi-like pattern near moon)
        if (attentionLevel < 0.7) {
            float crackStrength = (1.0 - attentionLevel) * 0.5;
            // Simple crack pattern using distance to hash grid
            float2 crackUV = (uv - moonPos) * 20.0;
            float2 cellID = floor(crackUV);
            float2 cellUV = fract(crackUV);
            float minDist = 1.0;
            for (int cx = -1; cx <= 1; cx++) {
                for (int cy = -1; cy <= 1; cy++) {
                    float2 neighbor = float2(float(cx), float(cy));
                    float2 neighborPos = hash2(cellID + neighbor);
                    float d = length(cellUV - neighbor - neighborPos);
                    minDist = min(minDist, d);
                }
            }
            float crackLine = smoothstep(0.05, 0.0, minDist) * crackStrength;
            // Only show cracks near moon area
            float moonMask = exp(-moonDist * moonDist * 80.0);
            resultColor += float3(0.3, 0.2, 0.15) * crackLine * moonMask;
        }

        // Vignette
        float vignette = smoothstep(0.3, 0.9, dist) * mix(0.5, 0.1, attentionLevel);
        alpha = moonGlow * 0.4 + vignette * 0.3;

        // Heal overlay when focused
        if (attentionLevel > 0.7) {
            float healGlow = (attentionLevel - 0.7) / 0.3 * exp(-moonDist * moonDist * 50.0) * 0.15;
            resultColor += float3(0.6, 0.65, 0.8) * healGlow;
            alpha += healGlow * 0.3;
        }
        break;
    }

    } // end switch

    return float4(resultColor, alpha);
}
