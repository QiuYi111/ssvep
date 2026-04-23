//
//  UniformBufferManager.swift
//  StarfieldFireflies
//
//  Triple-buffered SceneUniforms with 256-byte alignment.
//  Matches SceneUniforms struct in Shared.metal exactly.
//

import Metal
import simd

// MARK: - Scene Uniforms (Swift-side, matches Shared.metal)

struct SceneUniformsSwift {
    var viewProjectionMatrix: simd_float4x4
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD3<Float>
    var time: Float
    var deltaTime: Float
    var resolution: SIMD2<Float>
    var mousePosition: SIMD2<Float>
}

// MARK: - UniformBufferManager

final class UniformBufferManager {

    let buffer: MTLBuffer
    private let tripleBufferCount: Int
    private let alignedSize: Int

    init(device: MTLDevice, tripleBufferCount: Int) {
        self.tripleBufferCount = tripleBufferCount
        self.alignedSize = ((MemoryLayout<SceneUniformsSwift>.stride + 255) / 256) * 256

        let totalSize = alignedSize * tripleBufferCount
        self.buffer = device.makeBuffer(length: totalSize, options: .storageModeShared)!
        self.buffer.label = "UniformBuffer_Triple"
    }

    // MARK: - Offset for triple buffering

    func alignedOffset(for bufferIndex: Int) -> Int {
        return (bufferIndex % tripleBufferCount) * alignedSize
    }

    // MARK: - Update per frame

    func update(
        bufferIndex: Int,
        viewProjection: simd_float4x4,
        inverseViewProjection: simd_float4x4,
        cameraPosition: SIMD3<Float>,
        time: Float,
        deltaTime: Float,
        resolution: SIMD2<Float>,
        mousePosition: SIMD2<Float>
    ) {
        let offset = alignedOffset(for: bufferIndex)

        var uniforms = SceneUniformsSwift(
            viewProjectionMatrix: viewProjection,
            inverseViewProjection: inverseViewProjection,
            cameraPosition: cameraPosition,
            time: time,
            deltaTime: deltaTime,
            resolution: resolution,
            mousePosition: mousePosition
        )

        memcpy(buffer.contents() + offset, &uniforms, MemoryLayout<SceneUniformsSwift>.size)
    }
}
