//
//  Firefly.metal
//  StarfieldFireflies
//
//  Particle simulation (compute shader) and rendering (vertex + fragment).
//  Particle struct is 64 bytes, defined in Shared.metal.
//

#include <metal_stdlib>
using namespace metal;
#include "Shared.metal"

// ── Noise functions (hash from Shared.metal) ──

float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // smoothstep

    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Particle respawn ──

void respawnParticle(device Particle& p, constant SceneUniforms& uniforms, float time) {
    p.life = 0.0;
    p.maxLife = 3.0 + hash(float2(p.phase, time)) * 5.0;  // 3–8 seconds

    // Random position in world space [-1, 1] × [-0.7, 0.7]
    p.position = float2(
        (hash(float2(p.phase * 1.1, time * 0.1)) - 0.5) * 2.0,
        (hash(float2(p.phase * 0.7, time * 0.3)) - 0.5) * 1.4
    );

    p.velocity = float2(0.0);
    p.brightness = 0.0;  // fade in from 0
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Particle Compute Shader (simulation)
// ═══════════════════════════════════════════════════════════════

kernel void simulateParticles(
    device Particle* particles         [[buffer(0)]],
    constant uint&    particleCount    [[buffer(1)]],
    constant SceneUniforms& uniforms   [[buffer(2)]],
    constant SSVEPParams& ssvep        [[buffer(3)]],
    constant AttentionState& attention [[buffer(4)]],
    constant LevelSceneConfig& config  [[buffer(5)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= particleCount) return;

    device Particle& p = particles[id];
    float dt = uniforms.deltaTime;
    float time = uniforms.time;

    // ──── 1. Life cycle ────
    p.life += dt / p.maxLife;

    if (p.life >= 1.0) {
        respawnParticle(p, uniforms, time);
        // Rain type: respawn at top
        if (p.type == 3) {
            p.position = float2(p.position[0], 0.7);
            p.velocity = float2(0.0);
        }
        return;
    }

    // Fade in/out curve
    float lifeAlpha = smoothstep(0.0, 0.1, p.life) * smoothstep(1.0, 0.8, p.life);
    p.brightness = lifeAlpha;

    // ──── 2. Per-type movement behavior ────

    if (p.type == 1) {
        // Star: nearly stationary, very slow drift
        float2 noiseCoord = float2(p.position) * p.noiseScale + float2(p.phase, p.phase * 0.7);
        float2 noiseForce = float2(
            noise2D(noiseCoord + float2(time * 0.3, 0.0)),
            noise2D(noiseCoord + float2(0.0, time * 0.3))
        ) * 2.0 - 1.0;
        float2 noiseAcceleration = noiseForce * 0.05;

        p.velocity = float2(
            float2(p.velocity).x + noiseAcceleration.x * dt,
            float2(p.velocity).y + noiseAcceleration.y * dt
        );
        p.velocity = float2(float2(p.velocity).x * 0.99, float2(p.velocity).y * 0.99);

    } else if (p.type == 2) {
        // Leaf: downward gravity + lateral sway
        float2 noiseCoord = float2(p.position) * p.noiseScale + float2(p.phase, p.phase * 0.7);
        float lateralSway = noise2D(noiseCoord + float2(time * 0.5, 0.0)) * 2.0 - 1.0;

        p.velocity = float2(
            float2(p.velocity).x + lateralSway * 0.3 * dt,
            float2(p.velocity).y - 0.05 * dt
        );
        p.velocity = float2(float2(p.velocity).x * 0.97, float2(p.velocity).y * 0.97);

    } else if (p.type == 3) {
        // Rain: constant downward velocity
        p.velocity = float2(float2(p.velocity).x * 0.98, -0.3);

    } else {
        // Default firefly (type 0): noise wandering + attention gather
        float2 noiseCoord = float2(p.position) * p.noiseScale + float2(p.phase, p.phase * 0.7);
        float2 noiseForce = float2(
            noise2D(noiseCoord + float2(time * 0.3, 0.0)),
            noise2D(noiseCoord + float2(0.0, time * 0.3))
        ) * 2.0 - 1.0;
        float2 noiseAcceleration = noiseForce * 0.5;

        float2 attentionForce = float2(0.0);
        float2 attentionTarget = float2(attention.targetPositionX, attention.targetPositionY);

        if (p.ssvepChannel == 0) {
            float2 toTarget = attentionTarget - float2(p.position);
            float distToTarget = length(toTarget);
            float2 direction = distToTarget > 0.001 ? normalize(toTarget) : float2(0.0);

            float gatherStrength  = attention.level * 2.0;
            float scatterStrength = (1.0 - attention.level) * 1.5;

            attentionForce = direction * gatherStrength - direction * scatterStrength;

            float idealDist = 0.15;
            float distFactor = smoothstep(0.0, idealDist, distToTarget);
            attentionForce *= distFactor;
        }

        p.velocity = float2(
            float2(p.velocity).x + (noiseAcceleration.x + attentionForce.x) * dt,
            float2(p.velocity).y + (noiseAcceleration.y + attentionForce.y) * dt
        );
        p.velocity = float2(float2(p.velocity).x * 0.95, float2(p.velocity).y * 0.95);
    }

    // ──── 4. Speed limit ────
    float speed = length(float2(p.velocity));
    float maxSpeed = (p.type == 3) ? 0.5 : 0.5;
    if (speed > maxSpeed) {
        p.velocity = float2(float2(p.velocity).x / speed * maxSpeed, float2(p.velocity).y / speed * maxSpeed);
    }

    // ──── 5. Position update ────
    p.position = float2(
        float2(p.position).x + float2(p.velocity).x * dt,
        float2(p.position).y + float2(p.velocity).y * dt
    );

    // ──── 6. Soft boundary (skip for rain — wraps vertically) ────
    if (p.type == 3) {
        float2 bounds = float2(1.0, 0.7);
        if (float2(p.position).x < -bounds.x) {
            p.position = float2(bounds.x, float2(p.position).y);
        } else if (float2(p.position).x > bounds.x) {
            p.position = float2(-bounds.x, float2(p.position).y);
        }
        if (float2(p.position).y < -bounds.y) {
            respawnParticle(p, uniforms, time);
            p.position = float2(p.position[0], 0.7);
            p.velocity = float2(0.0, -0.3);
            return;
        }
    } else {
        float2 bounds = float2(1.0, 0.7);
        float margin = 0.1;

        if (float2(p.position).x < -bounds.x + margin) {
            p.velocity = float2(float2(p.velocity).x + 0.1 * dt, float2(p.velocity).y);
        } else if (float2(p.position).x > bounds.x - margin) {
            p.velocity = float2(float2(p.velocity).x - 0.1 * dt, float2(p.velocity).y);
        }
        if (float2(p.position).y < -bounds.y + margin) {
            p.velocity = float2(float2(p.velocity).x, float2(p.velocity).y + 0.1 * dt);
        } else if (float2(p.position).y > bounds.y - margin) {
            p.velocity = float2(float2(p.velocity).x, float2(p.velocity).y - 0.1 * dt);
        }
    }

    // ──── 7. Natural brightness flicker ────
    float flicker = noise2D(float2(time * 3.0, p.phase)) * 0.3 + 0.7;
    p.brightness *= flicker;
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Particle Vertex Shader (point-sprite billboard)
// ═══════════════════════════════════════════════════════════════

vertex ParticleFragmentIn particleVertex(
    uint vid [[vertex_id]],
    uint pid [[instance_id]],
    device Particle* particles [[buffer(0)]],
    constant SceneUniforms& uniforms [[buffer(kBufferUniforms)]]
) {
    ParticleFragmentIn out;

    device Particle& p = particles[pid];

    // Billboard quad: 4 vertices per instance (triangle strip)
    // vid 0,1,2,3 → left-bottom, right-bottom, left-top, right-top
    float2 quadOffsets[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    float2 offset = quadOffsets[vid] * p.size;

    // Project to screen space
    float4 worldPos = float4(float2(p.position), 0.0, 1.0);
    float4 screenPos = uniforms.viewProjectionMatrix * worldPos;

    // Pixel-space offset scaled to clip space
    float2 pixelOffset = offset / uniforms.resolution * 2.0;
    screenPos.xy += pixelOffset * screenPos.w;

    out.position     = screenPos;
    out.uv           = (quadOffsets[vid] + 1.0) * 0.5;  // [0, 1]
    out.color        = float3(p.color);
    out.brightness   = p.brightness;
    out.size         = p.size;
    out.ssvepChannel = p.ssvepChannel;

    return out;
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Particle Fragment Shader (soft glow circle + SSVEP)
// ═══════════════════════════════════════════════════════════════

fragment float4 particleFragment(
    ParticleFragmentIn in [[stage_in]],
    constant SSVEPParams& ssvep [[buffer(kBufferSSVEP)]],
    constant AttentionState& attention [[buffer(kBufferAttention)]],
    constant LevelSceneConfig& config [[buffer(kBufferLevelConfig)]]
) {
    float4 baseColor = float4(in.color, in.brightness);

    float dist = length(in.uv - float2(0.5));
    float softCircle = smoothstep(0.5, 0.15, dist);
    baseColor.a *= softCircle;

    float ssvepOpacity = 1.0;
    if (in.ssvepChannel == 0) {
        ssvepOpacity = ssvep.targetOpacity;
    } else if (in.ssvepChannel == 1) {
        ssvepOpacity = ssvep.distractorOpacity;
    } else if (in.ssvepChannel == 2) {
        ssvepOpacity = ssvep.advancedOpacity;
    }
    baseColor.a *= ssvepOpacity;

    float attentionBoost = mix(0.6, 1.0, attention.level);
    baseColor.rgb *= attentionBoost;

    // Per-channel color tinting from level config
    if (in.ssvepChannel == 0) {
        baseColor.rgb = mix(baseColor.rgb, config.themeColor.rgb, 0.3);
    } else if (in.ssvepChannel == 1) {
        baseColor.rgb = mix(baseColor.rgb, config.distractorColor.rgb, 0.3);
    }

    return baseColor;
}
