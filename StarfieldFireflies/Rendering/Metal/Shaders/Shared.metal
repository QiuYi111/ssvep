//
//  Shared.metal
//  StarfieldFireflies
//
//  Shared types and constants for all Metal shaders.
//  Buffer indices must match BufferIndex enum in MetalEngine.swift.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Common Utility Functions

inline float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float2 hash2(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return float2((p3.x + p3.y) * p3.z, (p3.y + p3.z) * p3.x);
}

// MARK: - Buffer Index Constants

constant int kBufferVertices    = 0;
constant int kBufferUniforms   = 1;
constant int kBufferSSVEP      = 2;
constant int kBufferParticles  = 3;
constant int kBufferAttention  = 4;
constant int kBufferLevelConfig = 5;
constant int kBufferNoise      = 6;

// MARK: - Scene Uniforms (matches UniformBufferManager Swift-side layout)

struct SceneUniforms {
    float4x4 viewProjectionMatrix;
    float4x4 inverseViewProjection;
    packed_float3 cameraPosition;
    float    time;
    float    deltaTime;
    packed_float2 resolution;
    packed_float2 mousePosition;
};

// MARK: - Particle (64 bytes, GPU-aligned)

struct Particle {
    packed_float2 position;      // offset 0:  world space [meters]
    packed_float2 velocity;      // offset 8:  velocity [m/s]
    float         life;          // offset 16: [0 = born, 1 = dead]
    float         maxLife;       // offset 20: max lifetime [seconds]
    packed_float3 color;         // offset 24: RGB
    float         brightness;    // offset 36: [0, 1]
    float         size;          // offset 40: screen-space radius [pixels]
    float         phase;         // offset 44: Perlin noise phase offset
    float         noiseScale;    // offset 48: noise scale factor
    int           ssvepChannel;  // offset 52: -1=none, 0=target, 1=distractor, 2=advanced
    int           type;          // offset 56: 0=firefly, 1=star, 2=leaf, 3=rain
    float         _pad;          // offset 60: alignment padding
};
// Total: 64 bytes ✅

// MARK: - SSVEP Parameters (matches SSVEPParamsMetal in SSVEPController.swift)

struct SSVEPParams {
    float   targetOpacity;
    float   distractorOpacity;
    float   advancedOpacity;
    float   attentionLevel;
    float   deltaTime;
    float   guidingPulse;
    float   riftMode;
    float   _alignPad;
    uint64_t frameIndex;
    float   padding;
};

// MARK: - Attention State (matches AttentionStateMetal in SSVEPController.swift)

struct AttentionState {
    float level;                 // [0, 1] current attention
    float targetPositionX;       // attention focus target
    float targetPositionY;
    float transitionSpeed;       // state transition speed
};

// MARK: - Level Scene Configuration (matches LevelSceneConfigMetal in Swift)

struct LevelSceneConfig {
    float4 themeColor;          // 16 bytes each
    float4 secondaryColor;
    float4 distractorColor;
    float4 backgroundColor;
    float4 fogColor;

    float skyGradientTopY;
    float skyGradientBottomY;
    float mountainHeight;
    float mountainSmoothness;

    float waterLevel;
    float waterWaveAmplitude;
    float waterWaveFrequency;

    float fogDensity;
    float fogHeightFalloff;
    float starBrightness;
    float starDensity;

    float lotusSize;
    float lotusPetalCount;

    float monumentX;
    float monumentY;

    float treeOfLifeGrowth;
    float treeOfLifeX;

    float swallowPosX;
    float swallowPosY;

    float lightningIntensity;
    float moonPhase;
    float snowPeakHeight;

    int   sceneMode;            // 0=starfield, 1=lake(L1), 2=forest(L2), 3=constellation(L3), 4=dualForest(L4), 5=storm(L5), 6=mountain(L6)
    int   particleBehaviorMode; // 0=float, 1=guided, 2=orbital, 3=scatter, 4=rain, 5=meteor
    int   attentionEffectMode;  // 0=default, 1=ripples, 2=fog, 3=constellate, 4=grow, 5=flight, 6=resist

    float bloomTintR;
    float bloomTintG;
    float bloomTintB;

    float _pad[15];
};

// MARK: - Common Vertex Output

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Background Vertex I/O

struct BackgroundVertexIn {
    float3 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct BackgroundFragmentIn {
    float4 position [[position]];
    float2 uv;
};

// MARK: - Particle Render Vertex Output

struct ParticleFragmentIn {
    float4 position   [[position]];
    float2 uv;                   // particle local UV [0, 1]
    float3 color;
    float  brightness;
    float  size;
    int    ssvepChannel;
};
