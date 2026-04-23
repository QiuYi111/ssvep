import Foundation
import QuartzCore
import Metal

final class PerformanceMonitor {

    struct FrameStats {
        var fps: Int = 0
        var frameTimeMS: Double = 0
        var minFrameTimeMS: Double = .infinity
        var maxFrameTimeMS: Double = 0
        var averageFrameTimeMS: Double = 0
    }

    private(set) var stats = FrameStats()

    private var frameTimestamps: [CFTimeInterval] = []
    private let maxFrameHistory = 120
    private var lastDrawTime: CFTimeInterval = 0
    private var frameTimes: [Double] = []
    private let maxFrameTimeHistory = 600

    var isRunningAt120fps: Bool {
        stats.fps >= 115
    }

    func recordFrame() {
        let now = CACurrentMediaTime()

        if lastDrawTime > 0 {
            let delta = (now - lastDrawTime) * 1000.0
            stats.frameTimeMS = delta

            frameTimes.append(delta)
            if frameTimes.count > maxFrameTimeHistory {
                frameTimes.removeFirst()
            }

            stats.minFrameTimeMS = frameTimes.min() ?? 0
            stats.maxFrameTimeMS = frameTimes.max() ?? 0
            stats.averageFrameTimeMS = frameTimes.reduce(0, +) / Double(frameTimes.count)
        }
        lastDrawTime = now

        frameTimestamps.append(now)
        if frameTimestamps.count > maxFrameHistory {
            frameTimestamps.removeFirst()
        }

        if frameTimestamps.count >= 2 {
            let elapsed = frameTimestamps.last! - frameTimestamps.first!
            if elapsed > 0 {
                stats.fps = Int(Double(frameTimestamps.count - 1) / elapsed)
            }
        }
    }

    func recordGPUTime(_ gpuTimeMS: Double) {
        // For use with MTLCommandBuffer.addCompletedHandler when GPU timing is available
        // Stored but not yet exposed; will be used in MetalRenderer integration
    }

    func reset() {
        stats = FrameStats()
        frameTimestamps.removeAll()
        frameTimes.removeAll()
        lastDrawTime = 0
    }
}
