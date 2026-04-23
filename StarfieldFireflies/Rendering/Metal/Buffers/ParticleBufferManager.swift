//
//  ParticleBufferManager.swift
//  StarfieldFireflies
//
//  Manages triple-buffered MTLBuffer for up to 10,000 particles.
//  Particle struct is 64 bytes, matching Shared.metal layout exactly.
//

import Metal
import Foundation
import simd

struct ParticleSwift {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var maxLife: Float
    var colorR: Float
    var colorG: Float
    var colorB: Float
    var brightness: Float
    var size: Float
    var phase: Float
    var noiseScale: Float
    var ssvepChannel: Int32
    var type: Int32
    var _pad: Float
}

// MARK: - ParticleBufferManager

final class ParticleBufferManager {

    let buffer: MTLBuffer
    private let maxParticleCount: Int
    private let tripleBufferCount: Int
    private(set) var activeParticleCount: Int

    private let alignedParticleStride: Int
    private let singleBufferSize: Int

    init(device: MTLDevice, maxParticleCount: Int, tripleBufferCount: Int) {
        assert(MemoryLayout<ParticleSwift>.stride == 64, "Particle struct must be 64 bytes for GPU alignment")

        self.maxParticleCount = maxParticleCount
        self.tripleBufferCount = tripleBufferCount
        self.activeParticleCount = maxParticleCount

        let particleStride = MemoryLayout<ParticleSwift>.stride
        // Align each particle buffer to 256 bytes for Metal buffer offset alignment
        self.alignedParticleStride = ((particleStride * maxParticleCount + 255) / 256) * 256
        self.singleBufferSize = alignedParticleStride

        let totalSize = singleBufferSize * tripleBufferCount
        self.buffer = device.makeBuffer(length: totalSize, options: .storageModeShared)!
        self.buffer.label = "ParticleBuffer_Triple"

        // Initialize with default particles
        initializeForLevel(1)
    }

    // MARK: - Offset for triple buffering

    func alignedOffset(for bufferIndex: Int) -> Int {
        return (bufferIndex % tripleBufferCount) * singleBufferSize
    }

    // MARK: - Level initialization

    func initializeForLevel(_ level: Int) {
        // Per-level particle counts (from implementation plan §2.4.2)
        let configs: [(firefly: Int, star: Int, other: Int)] = [
            (500, 200, 1000),    // Level 1: 涟漪绽放 — 1700 total
            (5000, 300, 500),    // Level 2: 萤火引路 — 5800 total
            (200, 5000, 300),    // Level 3: 星图寻迹 — 5500 total
            (3000, 200, 500),    // Level 4: 真假萤火 — 3700 (green)
            (1000, 100, 2000),   // Level 5: 飞燕破云 — 3100 total
            (500, 8000, 500),    // Level 6: 流星试炼 — 9000 total
        ]

        let configIndex = max(0, min(level - 1, configs.count - 1))
        let config = configs[configIndex]
        activeParticleCount = min(config.firefly + config.star + config.other, maxParticleCount)

        // Fill all triple buffers with initial particle data
        for bufIdx in 0..<tripleBufferCount {
            let offset = alignedOffset(for: bufIdx)
            let ptr = buffer.contents() + offset

            var particles = [ParticleSwift]()
            particles.reserveCapacity(activeParticleCount)

            // Per-level colors
            let fireflyR: Float = 0.804; let fireflyG: Float = 0.863; let fireflyB: Float = 0.224
            let starR: Float = 0.541;    let starG: Float = 0.706;    let starB: Float = 0.973
            let distractorR: Float = 0.392; let distractorG: Float = 0.710; let distractorB: Float = 0.965

            for _ in 0..<config.firefly {
                var p = ParticleSwift(
                    position: SIMD2<Float>(
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -0.7...0.7)
                    ),
                    velocity: .zero,
                    life: Float.random(in: 0.0...0.8),
                    maxLife: Float.random(in: 3.0...8.0),
                    colorR: fireflyR,
                    colorG: fireflyG,
                    colorB: fireflyB,
                    brightness: Float.random(in: 0.3...1.0),
                    size: Float.random(in: 3.0...8.0),
                    phase: Float.random(in: 0...Float.pi * 2),
                    noiseScale: Float.random(in: 0.5...2.0),
                    ssvepChannel: 0,
                    type: 0,
                    _pad: 0
                )
                particles.append(p)
            }

            for _ in 0..<config.star {
                let p = ParticleSwift(
                    position: SIMD2<Float>(
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -0.7...0.7)
                    ),
                    velocity: .zero,
                    life: Float.random(in: 0.0...0.8),
                    maxLife: Float.random(in: 5.0...15.0),
                    colorR: starR,
                    colorG: starG,
                    colorB: starB,
                    brightness: Float.random(in: 0.1...0.5),
                    size: Float.random(in: 1.0...3.0),
                    phase: Float.random(in: 0...Float.pi * 2),
                    noiseScale: Float.random(in: 0.1...0.5),
                    ssvepChannel: level >= 3 ? 1 : -1,
                    type: 1,
                    _pad: 0
                )
                particles.append(p)
            }

            for _ in 0..<config.other {
                let oR = Float.random(in: 0.3...0.6)
                let oG = Float.random(in: 0.4...0.7)
                let oB = Float.random(in: 0.3...0.5)
                let p = ParticleSwift(
                    position: SIMD2<Float>(
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -0.7...0.7)
                    ),
                    velocity: SIMD2<Float>(
                        Float.random(in: -0.1...0.1),
                        level == 5 ? Float.random(in: -0.3...(-0.1)) : Float.random(in: -0.1...0.1)
                    ),
                    life: Float.random(in: 0.0...0.8),
                    maxLife: Float.random(in: 2.0...6.0),
                    colorR: oR,
                    colorG: oG,
                    colorB: oB,
                    brightness: Float.random(in: 0.1...0.4),
                    size: Float.random(in: 1.0...4.0),
                    phase: Float.random(in: 0...Float.pi * 2),
                    noiseScale: Float.random(in: 0.3...1.5),
                    ssvepChannel: -1,
                    type: level == 5 ? 3 : 2,
                    _pad: 0
                )
                particles.append(p)
            }

            // Copy to buffer
            particles.withUnsafeBufferPointer { ptrToParticles in
                memcpy(ptr, ptrToParticles.baseAddress!, particles.count * MemoryLayout<ParticleSwift>.stride)
            }
        }
    }
}
