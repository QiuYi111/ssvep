import MetalKit
import AppKit

extension MTKView {

    func configureForProMotion() {
        preferredFramesPerSecond = 120

        enableSetNeedsDisplay = false
        isPaused = false

        if let device = device, device.supportsFamily(.apple7) {
            colorPixelFormat = .bgr10a2Unorm
        } else {
            colorPixelFormat = .bgra8Unorm
        }

        sampleCount = 4
        depthStencilPixelFormat = .depth32Float

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        drawableSize = CGSize(
            width: bounds.width * scaleFactor,
            height: bounds.height * scaleFactor
        )

        framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }

    func updateDrawableSize() {
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        drawableSize = CGSize(
            width: bounds.width * scaleFactor,
            height: bounds.height * scaleFactor
        )
    }
}
