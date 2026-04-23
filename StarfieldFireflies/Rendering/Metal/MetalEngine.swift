import Metal
import MetalKit
import Foundation

// MARK: - Buffer Index Convention (shared with shaders)
enum BufferIndex: Int {
    case vertices    = 0
    case uniforms    = 1
    case ssvep       = 2
    case particles   = 3
    case attention   = 4
    case levelConfig = 5
    case noise       = 6
}

// MARK: - MetalEngine Singleton
final class MetalEngine {

    static let shared = MetalEngine()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    private var renderPipelineCache: [String: MTLRenderPipelineState] = [:]
    private var computePipelineCache: [String: MTLComputePipelineState] = [:]
    private let cacheLock = NSLock()

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let queue = device.makeCommandQueue(maxCommandBufferCount: 3) else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue
        queue.label = "StarfieldFireflies.MainQueue"

        print("[MetalEngine] Device: \(device.name)")
        print("[MetalEngine] Max threads per group: \(device.maxThreadsPerThreadgroup)")
    }

    // MARK: - Library

    private var _library: MTLLibrary?
    var library: MTLLibrary {
        if let lib = _library { return lib }
        let lib: MTLLibrary
        if let customLib = try? device.makeDefaultLibrary(bundle: Bundle.main) {
            lib = customLib
        } else {
            lib = device.makeDefaultLibrary()!
        }
        _library = lib
        return lib
    }

    // MARK: - Render Pipeline State

    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor, name: String) -> MTLRenderPipelineState {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = renderPipelineCache[name] { return cached }

        descriptor.label = name
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            renderPipelineCache[name] = state
            return state
        } catch {
            fatalError("Failed to create render pipeline '\(name)': \(error)")
        }
    }

    // MARK: - Compute Pipeline State

    func makeComputePipelineState(functionName: String) -> MTLComputePipelineState {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = computePipelineCache[functionName] { return cached }

        let constantValues = MTLFunctionConstantValues()
        let function = (try? library.makeFunction(name: functionName, constantValues: constantValues)) ?? library.makeFunction(name: functionName)!
        do {
            let state = try device.makeComputePipelineState(function: function)
            computePipelineCache[functionName] = state
            return state
        } catch {
            fatalError("Failed to create compute pipeline '\(functionName)': \(error)")
        }
    }

    // MARK: - Pipeline Cache Flush

    func flushPipelineCaches() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        renderPipelineCache.removeAll()
        computePipelineCache.removeAll()
    }
}
