# 《星空与萤火》SSVEP 冥想训练 macOS 应用 — 技术实现计划

## Section 3: Audio Engine（AVAudioEngine）

### 3.1 Engine Architecture（引擎架构）

#### 3.1.1 完整 Audio Graph 拓扑

```
                          ┌──────────────────────────────────────────────────────────────┐
                          │                   SSVEPMeditationAudioEngine                  │
                          │                                                              │
  Source Nodes            │   Processing Nodes                  Output Nodes            │
  ┌─────────────────┐     │   ┌──────────────────────────┐    ┌───────────────────┐      │
  │ BinauralBeat    │─────┼──▶│                          │    │                   │      │
  │ Generator       │     │   │   mainMixerNode          │    │                   │      │
  │ (AVAudioSource  │     │   │   (AVAudioMixerNode)     │───▶│   outputNode      │──────┼──▶ 扬声器
  │  Node, stereo)  │     │   │                          │    │   (AVAudioOutput  │      │
  └─────────────────┘     │   │   inputBus 0: binaural   │    │    Node)           │      │
                          │   │   inputBus 1: ambient    │    │                   │      │
  ┌─────────────────┐     │   │   inputBus 2: chime      │    └───────────────────┘      │
  │ AmbientPad       │     │   └──────────┬───────────────┘                              │
  │ Generator       │─────┼──────────────┘                                               │
  │ (AVAudioSource  │     │                                                              │
  │  Node, stereo)  │     │   ┌──────────────────────────┐                               │
  └─────────────────┘     │   │   AVAudioUnitEQ          │                               │
                          │   │   (DynamicLowPass)       │                               │
  ┌─────────────────┐     │   │                          │                               │
  │ ChimeBell       │─────┼──▶│   Band 0: LowShelf       │                               │
  │ Generator       │     │   │   Band 1: Parametric     │                               │
  │ (AVAudioSource  │     │   │   Band 2: HighShelf      │                               │
  │  Node, stereo)  │     │   │   Band 3: Parametric     │                               │
  └─────────────────┘     │   │   Band 4-6: unused       │                               │
                          │   └──────────────────────────┘                               │
                          └──────────────────────────────────────────────────────────────┘
```

#### 3.1.2 AVAudioNode 子类层级与选择

| 节点 | AVAudioNode 子类 | 数量 | Channel Layout | 说明 |
|------|-----------------|------|---------------|------|
| BinauralBeatGenerator | `AVAudioSourceNode` | 1 | Stereo (L/R) | 自定义 render block，L/R 频率差产生 binaural beat |
| AmbientPadGenerator | `AVAudioSourceNode` | 1 | Stereo | 合成环境音垫（风声/雨声/篝火），filtered white noise |
| ChimeBellGenerator | `AVAudioSourceNode` | 1 | Stereo | 合成颂钵/风铃，harmonic sine + decay envelope |
| DynamicLowPassFilter | `AVAudioUnitEQ` | 1 | Stereo | 5-band EQ，Band 1 配置为 low-pass，cutoff 动态调节 |
| mainMixerNode | `AVAudioMixerNode` | 1 | Stereo | engine 自动创建的 singleton，所有 source 汇入 |
| outputNode | `AVAudioOutputNode` | 1 | Stereo | engine 自动创建的 singleton，连接物理输出 |

**为什么不用 `AVAudioUnitEffect` 自定义 AU？**
- `AVAudioSourceNode` 提供 render block 闭包，足够实现所有合成逻辑
- 避免了 `AUAudioUnit` 子类化的 Objective-C 桥接复杂性
- demo 阶段不需要 inter-app audio / Audio Unit hosting

#### 3.1.3 动态连接/断连策略

```swift
/// 运行时安全连接/断连规则（来自 Apple 文档的 constraint）：
/// 1. 断连操作只能在 mixer 的上游执行
/// 2. 不同 channel count 的节点不能直接互连（必须经过 mixer）
/// 3. 连接/断连前必须 engine.stop()，操作完成后 engine.start()
///    - 例外：如果 format 一致，可以在运行时 connect/disconnect

/// 推荐策略：所有 source node 在初始化时一次性全部连接到 mainMixerNode
/// 用 volume = 0.0 / 1.0 控制启停，而非动态 disconnect
/// 这避免了运行时拓扑变更的复杂性
```

**实现约束：**

```swift
// ✅ 推荐：volume 控制
func activateChimeLayer() {
    chimeGeneratorNode.volume = 1.0  // AVAudioMixerNode 属性
}
func deactivateChimeLayer() {
    // 使用 ramp 实现 fade out，避免咔嗒声
    chimeGeneratorNode.volumeParameter.ramp(
        toValue: 0.0,
        duration: 0.5,  // 500ms fade
        curve: .exponential
    )
}

// ❌ 避免：运行时 disconnect（可能导致 glitch）
// engine.disconnect(chimeGeneratorNode)
```

#### 3.1.4 Sample Rate 决策

| 参数 | 48000 Hz | 44100 Hz | 选择 |
|------|----------|----------|------|
| Binaural beat 精度 | ±0.000021 Hz | ±0.000023 Hz | 相当 |
| 15Hz 一周期采样点 | 3200 | 2940 | 48000 略优 |
| 20Hz 一周期采样点 | 2400 | 2205 | 48000 略优 |
| macOS 硬件原生 | 大多数外置 DAC | 内置扬声器 | 48000 |
| CPU 开销 | +9% vs 44100 | baseline | 44100 略优 |

**决策：48000 Hz**

理由：
1. macOS 外置音频设备（USB DAC、耳机放大器）绝大多数原生支持 48kHz
2. 15Hz binaural beat 在 48kHz 下每周期 3200 个采样点，phase 精度为 `2π/3200 = 0.00196 rad/sample`，远超人类听觉分辨率
3. SSVEP 应用不是 CPU 密集型，9% 的额外开销可忽略
4. 与视频帧率同步更干净（120fps / 48kHz = 每 400 samples 一帧，44100 = 每 367.5 samples 一帧，非整数）

**实际实现中的 sample rate 处理：**

```swift
let engine = AVAudioEngine()
// 不要硬编码 sample rate，使用设备硬件的 native rate
let hwSampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
// 通常为 48000.0（外置 DAC）或 44100.0（内置扬声器）
// 所有生成器的 phase increment 必须基于此值动态计算
```

#### 3.1.5 Buffer Size 与延迟优化

```swift
// 目标：input-to-output 延迟 < 10ms（远优于 100ms 同步要求）
let audioSession = AVAudioSession.sharedInstance()
do {
    try audioSession.setCategory(.playback, mode: .default, options: [])
    try audioSession.setPreferredSampleRate(48000)
    
    // 关键：设置最短 IO buffer duration
    // macOS 上 0.005 = 5ms = 240 samples @ 48kHz
    // 实际值取决于硬件，系统会 clamp 到设备支持的最小值
    try audioSession.setPreferredIOBufferDuration(0.005)  // 5ms
} catch {
    // fallback: 使用系统默认（通常 11.6ms ≈ 512 samples @ 44.1kHz 或 10.67ms @ 48kHz）
    print("Failed to set preferred IO buffer: \(error)")
}

// 验证实际值
let actualBufferDuration = audioSession.ioBufferDuration
let actualBufferSize = UInt32(actualBufferDuration * hwSampleRate)
// 预期：128 或 256 samples（2.67ms 或 5.33ms @ 48kHz）
```

**延迟预算分解：**

| 环节 | 延迟 | 累计 |
|------|------|------|
| Audio IO buffer | 5ms | 5ms |
| Render block 执行 | <1ms | 6ms |
| AudioVisual sync offset | <3ms | 9ms |
| AttentionManager 发布 | <2ms | 11ms |
| MetalRenderer 响应 | <8ms | 19ms |
| **总计** | | **<20ms**（远优于 100ms 目标） |

---

### 3.2 Binaural Beat Generator（双耳节拍生成器）

#### 3.2.1 完整实现规格

```swift
import AVFoundation

/// Binaural Beat Generator
/// 通过左右耳播放微小的频率差，诱导大脑产生差频的神经振荡
/// 原理：左耳 400Hz + 右耳 415Hz → 大脑感知 15Hz 拍频
final class BinauralBeatGenerator {
    
    // MARK: - Configuration
    
    /// 基础频率（左耳频率）
    /// 200-400Hz 为 binaural entrainment 的最优范围
    /// 更低频率（<200Hz）的 binaural beat 更容易感知但可能引起不适
    /// 更高频率（>400Hz）的 binaural beat 效果减弱
    let baseFrequency: Float  // 默认 200.0 Hz
    
    /// 拍频（右耳频率 - 左耳频率）
    /// 必须 < 40Hz 且 > 4Hz 才能有效产生 binaural beat 感知
    /// 15Hz = SSVEP 目标频率
    /// 20Hz = SSVEP 干扰频率
    let targetBeatFrequency: Float  // 15.0 或 20.0
    
    // MARK: - State
    
    /// 当前实际拍频（用于平滑过渡）
    private(set) var currentBeatFrequency: Float = 0.0
    
    /// 当前振幅（0.0 = 静音，1.0 = 全音量）
    private(set) var currentAmplitude: Float = 0.0
    
    /// 目标振幅
    var targetAmplitude: Float = 0.0 {
        didSet { /* trigger amplitude ramp */ }
    }
    
    /// 目标拍频（用于平滑过渡）
    var targetBeatFrequencyValue: Float = 15.0 {
        didSet { /* trigger frequency ramp */ }
    }
    
    /// phase accumulator（必须用 Double 精度避免 float drift）
    private var phaseLeft: Double = 0.0
    private var phaseRight: Double = 0.0
    
    /// sample rate（从 engine 获取）
    private var sampleRate: Double = 48000.0
    
    // MARK: - AVAudioSourceNode
    
    let audioSourceNode: AVAudioSourceNode
    
    init(baseFrequency: Float = 200.0,
         beatFrequency: Float = 15.0,
         sampleRate: Double = 48000.0) {
        
        self.baseFrequency = baseFrequency
        self.targetBeatFrequency = beatFrequency
        self.targetBeatFrequencyValue = beatFrequency
        self.sampleRate = sampleRate
        
        // Stereo format: 必须是 stereo，否则无法产生 binaural effect
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2  // Stereo: Left + Right
        )!
        
        // 使用 [self] 捕获以允许内部状态修改
        self.audioSourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            return self.renderBlock(frameCount: frameCount, audioBufferList: audioBufferList)
        }
    }
    
    // MARK: - Render Block
    
    private func renderBlock(frameCount: AVAudioFrameCount,
                              audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        
        // Stereo: bufferList[0] = Left, bufferList[1] = Right
        guard bufferList.count >= 2 else { return noErr }
        
        let leftChannel = bufferList[0]
        let rightChannel = bufferList[1]
        
        guard let leftPtr = leftChannel.mData?.assumingMemoryBound(to: Float.self),
              let rightPtr = rightChannel.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        
        let frameCount = Int(frameCount)
        let twoPi = 2.0 * Double.pi
        let sr = self.sampleRate
        
        // 预计算当前帧的 phase increment
        let leftFreq = Double(self.baseFrequency)
        let rightFreq = Double(self.baseFrequency + self.currentBeatFrequency)
        let leftPhaseIncrement = leftFreq / sr * twoPi
        let rightPhaseIncrement = rightFreq / sr * twoPi
        
        // 振幅平滑（每 buffer 级别的线性插值，避免咔嗒声）
        let amplitudeStep = (Double(self.targetAmplitude) - Double(self.currentAmplitude)) / Double(frameCount)
        
        // 频率平滑（每 buffer 级别）
        let freqStep = (Double(self.targetBeatFrequencyValue) - Double(self.currentBeatFrequency)) / Double(frameCount)
        
        for frame in 0..<frameCount {
            // 逐 sample 更新振幅和频率
            let amp = Float(Double(self.currentAmplitude) + Double(frame) * amplitudeStep)
            let beatFreq = Float(Double(self.currentBeatFrequency) + Double(frame) * freqStep)
            
            // 重新计算右耳频率（因为 beatFreq 在变化）
            let rightPhaseInc = Double(self.baseFrequency + beatFreq) / sr * twoPi
            
            // 生成正弦波
            let leftSample = sin(self.phaseLeft) * amp
            let rightSample = sin(self.phaseRight) * amp
            
            // 写入 buffer
            leftPtr[frame] = leftSample
            rightPtr[frame] = rightSample
            
            // 更新 phase（关键：用 Double 精度）
            self.phaseLeft += leftPhaseIncrement
            self.phaseRight += rightPhaseInc
            
            // Phase wrapping（防止 Double 溢出，每 ~4.5 小时 @ 48kHz）
            if self.phaseLeft > twoPi * 1e9 { self.phaseLeft -= twoPi * 1e9 }
            if self.phaseRight > twoPi * 1e9 { self.phaseRight -= twoPi * 1e9 }
        }
        
        // 更新当前状态
        self.currentAmplitude = self.targetAmplitude
        self.currentBeatFrequency = self.targetBeatFrequencyValue
        
        return noErr
    }
}
```

#### 3.2.2 基础频率选择策略

| 基础频率 | 优点 | 缺点 | 推荐场景 |
|---------|------|------|---------|
| **100 Hz** | Binaural beat 感知最强，低频更接近脑波频率 | 可能引起轻微头痛，长时间不舒适 | 高强度训练（短时间） |
| **200 Hz** ✅ | 感知清晰，舒适度好，entrainment 效果文献支持充分 | — | **默认值，所有关卡的起始配置** |
| **400 Hz** | 传统 binaural beat 常用频率，丰富的研究数据 | 高频段的 binaural beat 感知稍弱 | Level 3-6 高级训练 |
| **150 Hz** | 在感知强度和舒适度间取得良好平衡 | — | Level 1-2 入门阶段备选 |

**最终决策：200 Hz 为默认基础频率**

理由：
1. Oster (1973) 经典论文指出 200-300Hz 是 binaural beat 的最佳范围
2. 200Hz 的正弦波在 48kHz 采样率下每个周期 240 samples，phase 精度极高
3. 200Hz 不会产生听觉疲劳（长时间冥想训练的关键）
4. 足够低的频率确保 binaural beat 感知清晰（15Hz 的拍频在 200Hz 载波上可被清晰感知）

#### 3.2.3 拍频切换的平滑过渡

```swift
/// 切换 SSVEP 目标频率时的平滑过渡
/// 例如：从 Level 3 的 15Hz 目标切换到 Level 5 的 15Hz + 20Hz 干扰
func transitionBeatFrequency(to newFrequency: Float, duration: TimeInterval = 2.0) {
    // 不直接设置 targetBeatFrequencyValue
    // 而是启动一个定时器驱动的 ramp
    
    let startFreq = self.currentBeatFrequency
    let startTime = CACurrentMediaTime()
    let steps = Int(duration * self.sampleRate / 256)  // 每 256 samples 更新一次
    
    DispatchQueue.global(qos: .userInteractive).async {
        for step in 0...steps {
            let t = Float(step) / Float(steps)
            // 使用 smoothstep 插值（比线性更自然）
            let smoothT = t * t * (3.0 - 2.0 * t)
            let freq = startFreq + (newFrequency - startFreq) * smoothT
            
            DispatchQueue.main.sync {
                self.targetBeatFrequencyValue = freq
            }
            
            // 等待下一个更新周期
            usleep(UInt32(256.0 / self.sampleRate * 1_000_000))
        }
    }
}

/// 专注状态映射
func updateForAttention(_ attention: Float) {
    // attention: 0.0（完全走神）→ 1.0（完全专注）
    
    switch attention {
    case 0.6...1.0:
        // 专注：binaural beat 全功率，匹配 SSVEP 目标频率
        targetAmplitude = 0.3  // 不要太大！binaural beat 应该是 subliminal
        targetBeatFrequencyValue = currentSSVEPTargetFrequency  // 15Hz 或 40Hz
        // 0.3 的振幅意味着 carrier tone 很轻，beat 感知若有若无
        // 这是设计意图：用户不应该"听到" binaural beat，而是被它 subliminally 引导
        
    case 0.3..<0.6:
        // 中间状态：binaural beat 振幅线性衰减
        let t = (attention - 0.3) / 0.3  // 0..1
        targetAmplitude = 0.3 * t
        // beat 频率保持不变，只是越来越弱
        
    case 0.0..<0.3:
        // 走神：binaural beat 完全消失（no entrainment = 负反馈）
        targetAmplitude = 0.0
        
    default:
        break
    }
}
```

#### 3.2.4 Amplitude Envelope（振幅包络）

```swift
/// 全局 fade in/out 防止咔嗒声
/// 在 engine.start() / engine.stop() 前后调用

func fadeIn(duration: TimeInterval = 3.0) {
    // 3 秒淡入：冥想场景需要非常缓慢的进入
    // 使用 exponential curve 而非 linear（更自然）
    targetAmplitude = 0.3
    // render block 内部已实现 per-sample amplitude ramp
}

func fadeOut(duration: TimeInterval = 2.0) {
    // 2 秒淡出
    targetAmplitude = 0.0
}
```

---

### 3.3 Dynamic Low-Pass Filter（动态低通滤波器 — "溺水"效果）

#### 3.3.1 效果描述

设计文档原文："走神时音乐瞬间失去低频，只保留干涩的风声"

这是一个**频谱剥夺效果**（spectral stripping），而非简单的音量降低。核心思想是：
- **专注时**：完整频谱 → 温暖、丰满、包裹感
- **走神时**：高频被保留，低频和中低频被切除 → 干涩、冰冷、疏离感

#### 3.3.2 实现方案：AVAudioUnitEQ 5-band 配置

```swift
import AVFoundation

final class DynamicLowPassFilter {
    
    let eqNode: AVAudioUnitEQ
    private let filterBandIndex: UInt32 = 1  // Band 1 作为 low-pass
    private let lowShelfBandIndex: UInt32 = 0  // Band 0 作为 low shelf boost
    private let highShelfBandIndex: UInt32 = 2  // Band 2 作为 high shelf presence boost
    
    /// 当前 cutoff 频率
    private(set) var currentCutoffFrequency: Float = 20000.0
    
    init() {
        // 5-band EQ
        let eq = AVAudioUnitEQ(numberOfBands: 5)
        eq.globalGain = 0.0  // 不使用全局增益
        
        // Band 0: Low Shelf — 专注时 boost 低频（温暖感）
        let lowShelf = AVAudioUnitEQFilterParameters()
        lowShelf.filterType = .lowShelf
        lowShelf.frequency = 200.0    // 200Hz 拐点
        lowShelf.gain = 0.0          // 专注时 +6dB，走神时 -12dB
        lowShelf.bypass = false
        eq.bandParameters[0] = lowShelf
        
        // Band 1: Parametric (Low-Pass) — 核心动态滤波
        // AVAudioUnitEQ 没有直接的 low-pass type，但 parametric + 高 Q 值可模拟
        // 更好的方案：使用 Band 1 的 peak/notch 配合 Band 2 的 high shelf
        // 实际上我们用一个变通方案：调整 high shelf 的 cutoff
        
        // 重新设计：
        // Band 0: Low Shelf @ 150Hz — 控制低频温暖感
        // Band 1: Peaking @ 500Hz — 中频 presence（走神时这个频段以上被切）
        // Band 2: High Shelf @ 2000Hz — 高频空气感（走神时保留）
        // Band 3-4: 保留不用
        
        let midPeak = AVAudioUnitEQFilterParameters()
        midPeak.filterType = .parametric
        midPeak.frequency = 500.0
        midPeak.bandwidth = 2.0   // octaves
        midPeak.gain = 0.0
        midPeak.bypass = false
        eq.bandParameters[1] = midPeak
        
        let highShelf = AVAudioUnitEQFilterParameters()
        highShelf.filterType = .highShelf
        highShelf.frequency = 2000.0
        highShelf.gain = 0.0      // 专注时 +3dB（空气感），走神时 -6dB
        highShelf.bypass = false
        eq.bandParameters[2] = highShelf
        
        // Band 3-4: bypass
        for i in 3...4 {
            let unused = AVAudioUnitEQFilterParameters()
            unused.bypass = true
            eq.bandParameters[UInt32(i)] = unused
        }
        
        self.eqNode = eq
    }
    
    // MARK: - Attention-Driven Update
    
    /// 根据 attention 值更新滤波器参数
    /// @param attention 0.0（走神）→ 1.0（专注）
    func updateForAttention(_ attention: Float, duration: Float = 0.1) {
        // duration: 参数变化的时间（秒），用于平滑过渡避免 zipper noise
        
        let t = max(0.0, min(1.0, attention))  // clamp
        
        // --- Band 0: Low Shelf @ 150Hz ---
        // 专注时：+6dB（温暖的大提琴/颂钵低频）
        // 走神时：-12dB（低频被抽空）
        let lowShelfGain: Float = lerpf(-12.0, 6.0, t)
        eqNode.bandParameters[0].gain = lowShelfGain
        
        // --- Band 1: Parametric @ 500Hz ---
        // 专注时：+3dB（中频 presence，人声温暖）
        // 走神时：-8dB（中频被抽空，声音变薄）
        let midGain: Float = lerpf(-8.0, 3.0, t)
        eqNode.bandParameters[1].gain = midGain
        
        // --- Band 2: High Shelf @ 2000Hz ---
        // 专注时：+2dB（自然的空气感）
        // 走神时：-3dB（轻微衰减，但不完全消除）
        // 注意：高频不完全消除！设计意图是走神时保留"干涩的风声"
        // 风声的频谱集中在 2000-8000Hz，所以高频必须保留
        let highShelfGain: Float = lerpf(-3.0, 2.0, t)
        eqNode.bandParameters[2].gain = highShelfGain
        
        self.currentCutoffFrequency = lerpf(500.0, 20000.0, t)
    }
}

/// 线性插值
func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * t
}
```

#### 3.3.3 频谱映射表

| Attention | Low Shelf (150Hz) | Mid (500Hz) | High Shelf (2kHz) | 听感描述 |
|-----------|-------------------|-------------|-------------------|---------|
| 1.0（完全专注） | +6dB | +3dB | +2dB | 丰满温暖，大提琴长音 + 颂钵共鸣 |
| 0.8 | +2.4dB | +1.2dB | +0.8dB | 略微变薄但仍温暖 |
| 0.5 | -3dB | -2.5dB | -0.5dB | 明显变薄，温暖感消失 |
| 0.3 | -7.2dB | -5.6dB | -1.4dB | 干涩，只剩风声的高频嘶嘶声 |
| 0.0（完全走神） | -12dB | -8dB | -3dB | 极度干涩，只有枯叶摩擦般的嘶嘶声 |

#### 3.3.4 Anti-Zipper Noise 策略

```swift
// 方案 1（推荐）：使用 AVAudioUnitEQ 的内置 ramp
// AVAudioUnitEQ 在主线程设置参数时，会自动在下一个 render cycle 平滑过渡
// 只要不是在 audio render thread 上直接操作就没问题

// 方案 2（备用）：在 render callback 中做 per-sample 插值
// 如果 AVAudioUnitEQ 的内置 ramp 不够平滑，可以创建自定义 AVAudioUnitEffect

// 方案 3（最终保险）：使用 timer 驱动的逐步逼近
// 每 10ms 更新一次 EQ 参数（100Hz 更新率）
// 单次步进 < 0.5dB，完全不可闻
let filterUpdateTimer = Timer(timeInterval: 0.01, repeats: true) { _ in
    self.dynamicFilter.updateForAttention(self.currentAttention, duration: 0.01)
}
RunLoop.main.add(filterUpdateTimer, forMode: .common)
```

---

### 3.4 Ambient Sound Layer（环境音层合成）

#### 3.4.1 总体架构

```swift
/// 环境音混合器
/// 每个关卡有不同的 focused / distracted 音色配置
/// 通过 crossfade + filter 实现状态切换
final class AmbientSoundMixer {
    
    /// 两个环境音生成器：A（focused）和 B（distracted）
    let focusedPad: AmbientPadGenerator    // 温暖、丰富
    let distractedPad: AmbientPadGenerator // 干燥、稀疏
    
    /// 当前混合比例（0 = fully distracted, 1 = fully focused）
    var blendFactor: Float = 1.0 {
        didSet {
            focusedPad.volume = blendFactor
            distractedPad.volume = 1.0 - blendFactor
        }
    }
    
    func updateForAttention(_ attention: Float) {
        // 非线性映射：attention 0.5 附近变化最快
        let t = smoothstep(0.2, 0.8, attention)
        blendFactor = t
    }
}
```

#### 3.4.2 风声合成（Filtered White Noise + LFO）

```swift
/// 风声合成器
/// 原理：白噪声 → bandpass filter → LFO 调制 filter cutoff → 产生呼啸的起伏感
final class WindSynthesizer {
    
    // 白噪声源：使用 ARC4 random 生成
    // 不需要真正的 white noise buffer，可以在 render block 中实时生成
    // Float.random(in: -1...1) 即可产生白噪声
    
    // Bandpass filter 参数：
    // Center frequency: 800Hz - 3000Hz（由 LFO 调制）
    // Q factor: 0.5 - 2.0（低 Q = 宽频风声，高 Q = 窄频呼啸）
    // Gain: 0.15 - 0.25（风声不应太大，是背景层）
    
    // LFO 参数：
    // Rate: 0.05Hz - 0.2Hz（20 秒到 5 秒一个完整的强弱周期）
    // Depth: 200Hz - 1500Hz（cutoff 摆动范围）
    // Waveform: sine（平滑的呼吸感）或 triangle（更锐利的阵风）
    
    // 实时滤波实现（在 render block 中）：
    // 使用 biquad filter（二阶 IIR）
    // 每个样本更新 filter coefficients（因为 cutoff 在变）
    
    struct BiquadCoefficients {
        var b0: Float, b1: Float, b2: Float
        var a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0  // input history
        var y1: Float = 0, y2: Float = 0  // output history
    }
    
    static func bandpassCoefficients(centerFreq: Float, Q: Float, sampleRate: Float) -> BiquadCoefficients {
        let w0 = 2.0 * Float.pi * centerFreq / sampleRate
        let alpha = sin(w0) / (2.0 * Q)
        
        let b0 = alpha
        let b1 = 0.0
        let b2 = -alpha
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cos(w0)
        let a2 = 1.0 - alpha
        
        return BiquadCoefficients(
            b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
            a1: a1 / a0, a2: a2 / a0
        )
    }
}
```

**风声变体参数表：**

| 变体 | Center Freq (Hz) | Q | LFO Rate (Hz) | LFO Depth (Hz) | 用途 |
|------|-------------------|---|----------------|-----------------|------|
| 微风 | 1200 | 0.8 | 0.08 | 400 | Level 1 背景层 |
| 阵风 | 2000 | 1.5 | 0.15 | 800 | Level 2 迷雾森林 |
| 暴风 | 2500 | 0.5 | 0.3 | 1500 | Level 5 雷暴 |
| 死寂之风 | 3500 | 2.0 | 0.05 | 200 | Level 4-6 走神惩罚 |

#### 3.4.3 颂钵合成（Singing Bowl Resonance）

```swift
/// 颂钵合成器
/// 原理：多个正弦波泛音叠加 + 指数衰减包络
/// 颂钵的音色特征：强烈的基频 + 多个近似谐波关系的泛音
/// 
/// 典型 Tibetan singing bowl 的泛音结构（以 256Hz 基频为例）：
///   Fundamental: 256Hz (strike tone)
///   1st overtone: 512Hz (octave)
///   2nd overtone: 768Hz (perfect 12th, 颂钵特有)
///   3rd overtone: 1024Hz (double octave)
///   Water sound: ~1200-1800Hz (颂钵边缘振动)
final class SingingBowlSynthesizer {
    
    struct Harmonic {
        let frequency: Float       // Hz
        let amplitude: Float       // 0..1，相对于基频
        let decayRate: Float       // exponential decay rate（1/s）
        let phase: Double          // phase accumulator
    }
    
    /// 颂钵泛音表（基频 256Hz）
    static let tibetanBowlHarmonics: [Harmonic] = [
        Harmonic(frequency: 256.0,  amplitude: 1.0,  decayRate: 0.3,  phase: 0),
        Harmonic(frequency: 512.0,  amplitude: 0.6,  decayRate: 0.5,  phase: 0),
        Harmonic(frequency: 768.0,  amplitude: 0.35, decayRate: 0.8,  phase: 0),
        Harmonic(frequency: 1024.0, amplitude: 0.2,  decayRate: 1.2,  phase: 0),
        Harmonic(frequency: 1410.0, amplitude: 0.12, decayRate: 1.8,  phase: 0),  // 颂钵特有
        Harmonic(frequency: 1780.0, amplitude: 0.08, decayRate: 2.5,  phase: 0),  // 水声
    ]
    
    /// 每次触发（"敲击"）的时间戳和包络状态
    var lastStrikeTime: Double = 0
    var strikeAmplitude: Float = 0.0
    
    /// 触发一次"敲击"
    func strike(amplitude: Float = 0.4) {
        lastStrikeTime = CACurrentMediaTime()
        strikeAmplitude = amplitude
    }
    
    /// Render block 中的逐样本计算
    func renderSample(currentTime: Double, sampleIndex: Int, sampleRate: Double) -> Float {
        let elapsed = Float(currentTime - lastStrikeTime)
        if elapsed < 0 || elapsed > 30.0 { return 0.0 }  // 30 秒后完全衰减
        
        var sample: Float = 0.0
        let twoPi = 2.0 * Double.pi
        
        for i in 0..<Self.tibetanBowlHarmonics.count {
            var h = Self.tibetanBowlHarmonics[i]
            
            // 指数衰减包络
            let envelope = strikeAmplitude * h.amplitude * exp(-h.decayRate * elapsed)
            
            // 正弦波 + 轻微 frequency wobble（颂钵特有的颤动）
            let wobble = 1.0 + 0.002 * sin(Float(twoPi) * 5.0 * elapsed + Float(i) * 0.7)
            let freq = h.frequency * wobble
            
            h.phase += Double(freq) / sampleRate * twoPi
            if h.phase > twoPi { h.phase -= twoPi }
            
            sample += envelope * sin(h.phase)
        }
        
        // 轻微的 reverb tail（简单的 feedback delay）
        // 在实际实现中可以用更长的 delay line + low-pass filter
        
        return sample * 0.5  // master volume
    }
}
```

#### 3.4.4 风铃合成（Wind Chimes）

```swift
/// 风铃合成器
/// 原理：随机时间触发的高频正弦脉冲 + 指数衰减
/// 风铃的音色特征：高频、清脆、短衰减、随机泛音
final class WindChimeSynthesizer {
    
    struct ChimeTone {
        let frequency: Float   // Hz，通常 2000-6000Hz
        let decayRate: Float   // 1/s，通常 3-8（短促）
        let amplitude: Float
        var phase: Double = 0.0
    }
    
    /// 风铃音高表（Pentatonic scale 的高八度）
    static let pentatonicChimes: [ChimeTone] = [
        ChimeTone(frequency: 2637.0, decayRate: 4.0, amplitude: 0.3),  // C7
        ChimeTone(frequency: 2960.0, decayRate: 5.0, amplitude: 0.25), // D7
        ChimeTone(frequency: 3520.0, decayRate: 4.5, amplitude: 0.3),  // A7
        ChimeTone(frequency: 3951.0, decayRate: 6.0, amplitude: 0.2),  // B7
        ChimeTone(frequency: 4186.0, decayRate: 5.5, amplitude: 0.25), // C8
    ]
    
    /// 活跃的 chime 事件列表
    private var activeChimes: [(toneIndex: Int, startTime: Double, amplitude: Float)] = []
    
    /// 下一次触发时间（Poisson process）
    private var nextTriggerTime: Double = 0
    
    /// 平均触发间隔（秒）
    /// 专注时：2-5 秒一次（稀疏，冥想感）
    /// 走神时：0.5-1 秒一次（密集，焦虑感）→ 或完全停止
    var averageInterval: Double = 3.0
    
    func updateForAttention(_ attention: Float) {
        if attention > 0.6 {
            averageInterval = lerp(3.0, 5.0, (attention - 0.6) / 0.4)  // 3-5秒
        } else if attention > 0.3 {
            averageInterval = lerp(1.0, 3.0, (attention - 0.3) / 0.3)  // 1-3秒
        } else {
            averageInterval = 100.0  // 几乎不触发（走神惩罚）
        }
    }
    
    func renderSample(currentTime: Double, sampleRate: Double) -> Float {
        // 检查是否需要触发新 chime
        if currentTime >= nextTriggerTime {
            let toneIndex = Int.random(in: 0..<Self.pentatonicChimes.count)
            let amp = Float.random(in: 0.15...0.35)
            activeChimes.append((toneIndex, currentTime, amp))
            
            // Poisson process: 下一次触发间隔
            let interval = -log(Float.random(in: 0.001...1.0)) * Float(averageInterval)
            nextTriggerTime = currentTime + Double(interval)
        }
        
        // 清理已衰减的 chime
        activeChimes.removeAll { chime in
            let elapsed = Float(currentTime - chime.startTime)
            return exp(-Self.pentatonicChimes[chime.toneIndex].decayRate * elapsed) < 0.001
        }
        
        // 混合所有活跃 chime
        var sample: Float = 0.0
        for chime in activeChimes {
            let tone = Self.pentatonicChimes[chime.toneIndex]
            let elapsed = Float(currentTime - chime.startTime)
            let envelope = chime.amplitude * exp(-tone.decayRate * elapsed)
            sample += envelope * sin(tone.phase)
            tone.phase += Double(tone.frequency) / sampleRate * 2.0 * Double.pi
        }
        
        return sample * 0.4  // master volume
    }
}
```

#### 3.4.5 大提琴 Drone 合成（Cello Drone）

```swift
/// 大提琴 Drone 合成器
/// 原理：sawtooth wave → heavy low-pass filter → slow vibrato
/// 大提琴 drone 的音色特征：温暖、浓郁、有"琴体共鸣"感
final class CelloDroneSynthesizer {
    
    /// 基频：C2 = 65.41Hz（大提琴 open C string）
    /// 或 C3 = 130.81Hz（更轻盈的 drone）
    let fundamentalFreq: Float = 130.81  // C3
    
    /// Sawtooth 波生成（band-limited，避免 aliasing）
    /// 在 render block 中使用 additive synthesis 模拟：
    /// 只叠加前 12-16 个谐波（更高谐波被 low-pass filter 切掉）
    let harmonicCount: Int = 16
    
    /// Low-pass filter cutoff：400-800Hz（模拟大提琴琴体的自然共振上限）
    let filterCutoff: Float = 600.0
    
    /// Vibrato 参数
    let vibratoRate: Float = 5.5    // Hz（大提琴 vibrato 典型速率）
    let vibratoDepth: Float = 3.0   // Hz（频率摆动范围 ±3Hz）
    
    /// 各谐波的衰减系数（模拟 bow-string 的频谱包络）
    /// 低次谐波强，高次谐波弱，1/n 衰减 + 额外的 roll-off
    func harmonicAmplitude(_ harmonicIndex: Int) -> Float {
        let n = Float(harmonicIndex + 1)
        // 1/n 衰减 + 额外的高频 roll-off
        return (1.0 / n) * exp(-0.15 * n)
    }
}
```

#### 3.4.6 关卡音色配置矩阵

| 关卡 | Focused 音色 | Distracted 音色 | Blend 方式 |
|------|-------------|-----------------|-----------|
| Level 1 涟漪绽放 | 颂钵 + 水声（filtered noise @ 500Hz） | 微弱风声 | Crossfade |
| Level 2 萤火引路 | 风铃 + 森林环境音（filtered noise @ 1kHz） | 密集风声 + 枯叶（noise @ 3kHz, high Q） | Crossfade + Filter |
| Level 3 星图寻迹 | 大提琴 drone + 水晶般的高频泛音 | 稀疏风声 | Crossfade |
| Level 4 真假萤火 | 大提琴 drone + 颂钵 | 风声 + 金属摩擦声（high-pass noise @ 4kHz） | Crossfade + Filter |
| Level 5 飞燕破云 | 大提琴 drone（强）+ 有节奏的风铃 | 暴风 + 雷声（low burst noise @ 50Hz） | Crossfade + Additive |
| Level 6 流星试炼 | 极简：单一颂钵泛音（长 sustain） | 极静：只有最微弱的呼吸般的风声 | Crossfade |

---

### 3.5 Haptic Feedback（触觉反馈 — macOS 限制与替代方案）

#### 3.5.1 macOS 触觉能力现状

| API | macOS 支持情况 | 说明 |
|-----|---------------|------|
| `CoreHaptics` (`CHHapticEngine`) | ❌ **不支持** | 仅 iOS 13+, iPadOS 13+, visionOS 1.0+。macOS 10.15+ 的 API 存在但 `capabilities.supportsHaptics` 始终返回 `false` |
| `NSHapticFeedbackManager` | ⚠️ **极其有限** | 仅支持 `performanceFeedback`（align rect）和 `genericFeedback`（acknowledge）两种系统级反馈，无法自定义振动模式 |
| Magic Trackpad 力度反馈 | ❌ **不可编程** | Force Click 是系统级行为，开发者无法通过 API 触发自定义振动 |
| Magic Mouse | ❌ **无振动马达** | 无任何触觉反馈能力 |

**结论：macOS 平台不具备有意义的触觉反馈能力。**

#### 3.5.2 替代方案：视觉脉冲（Visual Pulse）

```swift
/// 替代触觉反馈的视觉脉冲系统
/// 当注意力状态发生变化时，在整个屏幕边缘产生微弱的光晕脉冲
/// 
/// 设计意图：
/// - 专注→走神：屏幕边缘向内收缩的暗色脉冲（"世界在缩小"的感觉）
/// - 走神→专注：屏幕中心向外扩散的暖色脉冲（"视野在打开"的感觉）
///
/// 实现方式：
/// - Metal shader：全屏 quad + radial gradient
/// - 脉冲参数：
///   - Duration: 500ms
///   - Max opacity: 0.15（极其微弱，subliminal）
///   - Color: 专注=#FFE9A6(暖黄), 走神=#1A1A2E(暗蓝黑)
///   - Ease curve: ease-out (fast attack, slow release)
```

#### 3.5.3 替代方案：音频瞬态（Audio Transient）

```swift
/// 用短促的音频瞬态替代触觉反馈
/// 
/// 专注达成：清脆的"叮"声（sine @ 2400Hz, 50ms decay）
/// 走神检测：低沉的"嗡"声（sine @ 80Hz, 200ms decay）
/// SSVEP 节点连线：柔和的 ascending tone（C5→E5→G5, 300ms each）
///
/// 关键约束：
/// - 音量必须极低（amplitude < 0.1）
/// - 不能干扰 binaural beat entrainment
/// - 频率应远离 SSVEP target 频率（15Hz/20Hz/40Hz）
```

---

### 3.6 Audio-Visual Sync Timing（音视频同步时序）

#### 3.6.1 同步架构

```
                    ┌─────────────────────────────┐
                    │     AttentionManager         │
                    │  (SimulatedAttentionSource)   │
                    │                              │
                    │  每 100ms 发布一次 attention 值│
                    └──────────┬──────────────────┘
                               │
                    CombineLatest / attention (Float)
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
    ┌─────────────────┐ ┌──────────────┐ ┌──────────────┐
    │  AudioEngine     │ │ MetalRenderer│ │ StateLogger  │
    │  .onReceive     │ │ .onReceive   │ │ .onReceive   │
    │                  │ │              │ │              │
    │  update filters  │ │ update visual│ │ log sync     │
    │  update binaural │ │ params       │ │ offset       │
    │  update ambient  │ │ update SSVEP │ │              │
    └─────────────────┘ └──────────────┘ └──────────────┘
```

#### 3.6.2 实现方案（Combine framework）

```swift
import Combine

/// Attention 状态发布者
/// 由 SimulatedAttentionSource（demo）或 EEGProcessor（生产）驱动
let attentionPublisher = CurrentValueSubject<Float, Never>(0.5)

// --- Audio 订阅 ---
let audioSubscription = attentionPublisher
    .removeDuplicates()  // 相同值不重复处理
    .receive(on: DispatchQueue.main)  // AVAudioEngine 参数修改必须在主线程
    .sink { [weak self] attention in
        self?.audioEngine.updateForAttention(attention)
    }

// --- Visual 订阅 ---
let visualSubscription = attentionPublisher
    .removeDuplicates()
    .receive(on: DispatchQueue.main)  // Metal command buffer 提交在主线程
    .sink { [weak self] attention in
        self?.metalRenderer.updateForAttention(attention)
    }

// --- Sync Logger（仅 DEBUG 模式）---
#if DEBUG
let syncLogger = AttentionSyncLogger()

let debugSubscription = attentionPublisher
    .sink { attention in
        let audioTimestamp = CACurrentMediaTime()
        syncLogger.logEvent(
            attention: attention,
            audioTimestamp: audioTimestamp,
            visualTimestamp: self.metalRenderer.lastFrameTimestamp,
            source: "attentionManager"
        )
    }
#endif
```

#### 3.6.3 同步精度测量

```swift
/// 音视频同步测量器
/// 仅在 DEBUG build 中编译
#if DEBUG
final class AttentionSyncLogger {
    
    struct SyncEvent {
        let timestamp: Double          // CACurrentMediaTime()
        let attention: Float
        let audioApplyTimestamp: Double?  // AudioEngine 实际应用参数的时间
        let visualApplyTimestamp: Double? // MetalRenderer 实际渲染帧的时间
        let syncOffsetMs: Double?         // audio - visual 偏移量（ms）
    }
    
    private var events: [SyncEvent] = []
    private let maxEvents = 1000
    
    func logEvent(attention: Float,
                  audioTimestamp: Double,
                  visualTimestamp: Double,
                  source: String) {
        // 音频和视频的实际应用时间差
        // audioEngine 在下一个 render cycle（~5ms）应用参数
        // metalRenderer 在下一个 frame（~8.3ms @ 120fps）应用参数
        // 因此同步偏移 = |audioRenderTime - visualFrameTime|
        
        let offset = abs(audioTimestamp - visualTimestamp) * 1000.0  // ms
        
        let event = SyncEvent(
            timestamp: CACurrentMediaTime(),
            attention: attention,
            audioApplyTimestamp: audioTimestamp,
            visualApplyTimestamp: visualTimestamp,
            syncOffsetMs: offset
        )
        
        events.append(event)
        if events.count > maxEvents { events.removeFirst() }
        
        // 偏移超过 50ms 时发出警告
        if offset > 50.0 {
            print("⚠️ Audio-Visual sync offset: \(String(format: "%.1f", offset))ms")
        }
    }
    
    /// 生成同步统计报告
    func generateReport() -> String {
        guard !events.isEmpty else { return "No sync events recorded" }
        
        let offsets = events.compactMap { $0.syncOffsetMs }
        guard !offsets.isEmpty else { return "No offset data" }
        
        let avg = offsets.reduce(0, +) / Double(offsets.count)
        let max = offsets.max() ?? 0
        let p95 = offsets.sorted()[Int(Double(offsets.count) * 0.95)]
        
        return """
        ═══ Audio-Visual Sync Report ═══
        Events: \(events.count)
        Avg offset: \(String(format: "%.2f", avg))ms
        Max offset: \(String(format: "%.2f", max))ms
        P95 offset: \(String(format: "%.2f", p95))ms
        Target: < 100ms ✅
        ══════════════════════════════
        """
    }
}
#endif
```

#### 3.6.4 同步精度保证策略

| 策略 | 实现 | 效果 |
|------|------|------|
| 统一时间源 | `CACurrentMediaTime()` | 音频和视频使用同一高精度时钟 |
| 同一发布源 | `CurrentValueSubject<Float>` | 保证两者收到相同值 |
| 主线程调度 | `.receive(on: DispatchQueue.main)` | 避免线程间竞争 |
| deduplication | `.removeDuplicates()` | 避免不必要的状态更新 |
| 偏差容忍 | 50ms threshold | 人类感知阈值 ~80ms，留余量 |

---

## Section 4: 六关详细规格

### Level 1: 涟漪绽放（Ripple Bloom）

#### 4.1.1 场景描述

黑暗湖面，中央一朵含苞待放的睡莲。无干扰项。用户需要持续注视莲花花蕊处闪烁的光点。

#### 4.1.2 SSVEP 配置

| 参数 | 值 | 说明 |
|------|---|------|
| Target 频率 | 15Hz | 莲花花蕊处闪烁 |
| Target 颜色 | #FFE9A6（暖烛光） | 透明度 60%~100% 正弦波动，占屏 < 3% |
| Distractor | 无 | 纯持续性注意力训练 |
| Target 几何 | 径向 30px 发光圆 | 中心亮，边缘柔和衰减（Gaussian falloff） |

#### 4.1.3 Metal Shader 规格

**水面 Shader（Water Surface）：**

```metal
// WaterSurfaceFragment.metal
// 原理：多层正弦波叠加（Gerstner wave 简化版）
// 不用 normal map（demo 阶段减少资源依赖）

// 水面参数：
// - 3 层正弦波叠加
// - Wave 1: freq = 0.3, amplitude = 0.02, speed = 0.5
// - Wave 2: freq = 0.7, amplitude = 0.01, speed = 0.8
// - Wave 3: freq = 1.5, amplitude = 0.005, speed = 1.2
// - 法线通过偏导数计算：N = normalize(cross(dFdx, dFdy))

fragment float4 waterSurface(VertexOut in [[stage_in]],
                             constant WaterParams& params [[buffer(0)]],
                             constant AttentionState& attention [[buffer(1)]]) {
    
    float2 uv = in.uv;
    float time = params.time;
    
    // 多层波叠加计算位移
    float displacement = 0.0;
    displacement += params.wave1Amp * sin(uv.x * params.wave1Freq + time * params.wave1Speed);
    displacement += params.wave2Amp * sin(uv.y * params.wave2Freq + time * params.wave2Speed + 1.7);
    displacement += params.wave3Amp * sin((uv.x + uv.y) * params.wave3Freq + time * params.wave3Speed + 3.1);
    
    // 注意力调制波幅
    displacement *= attention.value * 0.8 + 0.2;  // 0.2~1.0 范围
    
    // 法线计算（通过偏导数）
    float dx = 0.001;
    float hL = waterHeight(uv - float2(dx, 0), time, params, attention.value);
    float hR = waterHeight(uv + float2(dx, 0), time, params, attention.value);
    float hD = waterHeight(uv - float2(0, dx), time, params, attention.value);
    float hU = waterHeight(uv + float2(0, dx), time, params, attention.value);
    float3 normal = normalize(float3(hL - hR, hD - hU, 2.0 * dx));
    
    // 基础水色：深蓝黑
    float3 deepColor = float3(0.02, 0.04, 0.08);    // #050A14
    float3 shallowColor = float3(0.05, 0.10, 0.18);  // #0D1A2E
    
    // 简单的 Fresnel 近似
    float fresnel = pow(1.0 - max(dot(normal, float3(0, 0, 1)), 0.0), 3.0);
    float3 waterColor = mix(shallowColor, deepColor, fresnel);
    
    // 莲花区域附近的水面高光
    float distToLotus = length(uv - params.lotusPosition);
    float lotusGlow = exp(-distToLotus * 3.0) * attention.value * 0.3;
    waterColor += float3(1.0, 0.91, 0.65) * lotusGlow;  // #FFE9A6
    
    return float4(waterColor, 1.0);
}
```

**涟漪系统（Ripple Rings）：**

```metal
// 涟漪参数：
// - 从莲花中心向外扩散的同心圆
// - 每个涟漪：radius 从 0 扩展到 0.4（归一化坐标），然后消失
// - 同时存在 3-5 个涟漪（不同 phase）
// - 涟漪线条宽度：2-3px
// - 涟漪颜色：#FFE9A6（暖黄），opacity 随 radius 增大而降低
// - 生成频率：每 2-4 秒一个新涟漪（attention > 0.3 时）

// 涟漪生成逻辑（CPU 端）：
struct Ripple {
    let startTime: Double
    let maxRadius: Float  // 归一化坐标，0.3-0.5
    let speed: Float      // 归一化坐标/秒，0.1-0.2
    let opacity: Float    // 初始 opacity，0.3-0.6
}

// 涟漪绘制（在水面 shader 的 overlay pass 中）：
// float rippleDist = abs(length(uv - lotusCenter) - ripple.currentRadius);
// float rippleLine = smoothstep(0.003, 0.0, rippleDist);
// float rippleAlpha = rippleLine * ripple.currentOpacity * attention.value;
```

**莲花几何（Lotus Geometry）：**

```swift
// 莲花由多层花瓣组成，从外到内逐层绽放
// 
// 层级结构：
// - 外层花瓣：8 片，最大，最先打开
// - 中层花瓣：6 片，中等大小，延迟打开
// - 内层花瓣：4 片，最小，最后打开
// - 花蕊：中心发光点（SSVEP target），始终可见
//
// 每片花瓣：
// - 几何：Bezier curve 定义的 2D 轮廓（不是 3D mesh）
// - 材质：渐变填充，底部 #2D1B4E（暗紫），顶部 #FFB6C1（浅粉）
// - 绽放动画：花瓣绕根部旋转（rotation），0° = 闭合，60° = 全开
// - 缓动函数：ease-out-back（overshoot 到 65° 然后回弹到 60°）
//
// 花瓣绽放时间线（attention 持续 > 0.6 时触发）：
// t=0s: 外层花瓣开始打开（60° over 3s）
// t=2s: 中层花瓣开始打开（60° over 2.5s）
// t=3.5s: 内层花瓣开始打开（60° over 2s）
// t=5s: 花蕊发光增强 + 花粉粒子开始释放
//
// 走神时（attention < 0.3）：
// 所有花瓣反向关闭（速度加倍，1.5s 完全闭合）

struct LotusConfiguration {
    let petalLayers: [PetalLayer]
    let stamenGlowRadius: Float = 15.0  // px
    let stamenGlowColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.913, 0.651)  // #FFE9A6
    let stamenSSVEPFrequency: Float = 15.0
    let stamenSSVEPMinOpacity: Float = 0.6
    let stamenSSVEPMaxOpacity: Float = 1.0
    let centerPosition: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)  // 屏幕中心
}

struct PetalLayer {
    let count: Int           // 花瓣数量
    let width: Float         // 花瓣宽度（归一化，0.08-0.15）
    let height: Float        // 花瓣高度（归一化，0.10-0.20）
    let openAngle: Float     // 全开角度（度）
    let delay: TimeInterval  // 绽放延迟（秒）
    let duration: TimeInterval  // 绽放持续时间（秒）
    let baseColor: SIMD3<Float>
    let tipColor: SIMD3<Float>
}
```

**粒子系统（Pollen Particles）：**

```swift
// 花粉粒子参数：
// - 触发条件：attention > 0.8 持续 3 秒后开始释放
// - 最大粒子数：100-200
// - 每秒释放：10-20 个
// - 粒子大小：2-5px（Point Sprite）
// - 粒子颜色：#FFE9A6（暖黄）→ #FFA726（琥珀）随机
// - 运动模式：
//   - 初始速度：从花蕊中心向外，随机方向
//   - 速度：20-50 px/s
//   - 受重力影响（缓慢下落）：+5 px/s² 向下
//   - 受微风影响：水平方向 10-30 px/s 的正弦摆动
// - 生命周期：3-8 秒
// - 淡出：最后 1 秒 opacity 从 1.0 → 0.0（linear）
```

#### 4.1.4 音频规格

| 状态 | 音色 | 参数 |
|------|------|------|
| Focused (att > 0.6) | 颂钵共鸣 + 水声 | 颂钵基频 256Hz, 3-5 秒触发一次; 水声: filtered noise @ 500Hz, Q=0.5 |
| Neutral (0.3-0.6) | 颂钵减弱 + 微风 | 颂钵振幅 × attention; 风声 center=1200Hz, Q=0.8 |
| Distracted (att < 0.3) | 静默 → 干涩风声 | 颂钵停止; 风声 center=3000Hz, Q=2.0（刺耳的高频风） |
| Binaural Beat | 15Hz | 基础频率 200Hz, 振幅 0.3（subliminal） |

#### 4.1.5 Feedback Mapping（注意力 0.0 → 1.0）

| Attention 范围 | 视觉状态 | 音频状态 |
|---------------|---------|---------|
| 0.0-0.2 | 莲花完全闭合，水面静止（无涟漪），画面暗淡（整体亮度 × 0.4） | 完全静默（1 秒后渐入干涩风声） |
| 0.2-0.4 | 花蕊微弱发光（SSVEP 可见），水面极微弱波动 | 风声渐入，颂钵偶尔触发（10 秒一次） |
| 0.4-0.6 | 外层花瓣微微松动（角度 5°-15°），水面出现稀疏涟漪 | 颂钵 5 秒一次，水声渐入 |
| 0.6-0.8 | 外+中层花瓣展开（角度 30°-45°），涟漪活跃 | 颂钵 3 秒一次，水声正常 |
| 0.8-1.0 | 三层花瓣全开（60°），涟漪密集，花粉粒子释放，画面亮度恢复 | 颂钵 2 秒一次，水声丰满，binaural beat 全功率 |

**过渡动画时间约束：**
- 任意状态间过渡：≤ 2 秒（使用 exponential ease）
- 走神时花瓣闭合速度：1.5 秒（比打开快 2 倍，形成"惩罚感"）

---

### Level 2: 萤火引路（Firefly Path）

#### 4.2.1 场景描述

迷雾笼罩的黑暗森林，远处有一座古老石碑。萤火虫群在画面中央缓慢游荡。雾气随注意力变化而浓淡。

#### 4.2.2 SSVEP 配置

| 参数 | 值 | 说明 |
|------|---|------|
| Target 频率 | 15Hz | 萤火虫群整体亮度调制 |
| Target 颜色 | #CDDC39（生物荧光绿） | 粒子群整体透明度 60%~100% 正弦波动 |
| Distractor | 无 | 视觉耐力训练 |
| Target 几何 | 粒子群聚集区域 | 中心密集，边缘稀疏，半径 ~150px |

#### 4.2.3 Metal Shader 规格

**迷雾 Shader（Fog）：**

```metal
// 迷雾实现：多层噪声叠加 + 径向渐变透明度
// 
// 不是 volumetric fog（GPU 开销太大）
// 而是 layered transparency：4-6 层半透明 fog texture
// 每层使用不同速度的 Perlin noise 位移
//
// Fog 参数：
// - 基础颜色：#0A0F1E（深蓝黑）
// - 4 层 fog，每层 opacity 0.3-0.5
// - 每层独立的 noise offset 速度：0.01-0.03 UV/s
// - 整体 fog opacity = baseFogDensity * (1.0 - attention.value)
// - attention = 1.0 → fog 几乎透明（能看清石碑）
// - attention = 0.0 → fog 完全不透明（只能看到近处萤火虫）
//
// Noise 实现：简化版 Perlin noise（value noise + interpolation）
// 或使用预计算的 noise texture（256×256，R8 格式）

fragment float4 fogLayer(VertexOut in [[stage_in]],
                         constant FogParams& params [[buffer(0)]],
                         constant AttentionState& attention [[buffer(1)]],
                         texture2d<float> noiseTexture [[texture(0)]],
                         sampler noiseSampler [[sampler(0)]]) {
    
    float2 uv = in.uv;
    float time = params.time;
    
    // 多层噪声采样
    float noise1 = noiseTexture.sample(noiseSampler, uv * 2.0 + float2(time * 0.01, 0)).r;
    float noise2 = noiseTexture.sample(noiseSampler, uv * 4.0 + float2(0, time * 0.015) + 10.0).r;
    float noise3 = noiseTexture.sample(noiseSampler, uv * 8.0 + float2(time * 0.02, time * 0.01) + 20.0).r;
    
    float combinedNoise = noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2;
    
    // 注意力控制迷雾浓度
    float fogDensity = params.baseDensity * (1.0 - attention.value * 0.85);
    // attention = 1.0 → fogDensity = baseDensity * 0.15（极淡）
    // attention = 0.0 → fogDensity = baseDensity * 1.0（全浓）
    
    float fogAlpha = combinedNoise * fogDensity;
    float3 fogColor = float3(0.04, 0.06, 0.12);  // #0A0F1E
    
    return float4(fogColor, fogAlpha);
}
```

**树木剪影（Tree Silhouettes）：**

```swift
// 树木实现：不是 3D mesh，而是 2D 剪影
// 
// 方案：预渲染的 silhouette texture + distance fog blending
// - 预渲染 5-8 棵不同形状的树（PNG with alpha）
// - 分布在画面两侧和前景
// - 越远的树越暗（被 fog 遮盖更多）
// - 树木微微摇摆（vertex displacement，±2°，0.1Hz 正弦）
//
// 或者：shader-based procedural tree silhouettes
// - 使用 fractal branching algorithm
// - 但 demo 阶段推荐预渲染纹理方案（更可控）
//
// 树木颜色：纯黑 #000000 或 #050505（比背景稍亮，形成剪影）
```

**萤火虫粒子系统（Firefly Particles）：**

```swift
// 萤火虫参数：
//
// 粒子数量：
// - 最小：300（attention = 0.0）
// - 最大：800（attention = 1.0）
// - 动态增减：每帧 ±2 粒子
//
// 粒子属性：
// - 大小：3-8px（Point Sprite，带 Gaussian glow）
// - 颜色：#CDDC39（生物荧光绿）→ #8BC34A（浅绿）随机
// - 亮度：SSVEP 调制，15Hz 正弦波，opacity 范围 0.5-1.0
// - 发光半径：每个粒子额外渲染一个 20-30px 的 radial gradient glow
//
// 运动模式（Perlin noise wandering）：
// - 使用 2D Perlin noise field 驱动运动方向
// - Noise field 随时间缓慢变化（flow field）
// - 粒子速度：10-30 px/s
// - 边界处理：粒子离开屏幕边缘后从对侧重新进入（toroidal wrapping）
// - 聚集行为：粒子有轻微的向中心聚集倾向（attraction force = 0.5 px/s²）
//   attention 越高，聚集越紧密（force = 0.5 * attention）
//
// Perlin noise field 参数：
// - Grid size: 32×32 cells
// - Noise scale: 0.05（smooth, large-scale flow）
// - Time evolution: 0.001 per frame
// - 每个粒子查询其所在 cell 的 noise angle，作为运动方向
//
// 渲染：
// - 使用 Metal compute shader 更新粒子位置
// - 使用 point sprite + additive blending 渲染
// - 每个 point sprite 使用 radial gradient texture（中心亮，边缘透明）
// - Glow pass：将萤火虫 render 到一个低分辨率 buffer（1/4），blur 后 overlay

struct FireflySystem {
    let maxParticles: Int = 1000  // buffer 大小
    let minParticles: Int = 300
    let maxActiveParticles: Int = 800
    
    // GPU buffer layout (per particle):
    // [0]: position.x (Float)
    // [1]: position.y (Float)
    // [2]: velocity.x (Float)
    // [3]: velocity.y (Float)
    // [4]: size (Float)
    // [5]: brightness (Float) — 被 SSVEP 调制
    // [6]: color variation (Float) — 0..1 映射到绿色渐变
    // [7]: life (Float) — 0..1
}
```

**石碑（Ancient Stone Tablet）：**

```swift
// 石碑参数：
// - 位置：画面中心偏上（0.5, 0.35）
// - 大小：屏幕宽度 15%，高度 25%
// - 几何：简单的梯形（上窄下宽），预渲染纹理
// - 石碑颜色：#2C2C2C（深灰）→ #1A1A1A（暗灰）
// - 表面纹理：细微的 noise bump（凹凸感）
//
// 符文显现系统：
// - 石碑上有 5-7 个符文位置
// - 每个符文初始为完全暗淡（opacity = 0）
// - 当 attention 持续 > 0.7 时，符文逐个亮起
// - 每个符文需要 attention > 0.7 持续 5 秒
// - 符文颜色：#CDDC39（与萤火虫同色，呼应主题）
// - 符文亮起时有微弱的发光 pulse（2Hz，非 SSVEP）
// - 所有符文亮起 = 关卡完成
//
// 符文几何：
// - 简单的圆形/菱形/三角形组合（不需要真实的古老文字）
// - 每个符文由 3-5 个基础几何形状组成
// - 使用 stencil buffer 或单独的 render pass 绘制
```

#### 4.2.4 音频规格

| 状态 | 音色 | 参数 |
|------|------|------|
| Focused (att > 0.6) | 风铃 + 森林环境音 | 风铃 avgInterval=3s; 森林: noise @ 1kHz, Q=0.5, + bird chirps（sine bursts @ 3000-5000Hz, random） |
| Neutral (0.3-0.6) | 风铃减弱 + 风声 | 风铃 avgInterval=5s; 风声 center=1500Hz |
| Distracted (att < 0.3) | 密集风声 + 枯叶 | 风声 center=2500Hz, Q=1.5; 枯叶: noise @ 4kHz, Q=3.0, burst every 0.5s |
| Binaural Beat | 15Hz | 基础频率 200Hz |

#### 4.2.5 Feedback Mapping

| Attention | 迷雾密度 | 萤火虫亮度 | 可视距离 | 石碑可见度 | 音频 |
|-----------|---------|-----------|---------|-----------|------|
| 0.0-0.2 | 100%（几乎不可见） | 30%（微弱闪烁） | 仅眼前 50px | 完全不可见 | 干涩风声 + 枯叶摩擦 |
| 0.2-0.4 | 70% | 50% | 150px | 隐约轮廓 | 风声渐入 |
| 0.4-0.6 | 40% | 70% | 300px | 石碑形状可见，符文不可见 | 风铃开始 |
| 0.6-0.8 | 20% | 85% | 500px | 符文开始显现 | 风铃 + 森林 |
| 0.8-1.0 | 10%（几乎透明） | 100%（满亮） | 全屏 | 符文逐个亮起 | 丰满环境音 + binaural |

---

### Level 3: 星图寻迹（Star Map Tracing）

#### 4.3.1 场景描述

满天繁星的夜空，隐约有星座虚线连接。SSVEP target 和 distractor 首次同时出现。

#### 4.3.2 SSVEP 配置

| 参数 | Target | Distractor |
|------|--------|------------|
| 频率 | 15Hz | 20Hz |
| 颜色 | #FFE9A6（暖黄） | #8AB4F8（幽冷蓝） |
| 闪烁方式 | 透明度 60%~100% 正弦 | 透明度 70%~100% 正弦 |
| 几何 | 大号星点（8-12px） | 小号星点（2-4px） |
| 数量 | 5-7 颗（依次亮起） | 500-1500 颗（背景星空） |

#### 4.3.3 Metal Shader 规格

**星空（Star Field）：**

```swift
// 星空参数：
//
// 背景星（Distractor, 20Hz）：
// - 数量：2000 颗
// - 大小：1-3px
// - 颜色：#8AB4F8（幽冷蓝）为主，5% 随机为白色
// - 闪烁：20Hz 正弦调制，但幅度很小（opacity 0.7-1.0）
// - 分布：均匀随机，排除 target 星附近的 80px 区域
// - 使用 point sprite 渲染
//
// Target 星（15Hz）：
// - 数量：5-7 颗（构成一个星座）
// - 大小：8-12px + 外圈 glow（30px radial gradient）
// - 颜色：#FFE9A6（暖黄）
// - 闪烁：15Hz 正弦调制，幅度明显（opacity 0.5-1.0）
// - 当前 active target 有额外的高亮环（2px white border）
//
// 星座连线：
// - 初始状态：虚线，opacity 0.2
// - 当 attention 成功锁定当前 target（SSVEP > threshold 持续 3s）：
//   - 当前 target 爆出强光（brightness pulse，0.5s）
//   - 连线从当前 target 向下一 target 延伸（1s 动画）
//   - 连线变为实线，opacity 0.8
//   - active target 自动切换到下一颗
// - 走神时：正在延伸的连线断裂（0.3s），需要重新锁定
//
// 连线渲染：
// - 使用 Metal line primitive + additive blending
// - 连线颜色：#FFE9A6 @ 0.6 opacity
// - 连线宽度：2px
// - 延伸动画：从起点到终点的 progress（0→1），使用 ease-out curve
// - 断裂效果：line opacity 从 0.8 → 0.0（0.3s），同时产生 3-5 个碎片粒子

// 星座完成动画（"灵兽"）：
// - 所有连线完成后，整个星座闪烁 3 次（1Hz，持续 3s）
// - 星座轮廓产生光晕，然后一个"灵兽"的抽象光影从星座中跃出
// - 灵兽形状：由星座连线组成的简化动物轮廓（如鹿/鹤/龙）
// - 灵兽材质：纯发光线条 + additive blending
// - 灵兽动画：从星座位置向上飘升，逐渐变大、变淡（3s）
// - 之后进入 Level 4
```

#### 4.3.4 音频规格

| 状态 | 音色 |
|------|------|
| Focused on target | 大提琴 drone（C3=130.81Hz）+ 水晶般的高频泛音（sine @ 3000Hz, 5Hz tremolo） |
| Switching target | 短促的 ascending tone（C5→E5→G5, 每个 200ms） |
| Distracted | 大提琴 drone 渐弱，风声渐入 |
| 连线成功 | 清脆"叮"声（sine @ 2400Hz, 100ms decay） |
| 星座完成 | 三音和弦（C4+E4+G4, 1s sustain, 2s decay） |
| Binaural Beat | 15Hz（基础 200Hz） |

#### 4.3.5 Feedback Mapping

| 事件 | 视觉 | 音频 |
|------|------|------|
| 注视 target A（SSVEP > threshold） | A 亮度增强，光晕扩大 | 大提琴 drone + 高频泛音 |
| SSVEP 掉零（走神） | 连线延伸停止，A 暗淡 | drone 渐弱 |
| 锁定成功（3s 持续） | A 爆光 → 连线延伸到 B | "叮" + ascending tone |
| 连线断裂 | 连线碎裂粒子 | 低沉"嗡"（80Hz, 200ms） |
| 星座完成 | 灵兽跃出 | 和弦 + 颂钵共鸣 |

---

### Level 4: 真假萤火（True & False Fireflies）

#### 4.4.1 场景描述

森林中有两种颜色的萤火虫同时飞舞。画面中央有一棵"生命之树"。这是第一个引入 SSVEP 竞争机制的关卡。

#### 4.4.2 SSVEP 配置

| 参数 | Target（真） | Distractor（假） |
|------|-------------|-----------------|
| 频率 | 15Hz | 20Hz |
| 颜色 | #CDDC39 → #8BC34A（黄绿） | #64B5F6 → #1E88E5（蓝色） |
| 闪烁 | 60%~100% 正弦，幅度大 | 60%~100% 正弦，幅度略小 |
| 粒子数 | 200-400 | 200-400 |
| 大小 | 4-8px + glow | 4-8px + glow |
| 分布 | 整个屏幕随机游荡 | 整个屏幕随机游荡，偶尔靠近 target |

#### 4.4.3 Metal Shader 规格

**双粒子系统：**

```swift
// 两个独立的粒子系统，使用相同的 motion algorithm 但不同颜色和 SSVEP 参数
//
// 绿色萤火（Target）：
// - Compute Shader: firefly_green
// - SSVEP modulation: 15Hz on overall brightness
// - Noise field: shared with blue fireflies（同一场域）
// - Movement: Perlin noise wandering, 15-35 px/s
//
// 蓝色萤火（Distractor）：
// - Compute Shader: firefly_blue
// - SSVEP modulation: 20Hz on overall brightness
// - Noise field: same grid, slightly offset（偏移 5 个 cell）
// - Movement: Perlin noise wandering, 12-28 px/s（稍慢）
// - 偶尔"诱饵"行为：5% 的概率突然加速靠近绿色萤火群（模拟干扰）
//
// 竞争指数计算：
// competitionScore = greenSSVEPPower / (greenSSVEPPower + blueSSVEPPower)
// - > 0.6：用户注意力偏向 target = "focused"
// - 0.4-0.6：不确定状态 = "neutral"
// - < 0.4：用户注意力偏向 distractor = "distracted"
// 
// 注意：demo 模式下使用模拟数据：
// - 模拟 competitionScore 在 0.3-0.9 之间缓慢随机游荡
// - 每 2-4 秒变化一次（模拟真实 EEG 的响应延迟）
```

**生命之树（Tree of Life）：**

```swift
// 生命之树是整个关卡的视觉焦点和进度指示器
//
// 位置：画面正中央
// 大小：屏幕高度 60%，宽度 30%
//
// 树的组成部分（从下到上）：
// 1. 树根（Roots）：3-5 条曲线从树干底部向两侧延伸
//    - 宽度：5-15px
//    - 颜色：#5D4037（深棕）
//    - 随 competitionScore 增长：根变粗、延伸更远
//
// 2. 树干（Trunk）：中央的主干
//    - 宽度：20-40px（随 competitionScore 变化）
//    - 颜色：#4E342E → #795548（棕色渐变）
//    - 纹理：vertical noise stripes
//
// 3. 树枝（Branches）：从树干分叉的 8-12 条枝干
//    - 分形结构：每条主枝有 2-3 条次级分枝
//    - 随 competitionScore 增长：枝干延伸、次级分枝出现
//    - 使用 L-system 算法生成（简单版本）
//
// 4. 树叶（Leaves）：覆盖在枝干上的绿色粒子
//    - 数量：0-500（随 competitionScore 增长）
//    - 颜色：#4CAF50（绿）→ #81C784（浅绿）→ #FFC107（秋黄，当 competition 下降时）
//    - 使用 point sprite 渲染
//
// 5. 树冠光晕（Canopy Glow）：树冠上方的柔和发光
//    - 颜色：#CDDC39（黄绿）@ 0.2 opacity
//    - 大小：随 competitionScore 增大
//
// 枯萎动画（competition < 0.4）：
// - 树叶颜色从绿变黄 → 变棕 → 掉落（粒子重力下落）
// - 树枝裂纹出现（白色线条，随机位置）
// - 树干变灰（#795548 → #9E9E9E）
// - 树根缩回（宽度减小，延伸缩短）
// - 最终：树变成灰色枯木 + 散落的枯叶
//
// 生长/枯萎的时间常数：
// - 生长：competition > 0.6 持续时，树每 5 秒长一级
// - 枯萎：competition < 0.4 时，树每 3 秒枯一级（枯萎速度更快 = 惩罚）

struct TreeOfLife {
    enum GrowthStage: Int, CaseIterable {
        case seed = 0       // 只有种子（小土丘）
        case sprout = 1     // 嫩芽（小绿芽）
        case sapling = 2    // 幼苗（细树干 + 2 条枝）
        case young = 3      // 小树（4-6 条枝 + 少量叶）
        case mature = 4     // 成树（8-12 条枝 + 丰满叶冠）
        case ancient = 5    // 古树（最大形态 + 光晕 + 花朵）
    }
    
    let currentStage: GrowthStage
    let growthProgress: Float  // 0.0-1.0，当前阶段的进度
}
```

#### 4.4.4 音频规格

| 状态 | 音色 |
|------|------|
| Competition > 0.6（偏向 target） | 大提琴 drone（丰满）+ 颂钵（3s 间隔）+ 绿色萤火的微弱"嗡嗡"音（200Hz sine, 0.05 amplitude） |
| 0.4 < Competition < 0.6（不确定） | 大提琴 drone（减弱）+ 风声渐入 |
| Competition < 0.4（偏向 distractor） | 风声 + 金属摩擦声（high-pass noise @ 4kHz）+ 树枝断裂声（noise burst, 100ms） |
| 树升级 | ascending arpeggio（C3→E3→G3→C4, 每个 200ms） |
| 树枯萎 | descending tone（G3→E3→C3, 每个 300ms）+ 低频"嗡"（60Hz, 500ms） |
| Binaural Beat | 15Hz（基础 200Hz），当 competition < 0.4 时 amplitude → 0 |

#### 4.4.5 Feedback Mapping

| Competition | 生命之树 | 萤火虫 | 音频 |
|-------------|---------|--------|------|
| 0.0-0.2 | 枯木，灰白色，无叶 | 蓝色萤火极亮，绿色极暗 | 金属摩擦 + 风声 |
| 0.2-0.4 | 树干灰色，裂纹，枯叶掉落 | 蓝色较亮，绿色较暗 | 风声 + drone 减弱 |
| 0.4-0.6 | 小树苗，少量绿叶 | 两种萤火亮度接近 | 微弱 drone |
| 0.6-0.8 | 中等树，枝叶生长中 | 绿色较亮，蓝色较暗 | drone + 颂钵 |
| 0.8-1.0 | 大树，丰满叶冠 + 光晕 | 绿色极亮，蓝色极暗 | 丰满 drone + 颂钵 + 环境音 |

---

### Level 5: 飞燕破云（Swallow Breaking Clouds）

#### 4.5.1 场景描述

暴风雨夜航。天空中雷电交加（20Hz distractor），一只"引路灵燕"在云间穿行（15Hz target）。用户需要追踪灵燕的移动。

#### 4.5.2 SSVEP 配置

| 参数 | Target（灵燕） | Distractor（雷电） |
|------|--------------|-------------------|
| 频率 | 15Hz | 20Hz |
| 颜色 | #FFE9A6（暖黄光） | #E1F5FE（冷白蓝光） |
| 闪烁 | 整体亮度 50%~100% 正弦 | 整体亮度 70%~100% 正弦 |
| 运动 | 正弦曲线飞行轨迹（用户需追踪） | 从随机云位闪烁 |
| 大小 | 40×20px（鸟形轮廓） | 200-400px（闪电光柱，随机方向） |

#### 4.5.3 Metal Shader 规格

**灵燕（Guide Swallow）：**

```swift
// 灵燕运动轨迹：
// - 基础路径：水平方向从左到右的缓慢移动（30 px/s）
// - 叠加正弦波：垂直方向 ±100px 的正弦摆动
//   - 频率：0.15Hz（约 6.7 秒一个完整周期）
//   - 幅度：随关卡进度递增（初始 ±60px，最终 ±150px）
// - 偶尔的"急转弯"：每 10-15 秒，灵燕突然改变方向（±45°）
//   - 转弯持续 1 秒，然后回到正弦路径
//
// 灵燕渲染：
// - 不是照片级鸟的图像
// - 而是一个由 20-30 个粒子组成的"鸟形"轮廓
// - 粒子沿鸟的轮廓分布（V 形翅膀 + 尾巴）
// - 每个粒子 3-5px，#FFE9A6 颜色
// - 整体有微弱的 motion trail（10 个历史位置，opacity 递减）
// - SSVEP 15Hz 调制整体亮度
//
// 灵燕粒子分布（简化鸟形）：
//        *           <- 头部 (1 粒子)
//       / \
//      /   \         <- 翅膀前缘 (每侧 5 粒子)
//     /     \
//    /   *   \       <- 身体 (1 粒子)
//     \     /
//      \   /         <- 翅膀后缘 (每侧 4 粒子)
//       \ /
//        *           <- 尾巴 (3 粒子)
// 总计约 25 个粒子
```

**雷暴云（Storm Clouds）：**

```swift
// 雷暴云实现：
// - 不是 volumetric rendering（太慢）
// - 而是 3-5 层半透明 noise texture 叠加
// - 每层使用不同的 noise offset 速度和 scale
//
// Cloud 参数：
// - 颜色：#1A1A2E（暗紫蓝）→ #2C3E50（深灰蓝）
// - 每层 opacity：0.3-0.6
// - Noise scale：大（cloud 级别的 noise，不是 detail 级别）
// - 移动速度：0.02-0.05 UV/s（缓慢飘动）
// - Cloud 覆盖屏幕上 60% 的面积
//
// 闪电（Lightning）：
// - 触发：每 3-8 秒随机一次（Poisson process，均值 5s）
// - 持续时间：100-200ms
// - 形状：从云层某点向下的分叉闪电线
//   - 主干：1 条直线（起点→终点）
//   - 分叉：2-4 条，从主干 30-70% 位置分出
//   - 分叉角度：20°-60° 随机
// - 亮度：全屏 flash（screen opacity 瞬间 0.3→0），然后闪电线淡出
// - SSVEP：20Hz 整体亮度调制（与 distractor 频率同步）
// - 颜色：#E1F5FE（冷白蓝）
//
// 闪电渲染（CPU 端预计算 + Metal 绘制）：
// 1. 随机选择云层中的一个起点
// 2. 随机选择一个向下的终点
// 3. 生成主干 + 分叉路径（贝塞尔曲线）
// 4. 转换为 Metal line primitives
// 5. 使用 additive blending + blur post-process
```

**雨粒子（Rain）：**

```swift
// 雨粒子参数：
// - 数量：1000-2000
// - 大小：1-2px（细长的线段，不是点）
// - 长度：5-15px（受"风力"影响）
// - 颜色：#B0BEC5（灰蓝）@ 0.3-0.5 opacity
// - 方向：倾斜 15°-30°（模拟风吹）
// - 速度：500-800 px/s（快速下落）
// - 使用 Metal instanced rendering（所有雨滴共享一个 geometry）
//
// 雨滴是背景装饰，不参与 SSVEP 交互
// 但雨的密度可以随 attention 变化：
// - attention 高：雨减小（50% 密度），"破云而出"的感觉
// - attention 低：雨增大（100% 密度），"被暴风雨吞没"的感觉
```

**Screen Shake（屏幕震动）：**

```swift
// 当用户被闪电吸引（attention < 0.3）时触发
// 
// Screen shake 参数：
// - 持续时间：0.5-1.0s
// - 震动幅度：±5-15px（X 和 Y 方向独立）
// - 震动模式：随机噪声（不是正弦波），用 perlin noise 驱动
// - 衰减：exponential decay（从最大振幅到 0）
//
// 实现方式：
// - 在 Metal vertex shader 中对所有顶点施加 uniform offset
// - offset = shakeOffset * (1.0 - exp(-3.0 * elapsed))
// - shakeOffset 在 CPU 端用 perlin noise 每帧更新
//
// Blur 效果：
// - 当 attention < 0.3 持续 > 1s 时叠加
// - 使用一个 1/4 分辨率的 blur pass（高斯模糊，radius 3-5px）
// - Blur intensity 随走神持续时间增加（0→1 over 3s）
// - attention 恢复后 blur 在 0.5s 内消失
```

#### 4.5.4 音频规格

| 状态 | 音色 |
|------|------|
| 追踪灵燕（att > 0.6） | 大提琴 drone（强）+ 有节奏的风铃（1s 间隔）+ 微弱雨声 |
| 灵燕急转弯 | 短促的弦乐 glissando（上滑 0.3s） |
| 被闪电吸引（att < 0.3） | 雷声（low noise burst @ 40Hz, 500ms）+ 暴风（full storm wind）+ screen shake audio transient |
| 闪电闪烁 | 雷声（每次闪电都伴随，即使 attention 正常） |
| 雨声 | 始终存在，filtered noise @ 2kHz, Q=0.3 |
| Binaural Beat | 15Hz（基础 200Hz），att < 0.3 时 fade to 0 |

#### 4.5.5 Feedback Mapping

| 状态 | 视觉 | 音频 |
|------|------|------|
| 追踪灵燕 | 灵燕清晰，云层稀疏，雨小，视野稳定 | drone + 风铃 + 微雨 |
| 走神（被闪电吸引） | 灵燕模糊，云层密集，screen shake，blur | 雷声 + 暴风 + 颠簸感 |
| 灵燕转弯 | 灵燕轨迹变化（考验追踪能力） | glissando 提示 |
| 长时间专注 | 云层逐渐散开，露出星空碎片 | drone 增强 + 星空般的泛音 |

---

### Level 6: 流星试炼（Meteor Trial）

#### 4.6.1 场景描述

极简场景：雪山夜空，山巅一颗孤星。没有任何周期性 SSVEP distractor——所有干扰都是瞬态的（流星、极光、飞鸟），考验的是"抵御诱惑"的执行控制能力。

#### 4.6.2 SSVEP 配置

| 参数 | Target（孤星） | Distractor（流星等） |
|------|--------------|---------------------|
| 频率 | 15Hz | **无 SSVEP 频率**（纯视觉诱惑） |
| 颜色 | #FFE9A6（暖黄）→ #FFFFFF（白，满月时） | 流星:#FFFFFF, 极光:#00E676/#FF4081, 飞鸟:#000000(剪影) |
| 闪烁 | 整体亮度 60%~100% 正弦 | 无周期闪烁 |
| 位置 | 固定：屏幕中上方（0.5, 0.25） | 随机穿越视野 |

#### 4.6.3 Metal Shader 规格

**极简场景构成：**

```swift
// Layer 0: 天空背景
// - 纯色渐变：顶部 #0A0A1A（近黑）→ 底部 #1A1A3E（深蓝紫）
// - 无星星（极简），只有 target 星
//
// Layer 1: 雪山剪影
// - 简单的三角形/梯形组合（3-5 个山尖）
// - 颜色：#0D0D15（比天空更黑）
// - 山顶积雪：#2A2A3A（微亮），使用简单的 noise 描边
// - 占屏幕下方 25%
//
// Layer 2: 孤星 → 满月
// - 初始状态：一颗 8px 的星点 + 30px glow
// - 随 focus 持续时间增长：
//   0-10s: 星点 → 新月（crescent）
//   10-20s: 新月 → 上弦月（half）
//   20-30s: 上弦月 → 凸月（gibbous）
//   30s+: 凸月 → 满月（full moon, 40px diameter）
// - 满月效果：屏幕整体获得微弱的月光照明（ambient light level +0.1）
//
// 月相渲染：
// - 使用两个圆形（亮面 + 暗面）的 clip/mask 操作
// - 亮面颜色：#FFF8E1（暖白）
// - 暗面颜色：#1A1A2E（背景色）
// - 过渡动画：亮面圆心相对于暗面圆心平移（产生月相变化效果）
// - 月球表面纹理：可选，使用 2-3 个暗色 circle 作为 "craters"
//
// 月亮裂纹（走神惩罚）：
// - 走神时在月亮表面添加裂纹纹理
// - 裂纹：3-5 条不规则线条，从月亮边缘向中心延伸
// - 颜色：#FF1744（暗红）@ 0.5 opacity
// - 裂纹数量 = 走神次数
// - 裂纹修复：每次持续专注 10s，修复一条裂纹
// - 所有裂纹修复后才能继续满月进度
//
// 乌云遮月（走神惩罚）：
// - 走神时乌云从月亮一侧飘过
// - 乌云：半透明灰色椭圆（#424242 @ 0.6 opacity）
// - 飘过时间：2s
// - 飘过后月亮被部分遮挡（0.3-0.7 random）
// - 乌云散去：1s fade out
```

**流星（Meteors — 瞬态诱惑）：**

```swift
// 流星参数：
// - 触发频率：每 4-10 秒一颗（Poisson process，均值 6s）
// - 但不使用 SSVEP 频率闪烁（关键区别！）
// - 流星是一条明亮的白色/浅蓝线段，快速划过视野
//
// 流星运动：
// - 起始位置：屏幕边缘随机（上/左/右）
// - 方向：大致从右上到左下（模拟真实流星），±30° 随机偏移
// - 速度：800-1500 px/s（极快）
// - 长度：50-200px（尾迹）
// - 持续时间：100-300ms
//
// 流星渲染：
// - 头部：5px 明亮白点
// - 尾迹：从白到透明的渐变线段
// - 使用 additive blending
// - 流星经过时对周围 100px 范围产生微弱照亮（screen flash, 0.1 opacity）
//
// 关键设计决策：
// 流星不使用 20Hz 闪烁！
// 这是 Level 6 的核心——干扰不是 SSVEP distractor，
// 而是纯粹的视觉诱惑。
// SSVEP 算法无法检测到用户是否被流星吸引，
// 只能通过 target（15Hz 孤星）的 SSVEP 功率下降来判断。
// 这测试的是执行控制（executive control），不是频率选择性注意。
```

**极光（Aurora — 持续诱惑）：**

```swift
// 极光参数：
// - 位置：屏幕边缘（上 1/3 区域）
// - 触发条件：attention 持续 > 0.7 超过 20s 后开始出现
// - 持续时间：10-15s
// - 目的：作为"奖励性干扰"——你专注得越好，极光越美，越容易分心
//
// 极光渲染（shader-based）：
// - 多条（3-5）半透明的弯曲光带
// - 每条光带是一个正弦波变形的矩形
// - 光带参数：
//   - 宽度：30-80px
//   - 颜色：#00E676（绿）→ #FF4081（粉）→ #7C4DFF（紫）渐变
//   - 透明度：0.1-0.3（subtle）
//   - 运动：缓慢波动（0.05Hz 正弦波调制 Y 偏移）
//   - 颜色变化：每条光带的颜色沿 X 轴缓慢渐变
//
// 极光 shader（simplified aurora）：
// float auroraIntensity = sin(uv.x * 3.0 + time * 0.3) * 0.5 + 0.5;
// auroraIntensity *= smoothstep(0.0, 0.1, uv.y) * smoothstep(0.4, 0.2, uv.y);
// float3 auroraColor = mix(green, purple, sin(uv.x * 2.0 + time * 0.1) * 0.5 + 0.5);
// float auroraAlpha = auroraIntensity * 0.15;
```

**飞鸟（Flying Birds — 瞬态干扰）：**

```swift
// 飞鸟参数：
// - 触发频率：每 8-15 秒一群（Poisson process，均值 10s）
// - 数量：3-7 只鸟
// - 形状：简单的 V 形（两个 wing points + body point），剪影
// - 颜色：#000000（纯黑剪影）
// - 大小：15-30px（翼展）
// - 运动：从一侧飞到另一侧，正弦波上下摆动
// - 速度：100-200 px/s（比流星慢得多，更容易吸引注意）
// - 持续时间：3-6 秒（跨越屏幕）
//
// 飞鸟不是 SSVEP 干扰！
// 和流星一样，是纯粹的视觉诱惑。
// 飞鸟的缓慢运动比流星更容易吸引眼球（smooth pursuit reflex）。
```

#### 4.6.4 音频规格

| 状态 | 音色 |
|------|------|
| 持续专注（30s+） | 极简：单一颂钵泛音（256Hz fundamental, 长 sustain, 无衰减）+ 极微弱的风声（noise @ 800Hz, amplitude 0.05） |
| 走神 | 颂钵泛音消失 → 极静（只有最微弱的呼吸般的风声，amplitude 0.02） |
| 流星划过 | 无音频（无声的视觉诱惑——让视觉干扰更"纯净"） |
| 极光出现 | 极微弱的 shimmer 音效（high-frequency sine @ 5000Hz, tremolo 8Hz, amplitude 0.03） |
| 飞鸟飞过 | 微弱的翅膀扇动声（noise burst @ 200Hz, 50ms, 每 0.5s 一次，持续 3-6s） |
| 月相升级 | 柔和的 ascending tone（C4→G4, 2s） |
| 月亮裂纹 | 低沉的"咔"声（noise burst @ 100Hz, 50ms） |
| Binaural Beat | 15Hz（基础 200Hz），att < 0.3 时 fade to 0 |

#### 4.6.5 Feedback Mapping

| 事件 | 视觉 | 音频 |
|------|------|------|
| 持续专注 0-10s | 星点 → 新月 | 颂钵泛音渐入 |
| 持续专注 10-20s | 新月 → 上弦月 | 颂钵泛音持续 |
| 持续专注 20-30s | 上弦月 → 凸月 | ascending tone |
| 持续专注 30s+ | 凸月 → 满月 + 月光 | 颂钵全功率 |
| 走神（SSVEP drop） | 月亮裂纹 / 乌云遮月 | 颂钵消失 + "咔" |
| 修复裂纹（专注 10s） | 一条裂纹消失 | 颂钵重新渐入 |
| 流星划过 | 明亮线条穿越视野 | 无声（纯粹视觉诱惑） |
| 极光出现 | 边缘光带缓慢飘动 | 极微弱 shimmer |
| 飞鸟经过 | 黑色剪影穿越 | 微弱翅膀声 |

#### 4.6.6 满月进度追踪

```swift
/// 满月进度系统
/// Level 6 的"通关"条件：累计专注达到满月状态
///
/// 数据结构：
struct MoonProgress {
    var totalFocusSeconds: Float = 0.0       // 累计专注秒数
    var currentFocusStreak: Float = 0.0      // 当前连续专注秒数
    var crackCount: Int = 0                  // 当前裂纹数
    var maxCrackCount: Int = 5               // 最大裂纹数
    var moonPhase: MoonPhase = .star         // 当前月相
    var bestFocusStreak: Float = 0.0         // 历史最长连续专注
    var meteorResistCount: Int = 0           // 成功抵御流星次数（estimated）
    var distractionCount: Int = 0            // 走神次数
}

enum MoonPhase: Float {
    case star = 0.0         // 孤星
    case crescent = 0.25    // 新月
    case half = 0.5         // 上弦月
    case gibbous = 0.75     // 凸月
    case full = 1.0         // 满月
}

/// 每帧更新逻辑（伪代码）：
/// if attention > 0.7:
///     currentFocusStreak += deltaTime
///     totalFocusSeconds += deltaTime
///     moonPhase = calculateMoonPhase(totalFocusSeconds)
///     // 每 10s 修复一条裂纹
///     if currentFocusStreak > 10.0 && crackCount > 0:
///         crackCount -= 1
///         currentFocusStreak -= 10.0  // 重置裂纹修复计时
/// else if attention < 0.3:
///     distractionCount += 1
///     crackCount = min(crackCount + 1, maxCrackCount)
///     currentFocusStreak = 0.0
///     // 月亮回退：裂纹 > 3 时，moonPhase 退一档
///     if crackCount > 3:
///         moonPhase = max(moonPhase - 1, .star)
```

---

## 附录：Demo 模式模拟数据规格

所有关卡的 demo 模式使用 `SimulatedAttentionSource` 替代真实 EEG 数据：

```swift
/// 模拟注意力数据源
/// 生成逼真的注意力波动曲线
final class SimulatedAttentionSource {
    
    /// 模拟模式
    enum Mode {
        case autoPlay      // 自动演示：注意力在 0.3-0.9 之间缓慢正弦波动
        case randomWalk    // 随机游走：模拟真实用户的注意力波动
        case manual        // 手动控制：通过键盘/滑块控制 attention 值
    }
    
    let mode: Mode
    
    /// Random Walk 参数（模拟真实注意力）：
    // - 步长：每 100ms ±0.05-0.15（随机）
    // - 均值回归：当 attention 偏离 0.6 时，有 0.02 的 pull-back force
    // - 突然走神：每 15-30 秒，attention 突然下降 0.3-0.5（持续 2-5s）
    // - 突然专注：每 20-40 秒，attention 突然上升 0.2-0.4（持续 5-15s）
    // - 噪声：±0.02 的高频随机噪声（模拟 EEG 的自然波动）
    
    // Level 4 额外参数（模拟竞争指数）：
    // - competitionScore 在 0.3-0.9 之间 random walk
    // - 与 attention 有 0.7 的相关性（attention 高 → competition 倾向高）
    // - 加入 ±0.1 的独立噪声
    
    // Level 6 额外参数：
    // - 流星/极光/飞鸟的触发频率不随 attention 变化（始终触发）
    // - 但 distraction 判定（attention < 0.3）的持续时间模拟真实用户
    // - 平均每 20s 有一次"被诱惑"的走神（持续 1-3s）
}
```
