//
//  MetalView.swift
//  StarfieldFireflies
//
//  NSViewRepresentable wrapping MTKView for macOS 14+.
//  Configures ProMotion 80–120Hz, .bgra8Unorm, continuous rendering.
//

import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {

    var renderer: MetalRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MetalEngine.shared.device
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = 1
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }
}

#if DEBUG
#Preview {
    MetalView(renderer: MetalRenderer())
        .frame(width: 800, height: 600)
}
#endif
