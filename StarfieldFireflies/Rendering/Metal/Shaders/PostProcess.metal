//
//  PostProcess.metal
//  StarfieldFireflies
//
//  Bloom post-processing pipeline:
//  1. bloomExtract  — extract bright pixels above threshold (compute)
//  2. blurHorizontal / blurVertical — separable 9-tap Gaussian (compute)
//  3. bloomComposite — additive blend of multi-level bloom (render)
//

#include <metal_stdlib>
using namespace metal;
#include "Shared.metal"

// ═══════════════════════════════════════════════════════════════
// MARK: - Bloom Extract (Compute)
// ═══════════════════════════════════════════════════════════════

kernel void bloomExtract(
    texture2d<float, access::read>  source    [[texture(0)]],
    texture2d<float, access::write> dest      [[texture(1)]],
    constant float& threshold                [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    // Source may be larger — sample at destination coordinates
    uint2 srcCoord = gid * uint2(source.get_width() / dest.get_width(),
                                  source.get_height() / dest.get_height());
    srcCoord = min(srcCoord, uint2(source.get_width() - 1, source.get_height() - 1));

    float4 color = source.read(srcCoord);

    // Luminance (Rec.709)
    float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));

    // Soft threshold: smooth transition rather than hard cutoff
    float contribution = smoothstep(threshold, threshold + 0.3, luminance);

    dest.write(float4(color.rgb * contribution, 1.0), gid);
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Gaussian Blur Horizontal (Compute)
// ═══════════════════════════════════════════════════════════════

kernel void blurHorizontal(
    texture2d<float, access::read>  source  [[texture(0)]],
    texture2d<float, access::write> dest    [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    // 9-tap Gaussian weights (σ ≈ 2.0), sum ≈ 1.0
    float w0 = 0.2270, w1 = 0.1945, w2 = 0.1216, w3 = 0.0540, w4 = 0.0162;

    float4 result = source.read(gid) * w0;
    result += source.read(uint2(clamp(int(gid.x) - 1, 0, int(source.get_width()) - 1), gid.y)) * w1;
    result += source.read(uint2(clamp(int(gid.x) + 1, 0, int(source.get_width()) - 1), gid.y)) * w1;
    result += source.read(uint2(clamp(int(gid.x) - 2, 0, int(source.get_width()) - 1), gid.y)) * w2;
    result += source.read(uint2(clamp(int(gid.x) + 2, 0, int(source.get_width()) - 1), gid.y)) * w2;
    result += source.read(uint2(clamp(int(gid.x) - 3, 0, int(source.get_width()) - 1), gid.y)) * w3;
    result += source.read(uint2(clamp(int(gid.x) + 3, 0, int(source.get_width()) - 1), gid.y)) * w3;
    result += source.read(uint2(clamp(int(gid.x) - 4, 0, int(source.get_width()) - 1), gid.y)) * w4;
    result += source.read(uint2(clamp(int(gid.x) + 4, 0, int(source.get_width()) - 1), gid.y)) * w4;

    dest.write(result, gid);
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Gaussian Blur Vertical (Compute)
// ═══════════════════════════════════════════════════════════════

kernel void blurVertical(
    texture2d<float, access::read>  source  [[texture(0)]],
    texture2d<float, access::write> dest    [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    // 9-tap Gaussian weights (σ ≈ 2.0), sum ≈ 1.0
    float w0 = 0.2270, w1 = 0.1945, w2 = 0.1216, w3 = 0.0540, w4 = 0.0162;

    float4 result = source.read(gid) * w0;
    result += source.read(uint2(gid.x, clamp(int(gid.y) - 1, 0, int(source.get_height()) - 1))) * w1;
    result += source.read(uint2(gid.x, clamp(int(gid.y) + 1, 0, int(source.get_height()) - 1))) * w1;
    result += source.read(uint2(gid.x, clamp(int(gid.y) - 2, 0, int(source.get_height()) - 1))) * w2;
    result += source.read(uint2(gid.x, clamp(int(gid.y) + 2, 0, int(source.get_height()) - 1))) * w2;
    result += source.read(uint2(gid.x, clamp(int(gid.y) - 3, 0, int(source.get_height()) - 1))) * w3;
    result += source.read(uint2(gid.x, clamp(int(gid.y) + 3, 0, int(source.get_height()) - 1))) * w3;
    result += source.read(uint2(gid.x, clamp(int(gid.y) - 4, 0, int(source.get_height()) - 1))) * w4;
    result += source.read(uint2(gid.x, clamp(int(gid.y) + 4, 0, int(source.get_height()) - 1))) * w4;

    dest.write(result, gid);
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Bloom Composite Vertex Shader
// ═══════════════════════════════════════════════════════════════

vertex VertexOut bloomCompositeVertex(
    uint vid [[vertex_id]],
    constant float* vertexData [[buffer(kBufferVertices)]]
) {
    VertexOut out;
    float2 pos = float2(vertexData[vid * 4], vertexData[vid * 4 + 1]);
    float2 uv  = float2(vertexData[vid * 4 + 2], vertexData[vid * 4 + 3]);
    out.position = float4(pos, 0.0, 1.0);
    out.uv = uv;
    return out;
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Bloom Composite Fragment Shader
// ═══════════════════════════════════════════════════════════════

fragment float4 bloomCompositeFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sceneTexture [[texture(0)]],
    texture2d<float, access::sample> bloomHalf    [[texture(1)]],
    texture2d<float, access::sample> bloomQuarter [[texture(2)]],
    texture2d<float, access::sample> bloomEighth  [[texture(3)]],
    constant float& bloomIntensity [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;

    float4 scene = sceneTexture.sample(linearSampler, uv);

    float4 halfBloom    = bloomHalf.sample(linearSampler, uv)    * 0.5;
    float4 quarterBloom = bloomQuarter.sample(linearSampler, uv) * 0.3;
    float4 eighthBloom  = bloomEighth.sample(linearSampler, uv)  * 0.2;

    float4 totalBloom = (halfBloom + quarterBloom + eighthBloom) * bloomIntensity;
    totalBloom.rgb = min(totalBloom.rgb, float3(2.0));

    return float4(scene.rgb + totalBloom.rgb, 1.0);
}

// ═══════════════════════════════════════════════════════════════
// MARK: - ACES Tone Mapping (utility)
// ═══════════════════════════════════════════════════════════════

float3 ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}
