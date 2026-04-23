import MetalKit
import simd
import QuartzCore

// AttentionProvider, FeedbackState, DistractionEvent defined in Services/Attention/

// MARK: - MetalRenderer

final class MetalRenderer: NSObject, MTKViewDelegate, ObservableObject {

    private let engine = MetalEngine.shared
    let ssvepController = SSVEPController()

    @ObservationIgnored private(set) var frameCount: UInt64 = 0
    @ObservationIgnored var ssvepFrequency: Int = 15
    @ObservationIgnored var particleScale: Float = 1.0
    @ObservationIgnored var enableBloom: Bool = true
    var currentLevel: LevelID = .level1

    let performanceMonitor = PerformanceMonitor()

    var currentFPS: Int { performanceMonitor.stats.fps }
    var averageFrameTime: Double { performanceMonitor.stats.averageFrameTimeMS }

    private var particleBufferManager: ParticleBufferManager!
    private var uniformBufferManager: UniformBufferManager!
    private let renderPipelineCache = PipelineStateCache()
    private let computePipelineCache = ComputePipelineCache()

    private var backgroundPipelineState: MTLRenderPipelineState?
    private var particleRenderPipelineState: MTLRenderPipelineState?
    private var ssvepOverlayPipelineState: MTLRenderPipelineState?
    private var bloomCompositePipelineState: MTLRenderPipelineState?
    private var particleComputePipelineState: MTLComputePipelineState?
    private var bloomExtractPipelineState: MTLComputePipelineState?
    private var blurHorizontalPipelineState: MTLComputePipelineState?
    private var blurVerticalPipelineState: MTLComputePipelineState?
    private var attentionVisualPipelineState: MTLRenderPipelineState?

    private var bloomHalfTexture: MTLTexture?
    private var bloomQuarterTexture: MTLTexture?
    private var bloomEighthTexture: MTLTexture?
    private var sceneTexture: MTLTexture?
    private var bloomSourceTexture: MTLTexture?
    private var backgroundCacheTexture: MTLTexture?
    private var backgroundDirty = true

    private var bloomWeightsBuffer: MTLBuffer?
    private let blurWeights: [Float] = [
        0.0162, 0.0540, 0.1217, 0.1945, 0.2270,
        0.1945, 0.1217, 0.0540, 0.0162
    ]

    private var ssvepBuffer: MTLBuffer?
    private var attentionBuffer: MTLBuffer?
    private var levelConfigBuffer: MTLBuffer?

    private let maxParticleCount = 10_000
    private let tripleBufferCount = 3
    private var currentBufferIndex: Int = 0

    private var lastFrameTime: CFTimeInterval = 0
    private var bloomIntensity: Float = 1.0

    private var fullScreenQuadVertexBuffer: MTLBuffer?

    override init() {
        super.init()
        particleBufferManager = ParticleBufferManager(
            device: engine.device,
            maxParticleCount: maxParticleCount,
            tripleBufferCount: tripleBufferCount
        )
        uniformBufferManager = UniformBufferManager(
            device: engine.device,
            tripleBufferCount: tripleBufferCount
        )
        createBloomWeightsBuffer()
        createFullScreenQuad()
        createConstantBuffers()
        updateLevelConfigBuffer(level: .level1)
    }

    // MARK: - Setup

    private func createBloomWeightsBuffer() {
        bloomWeightsBuffer = engine.device.makeBuffer(
            bytes: blurWeights,
            length: blurWeights.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        bloomWeightsBuffer?.label = "BloomWeights"
    }

    private func createFullScreenQuad() {
        let vertices: [Float] = [
            -1, -1, 0, 0,
             1, -1, 1, 0,
            -1,  1, 0, 1,
             1,  1, 1, 1,
        ]
        fullScreenQuadVertexBuffer = engine.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
        fullScreenQuadVertexBuffer?.label = "FullScreenQuad"
    }

    private func createConstantBuffers() {
        let ssvepSize = ((MemoryLayout<SSVEPParamsMetal>.stride + 255) / 256) * 256
        ssvepBuffer = engine.device.makeBuffer(
            length: ssvepSize * tripleBufferCount,
            options: .storageModeShared
        )
        ssvepBuffer?.label = "SSVEPBuffer"

        let attentionSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        attentionBuffer = engine.device.makeBuffer(
            length: attentionSize * tripleBufferCount,
            options: .storageModeShared
        )
        attentionBuffer?.label = "AttentionBuffer"

        levelConfigBuffer = engine.device.makeBuffer(
            length: 256,
            options: .storageModeShared
        )
        levelConfigBuffer?.label = "LevelConfigBuffer"
    }

    // MARK: - Pipeline State Creation (lazy)

    private func getBackgroundPipelineState(format: MTLPixelFormat) -> MTLRenderPipelineState {
        if let state = backgroundPipelineState { return state }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = engine.library.makeFunction(name: "backgroundVertex")
        descriptor.fragmentFunction = engine.library.makeFunction(name: "backgroundFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.colorAttachments[0].isBlendingEnabled = false
        let state = engine.makeRenderPipelineState(descriptor: descriptor, name: "Background")
        backgroundPipelineState = state
        return state
    }

    private func getParticleComputePipelineState() -> MTLComputePipelineState {
        if let state = particleComputePipelineState { return state }
        let state = engine.makeComputePipelineState(functionName: "simulateParticles")
        particleComputePipelineState = state
        return state
    }

    private func getParticleRenderPipelineState(format: MTLPixelFormat) -> MTLRenderPipelineState {
        if let state = particleRenderPipelineState { return state }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = engine.library.makeFunction(name: "particleVertex")
        descriptor.fragmentFunction = engine.library.makeFunction(name: "particleFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        let state = engine.makeRenderPipelineState(descriptor: descriptor, name: "ParticleRender")
        particleRenderPipelineState = state
        return state
    }

    private func getSSVEPOverlayPipelineState(format: MTLPixelFormat) -> MTLRenderPipelineState {
        if let state = ssvepOverlayPipelineState { return state }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = engine.library.makeFunction(name: "ssvepOverlayVertex")
        descriptor.fragmentFunction = engine.library.makeFunction(name: "ssvepOverlayFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        let state = engine.makeRenderPipelineState(descriptor: descriptor, name: "SSVEPOverlay")
        ssvepOverlayPipelineState = state
        return state
    }

    private func getAttentionVisualPipelineState(format: MTLPixelFormat) -> MTLRenderPipelineState {
        if let state = attentionVisualPipelineState { return state }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = engine.library.makeFunction(name: "attentionVisualVertex")
        descriptor.fragmentFunction = engine.library.makeFunction(name: "attentionVisualFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let state = engine.makeRenderPipelineState(descriptor: descriptor, name: "AttentionVisual")
        attentionVisualPipelineState = state
        return state
    }

    private func getBloomExtractPipelineState() -> MTLComputePipelineState {
        if let state = bloomExtractPipelineState { return state }
        let state = engine.makeComputePipelineState(functionName: "bloomExtract")
        bloomExtractPipelineState = state
        return state
    }

    private func getBlurHorizontalPipelineState() -> MTLComputePipelineState {
        if let state = blurHorizontalPipelineState { return state }
        let state = engine.makeComputePipelineState(functionName: "blurHorizontal")
        blurHorizontalPipelineState = state
        return state
    }

    private func getBlurVerticalPipelineState() -> MTLComputePipelineState {
        if let state = blurVerticalPipelineState { return state }
        let state = engine.makeComputePipelineState(functionName: "blurVertical")
        blurVerticalPipelineState = state
        return state
    }

    private func getBloomCompositePipelineState(format: MTLPixelFormat) -> MTLRenderPipelineState {
        if let state = bloomCompositePipelineState { return state }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = engine.library.makeFunction(name: "bloomCompositeVertex")
        descriptor.fragmentFunction = engine.library.makeFunction(name: "bloomCompositeFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.colorAttachments[0].isBlendingEnabled = false
        let state = engine.makeRenderPipelineState(descriptor: descriptor, name: "BloomComposite")
        bloomCompositePipelineState = state
        return state
    }

    // MARK: - Texture Management

    func rebuildResolutionDependentTextures(width: Int, height: Int) {
        let createTex = { (w: Int, h: Int, label: String) -> MTLTexture in
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: max(1, w),
                height: max(1, h),
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .private
            let tex = self.engine.device.makeTexture(descriptor: desc)!
            tex.label = label
            return tex
        }

        sceneTexture = createTex(width, height, "Scene")
        bloomSourceTexture = createTex(width, height, "BloomSource")
        backgroundCacheTexture = createTex(width, height, "BackgroundCache")
        bloomHalfTexture = createTex(width / 2, height / 2, "BloomHalf")
        bloomQuarterTexture = createTex(width / 4, height / 4, "BloomQuarter")
        bloomEighthTexture = createTex(width / 8, height / 8, "BloomEighth")
        backgroundDirty = true
    }

    // MARK: - Main Draw

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        performanceMonitor.recordFrame()

        let now = CACurrentMediaTime()
        let deltaTime: Float = lastFrameTime > 0 ? Float(now - lastFrameTime) : 1.0 / 120.0
        lastFrameTime = now

        frameCount &+= 1
        currentBufferIndex = Int(frameCount % UInt64(tripleBufferCount))
        ssvepController.onFrame()
        let ssvepState = ssvepController.currentState

        let attentionValue = ssvepController.simulatedAttention
        let feedback = computeFeedbackState(attention: attentionValue)

        let commandBuffer = engine.commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Frame_\(frameCount)"

        updateUniformBuffers(deltaTime: deltaTime, view: view)
        updateSSVEPBuffer(ssvepState: ssvepState, deltaTime: deltaTime)
        updateAttentionBuffer(attention: attentionValue)

        let pixelFormat = view.colorPixelFormat

        // Ensure off-screen textures exist
        let drawableSize = view.drawableSize
        let w = Int(drawableSize.width)
        let h = Int(drawableSize.height)
        if w > 0 && h > 0 && (sceneTexture == nil || sceneTexture!.width != w || sceneTexture!.height != h) {
            rebuildResolutionDependentTextures(width: w, height: h)
        }

        guard let sceneTex = sceneTexture else {
            // Fallback: render directly to drawable (no bloom)
            renderSceneToDrawable(commandBuffer: commandBuffer, descriptor: renderPassDescriptor, pixelFormat: pixelFormat, ssvepState: ssvepState, attentionValue: attentionValue, deltaTime: deltaTime)
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        // ── Pass 1: Render full scene to off-screen sceneTexture ──
        let sceneDesc = MTLRenderPassDescriptor()
        sceneDesc.colorAttachments[0].texture = sceneTex
        sceneDesc.colorAttachments[0].loadAction = .clear
        sceneDesc.colorAttachments[0].storeAction = .store
        sceneDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0)

        executeBackgroundPass(commandBuffer: commandBuffer, texture: sceneTex, pixelFormat: .rgba16Float)
        executeParticleComputePass(commandBuffer: commandBuffer, deltaTime: deltaTime)
        executeParticleRenderPass(commandBuffer: commandBuffer, texture: sceneTex, pixelFormat: .rgba16Float)
        executeSSVEPOverlayPass(commandBuffer: commandBuffer, texture: sceneTex, pixelFormat: .rgba16Float)
        executeAttentionVisualPass(commandBuffer: commandBuffer, texture: sceneTex, pixelFormat: .rgba16Float)

        // ── Pass 2: Bloom from sceneTexture → bloom textures ──
        if enableBloom {
            executeBloomFromSceneTexture(commandBuffer: commandBuffer, sceneTexture: sceneTex, bloomStrength: feedback.glowIntensity)
        }

        // ── Pass 3: Final composite (sceneTexture + bloom) → drawable ──
        let finalDesc = MTLRenderPassDescriptor()
        finalDesc.colorAttachments[0].texture = drawable.texture
        finalDesc.colorAttachments[0].loadAction = .clear
        finalDesc.colorAttachments[0].storeAction = .store
        finalDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalDesc) {
            encoder.label = "FinalComposite"
            encoder.pushDebugGroup("FinalComposite")

            encoder.setRenderPipelineState(getBloomCompositePipelineState(format: pixelFormat))
            encoder.setVertexBuffer(fullScreenQuadVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)

            let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
            encoder.setVertexBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

            encoder.setFragmentTexture(sceneTex, index: 0)
            encoder.setFragmentTexture(bloomHalfTexture ?? sceneTex, index: 1)
            encoder.setFragmentTexture(bloomQuarterTexture ?? sceneTex, index: 2)
            encoder.setFragmentTexture(bloomEighthTexture ?? sceneTex, index: 3)
            var intensity: Float = enableBloom ? feedback.glowIntensity * bloomIntensity : 0.0
            encoder.setFragmentBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.popDebugGroup()
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Fallback: render directly to drawable (no off-screen texture)

    private func renderSceneToDrawable(
        commandBuffer: MTLCommandBuffer,
        descriptor: MTLRenderPassDescriptor,
        pixelFormat: MTLPixelFormat,
        ssvepState: SSVEPState,
        attentionValue: Float,
        deltaTime: Float
    ) {
        guard let texture = descriptor.colorAttachments[0].texture else { return }
        executeBackgroundPass(commandBuffer: commandBuffer, texture: texture, pixelFormat: pixelFormat)
        executeParticleComputePass(commandBuffer: commandBuffer, deltaTime: deltaTime)
        executeParticleRenderPass(commandBuffer: commandBuffer, texture: texture, pixelFormat: pixelFormat)
        executeSSVEPOverlayPass(commandBuffer: commandBuffer, texture: texture, pixelFormat: pixelFormat)
        executeAttentionVisualPass(commandBuffer: commandBuffer, texture: texture, pixelFormat: pixelFormat)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildResolutionDependentTextures(width: Int(size.width), height: Int(size.height))
    }

    // MARK: - Feedback State Computation

    private func computeFeedbackState(attention: Float) -> FeedbackState {
        let s = { (edge0: Float, edge1: Float, x: Float) -> Float in
            let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
            return t * t * (3.0 - 2.0 * t)
        }
        return FeedbackState(
            brightness: 0.15 + attention * 0.85,
            particleSpeed: s(0.2, 0.8, attention),
            glowIntensity: s(0.3, 0.9, attention) * 1.5,
            colorTemperature: 1.0 - s(0.2, 0.7, attention),
            vignetteStrength: 1.0 - s(0.2, 0.7, attention),
            audioLowPassCutoff: 200 + attention * 17800,
            binauralBeatGain: s(0.3, 0.9, attention),
            ambientVolume: s(0.2, 0.8, attention),
            feedbackTrigger: .none
        )
    }

    // MARK: - Buffer Updates

    private func updateUniformBuffers(deltaTime: Float, view: MTKView) {
        let projection = matrix_identity_float4x4
        let viewMatrix = matrix_identity_float4x4
        let viewProj = matrix_multiply(projection, viewMatrix)
        let inverseVP = viewProj.inverse
        let drawableSize = view.drawableSize

        uniformBufferManager.update(
            bufferIndex: currentBufferIndex,
            viewProjection: viewProj,
            inverseViewProjection: inverseVP,
            cameraPosition: SIMD3<Float>(0, 0, 2),
            time: Float(CACurrentMediaTime()),
            deltaTime: deltaTime,
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            mousePosition: SIMD2<Float>(0, 0)
        )
    }

    private func updateSSVEPBuffer(ssvepState: SSVEPState, deltaTime: Float) {
        let alignedSize = ((MemoryLayout<SSVEPParamsMetal>.stride + 255) / 256) * 256
        let offset = currentBufferIndex * alignedSize
        var params = SSVEPParamsMetal(
            targetOpacity: ssvepState.targetOpacity,
            distractorOpacity: ssvepState.distractorOpacity,
            advancedOpacity: ssvepState.advancedOpacity,
            attentionLevel: ssvepController.simulatedAttention,
            deltaTime: deltaTime,
            guidingPulse: ssvepController.guidingPulseActive ? 1.0 : 0.0,
            riftMode: ssvepController.riftModeActive ? 1.0 : 0.0,
            _alignPad: 0,
            frameIndex: ssvepState.frameIndex,
            padding: 0
        )
        memcpy(ssvepBuffer!.contents() + offset, &params, MemoryLayout<SSVEPParamsMetal>.size)
    }

    private func updateAttentionBuffer(attention: Float) {
        let alignedSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        let offset = currentBufferIndex * alignedSize
        var state = AttentionStateMetal(
            level: attention,
            targetPositionX: 0.0,
            targetPositionY: 0.0,
            transitionSpeed: 0.5
        )
        memcpy(attentionBuffer!.contents() + offset, &state, MemoryLayout<AttentionStateMetal>.size)
    }

    private func updateLevelConfigBuffer(level: LevelID) {
        guard let buffer = levelConfigBuffer else { return }
        var config = LevelSceneConfigMetal.forLevel(level)
        memcpy(buffer.contents(), &config, MemoryLayout<LevelSceneConfigMetal>.size)
    }

    // MARK: - Pass 1: Background

    private func executeBackgroundPass(commandBuffer: MTLCommandBuffer, texture: MTLTexture, pixelFormat: MTLPixelFormat) {
        let bgDescriptor = MTLRenderPassDescriptor()
        bgDescriptor.colorAttachments[0].texture = texture
        bgDescriptor.colorAttachments[0].loadAction = .clear
        bgDescriptor.colorAttachments[0].storeAction = .store
        bgDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: bgDescriptor) else { return }
        encoder.label = "BackgroundPass"
        encoder.pushDebugGroup("Background")

        encoder.setRenderPipelineState(getBackgroundPipelineState(format: pixelFormat))
        encoder.setVertexBuffer(fullScreenQuadVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
        let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setVertexBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

        let attentionAlignedSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        let attentionOffset = currentBufferIndex * attentionAlignedSize
        encoder.setFragmentBuffer(attentionBuffer!, offset: attentionOffset, index: BufferIndex.attention.rawValue)

        encoder.setFragmentBuffer(levelConfigBuffer!, offset: 0, index: BufferIndex.levelConfig.rawValue)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.popDebugGroup()
        encoder.endEncoding()
        backgroundDirty = false
    }

    // MARK: - Pass 2: Particle Compute

    private func executeParticleComputePass(commandBuffer: MTLCommandBuffer, deltaTime: Float) {
        let pipelineState = getParticleComputePipelineState()
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "ParticleCompute"
        encoder.pushDebugGroup("ParticleSimulate")

        encoder.setComputePipelineState(pipelineState)

        let particleOffset = particleBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setBuffer(particleBufferManager.buffer, offset: particleOffset, index: 0)

        var count = UInt32(particleBufferManager.activeParticleCount)
        encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)

        let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: 2)

        let ssvepAlignedSize = ((MemoryLayout<SSVEPParamsMetal>.stride + 255) / 256) * 256
        let ssvepOffset = currentBufferIndex * ssvepAlignedSize
        encoder.setBuffer(ssvepBuffer!, offset: ssvepOffset, index: 3)

        let attentionAlignedSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        let attentionOffset = currentBufferIndex * attentionAlignedSize
        encoder.setBuffer(attentionBuffer!, offset: attentionOffset, index: 4)

        encoder.setBuffer(levelConfigBuffer!, offset: 0, index: BufferIndex.levelConfig.rawValue)

        let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)
        let gridSize = MTLSize(
            width: (particleBufferManager.activeParticleCount + 255) / 256 * 256,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)

        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    // MARK: - Pass 2b: Particle Render

    private func executeParticleRenderPass(commandBuffer: MTLCommandBuffer, texture: MTLTexture, pixelFormat: MTLPixelFormat) {
        let particleDesc = MTLRenderPassDescriptor()
        particleDesc.colorAttachments[0].texture = texture
        particleDesc.colorAttachments[0].loadAction = .load
        particleDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: particleDesc) else { return }
        encoder.label = "ParticleRender"
        encoder.pushDebugGroup("ParticleDraw")

        encoder.setRenderPipelineState(getParticleRenderPipelineState(format: pixelFormat))

        let particleOffset = particleBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setVertexBuffer(particleBufferManager.buffer, offset: particleOffset, index: 0)

        let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setVertexBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

        let ssvepAlignedSize = ((MemoryLayout<SSVEPParamsMetal>.stride + 255) / 256) * 256
        let ssvepOffset = currentBufferIndex * ssvepAlignedSize
        encoder.setFragmentBuffer(ssvepBuffer!, offset: ssvepOffset, index: BufferIndex.ssvep.rawValue)

        let attentionAlignedSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        let attentionOffset = currentBufferIndex * attentionAlignedSize
        encoder.setFragmentBuffer(attentionBuffer!, offset: attentionOffset, index: BufferIndex.attention.rawValue)

        encoder.setFragmentBuffer(levelConfigBuffer!, offset: 0, index: BufferIndex.levelConfig.rawValue)

        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: particleBufferManager.activeParticleCount
        )

        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    // MARK: - Pass 3: SSVEP Stimulus Overlay

    private func executeSSVEPOverlayPass(commandBuffer: MTLCommandBuffer, texture: MTLTexture, pixelFormat: MTLPixelFormat) {
        let overlayDesc = MTLRenderPassDescriptor()
        overlayDesc.colorAttachments[0].texture = texture
        overlayDesc.colorAttachments[0].loadAction = .load
        overlayDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: overlayDesc) else { return }
        encoder.label = "SSVEPOverlay"
        encoder.pushDebugGroup("SSVEPStimulus")

        encoder.setRenderPipelineState(getSSVEPOverlayPipelineState(format: pixelFormat))
        encoder.setVertexBuffer(fullScreenQuadVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)

        let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setVertexBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

        let ssvepAlignedSize = ((MemoryLayout<SSVEPParamsMetal>.stride + 255) / 256) * 256
        let ssvepOffset = currentBufferIndex * ssvepAlignedSize
        encoder.setFragmentBuffer(ssvepBuffer!, offset: ssvepOffset, index: BufferIndex.ssvep.rawValue)

        encoder.setFragmentBuffer(levelConfigBuffer!, offset: 0, index: BufferIndex.levelConfig.rawValue)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    // MARK: - Pass 3b: Attention Visual

    private func executeAttentionVisualPass(commandBuffer: MTLCommandBuffer, texture: MTLTexture, pixelFormat: MTLPixelFormat) {
        let visualDesc = MTLRenderPassDescriptor()
        visualDesc.colorAttachments[0].texture = texture
        visualDesc.colorAttachments[0].loadAction = .load
        visualDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: visualDesc) else { return }
        encoder.label = "AttentionVisual"
        encoder.pushDebugGroup("AttentionVisual")

        encoder.setRenderPipelineState(getAttentionVisualPipelineState(format: pixelFormat))
        encoder.setVertexBuffer(fullScreenQuadVertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)

        let uniformOffset = uniformBufferManager.alignedOffset(for: currentBufferIndex)
        encoder.setVertexBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(uniformBufferManager.buffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

        let attentionAlignedSize = ((MemoryLayout<AttentionStateMetal>.stride + 255) / 256) * 256
        let attentionOffset = currentBufferIndex * attentionAlignedSize
        encoder.setFragmentBuffer(attentionBuffer!, offset: attentionOffset, index: BufferIndex.attention.rawValue)

        encoder.setFragmentBuffer(levelConfigBuffer!, offset: 0, index: BufferIndex.levelConfig.rawValue)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.popDebugGroup()
        encoder.endEncoding()
    }

    // MARK: - Pass 4: Bloom (from off-screen sceneTexture)

    private func executeBloomFromSceneTexture(commandBuffer: MTLCommandBuffer, sceneTexture: MTLTexture, bloomStrength: Float) {
        guard let halfTex = bloomHalfTexture,
              let quarterTex = bloomQuarterTexture,
              let eighthTex = bloomEighthTexture else { return }

        let extractPipeline = getBloomExtractPipelineState()

        // Extract bright pixels from scene → half texture
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "BloomExtract"
            encoder.setComputePipelineState(extractPipeline)
            encoder.setTexture(sceneTexture, index: 0)
            encoder.setTexture(halfTex, index: 1)
            var threshold: Float = 0.5
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: halfTex.width, height: halfTex.height, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }

        computeBlurPass(commandBuffer: commandBuffer, source: halfTex, dest: halfTex, temp: bloomSourceTexture!)

        // Downsample to quarter and blur
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "BloomExtractQuarter"
            encoder.setComputePipelineState(extractPipeline)
            encoder.setTexture(halfTex, index: 0)
            encoder.setTexture(quarterTex, index: 1)
            var threshold: Float = 0.0
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: quarterTex.width, height: quarterTex.height, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }
        computeBlurPass(commandBuffer: commandBuffer, source: quarterTex, dest: quarterTex, temp: bloomSourceTexture!)

        // Downsample to eighth and blur
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "BloomExtractEighth"
            encoder.setComputePipelineState(extractPipeline)
            encoder.setTexture(quarterTex, index: 0)
            encoder.setTexture(eighthTex, index: 1)
            var threshold: Float = 0.0
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: eighthTex.width, height: eighthTex.height, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }
        computeBlurPass(commandBuffer: commandBuffer, source: eighthTex, dest: eighthTex, temp: bloomSourceTexture!)
    }

    private func computeBlurPass(commandBuffer: MTLCommandBuffer, source: MTLTexture, dest: MTLTexture, temp: MTLTexture) {
        // Horizontal blur: source → temp
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "BlurHorizontal"
            encoder.setComputePipelineState(getBlurHorizontalPipelineState())
            encoder.setTexture(source, index: 0)
            encoder.setTexture(temp, index: 1)
            encoder.setBuffer(bloomWeightsBuffer!, offset: 0, index: 0)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: source.width, height: source.height, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }

        // Vertical blur: temp → dest
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.label = "BlurVertical"
            encoder.setComputePipelineState(getBlurVerticalPipelineState())
            encoder.setTexture(temp, index: 0)
            encoder.setTexture(dest, index: 1)
            encoder.setBuffer(bloomWeightsBuffer!, offset: 0, index: 0)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: dest.width, height: dest.height, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            encoder.endEncoding()
        }
    }

    // MARK: - Thermal Quality Adjustment

    func applyThermalState(_ level: ThermalMonitor.ThermalLevel) {
        particleScale = level.particleScaleFactor
        enableBloom = level.shouldEnableBloom
    }

    // MARK: - Level Transition

    func transitionToLevel(_ level: LevelID) {
        currentLevel = level
        ssvepController.configureForLevel(level.id)
        backgroundDirty = true
        particleBufferManager.initializeForLevel(level.id)
        updateLevelConfigBuffer(level: level)

        switch level {
        case .level1: bloomIntensity = 0.12
        case .level2: bloomIntensity = 1.2
        case .level3: bloomIntensity = 0.6
        case .level4: bloomIntensity = 1.0
        case .level5: bloomIntensity = 0.4
        case .level6: bloomIntensity = 1.5
        }
    }
}
