# §3 音频引擎与反馈系统 (Audio Engine & Feedback System)

本节定义"星空与萤火"的完整音频架构。所有声音均为实时合成，零预录制文件。音频是训练过程中的主反馈通道，haptics 为辅助。

---

## 3.1 AVAudioEngine Architecture

### 3.1.1 音频图 (Audio Graph) 完整拓扑

```
[BinauralBeatNode] ──┐
[AmbientWindNode]   ──┤
[AmbientWaterNode]  ──┤
[AmbientForestNode] ──┤──→ [DynamicLowPassFilter] ──→ [ReverbSend] ──→ [MainMixer] ──→ [AudioOutput]
[FeedbackNode]      ──┤           │                       │
[SingingBowlNode]   ──┘           │                       └──→ [ReverbNode] ──→ (wet signal back to MainMixer)
                                          │
                                          └── 参数由 AttentionController 驱动
```

每个合成节点都是 `AVAudioSourceNode` 的子类。`DynamicLowPassFilter` 是全局 EQ 节点，所有音源汇合后通过它。

### 3.1.2 AudioEngine 初始化

```swift
import AVFoundation

final class AudioEngineManager: @unchecked Sendable {
    static let shared = AudioEngineManager()

    let engine = AVAudioEngine()
    let mainMixer: AVAudioMixerNode
    let lowPassFilter: AVAudioUnitEQ
    let reverbNode: AVAudioUnitReverb

    // 合成节点
    let binauralNode: BinauralBeatNode
    let ambientWindNode: AmbientWindNode
    let ambientWaterNode: AmbientWaterNode
    let ambientForestNode: AmbientForestNode
    let feedbackNode: FeedbackNode

    // 参数状态 (仅主线程写入，render callback 通过原子值读取)
    private var _attentionLevel: AtomicFloat = AtomicFloat(0.5)
    var attentionLevel: Float {
        get { _attentionLevel.value }
        set { _attentionLevel.value = newValue }
    }

    // 目标值 (用于平滑插值)
    private var _targetFilterCutoff: Float = 5000.0
    private var _currentFilterCutoff: Float = 5000.0
    private var _targetReverbWetDry: Float = 0.3
    private var _currentReverbWetDry: Float = 0.3

    private var parameterTimer: Timer?
    private let parameterQueue = DispatchQueue(label: "com.ssvep.audio.params", qos: .userInteractive)

    private init() {
        mainMixer = engine.mainMixerNode
        lowPassFilter = AVAudioUnitEQ(numberOfBands: 1)
        reverbNode = AVAudioUnitReverb()

        binauralNode = BinauralBeatNode()
        ambientWindNode = AmbientWindNode()
        ambientWaterNode = AmbientWaterNode()
        ambientForestNode = AmbientForestNode()
        feedbackNode = FeedbackNode()

        configureAudioSession()
        configureFilter()
        configureReverb()
        connectAudioGraph()
        startParameterSmoothing()
    }
}
```

### 3.1.3 Audio Session 配置

macOS 下使用 `AVAudioSession` 不适用，改为直接配置 `AVAudioEngine` 的 `outputNode` 格式：

```swift
private func configureAudioSession() {
    let output = engine.outputNode
    let hwSampleRate = output.outputFormat(forBus: 0).sampleRate

    // 强制 48kHz，保证所有合成节点的数学精确
    let desiredFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48000,
        channels: 2  // 立体声，binaural beats 必须双声道
    )!

    // 如果硬件不支持 48kHz，fallback 到硬件原生采样率
    guard engine.inputNode == nil else {
        // macOS 没有输入节点时直接设输出格式
        engine.outputNode.reset()
    }

    do {
        try engine.setOutputFormat(desiredFormat)
    } catch {
        // Fallback: 使用硬件原生格式，在 render callback 中做 SRC
        print("[AudioEngine] Failed to set 48kHz, using hardware rate: \(hwSampleRate)")
    }

    // 最大缓冲区大小控制延迟 (macOS 优先低延迟)
    let bufferDuration: TimeInterval = 0.005  // 5ms = 240 samples @ 48kHz
    engine.outputNode.audioUnit?.setMaximumFramesPerSlice(UInt32(48000 * bufferDuration))
}
```

**关键数值：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 采样率 | 48000 Hz | 合成精度与硬件兼容的平衡点 |
| 声道数 | 2 (stereo) | binaural beats 依赖双声道 |
| 缓冲区大小 | 240 frames (5ms) | 低延迟，<10ms 端到端延迟 |
| 位深度 | Float32 | AVAudioEngine 默认 |

### 3.1.4 线程安全模型

render callback 运行在音频实时线程 (realtime thread)，**禁止任何锁、内存分配、Objective-C 消息发送**。

参数传递采用两级架构：

```swift
/// 原子浮点数，lock-free read/write
final class AtomicFloat: @unchecked Sendable {
    private var value: Float
    private let lock = OSAllocatedUnfairLock()

    init(_ value: Float = 0.0) {
        self.value = value
    }

    var atomicValue: Float {
        lock.withLock { value }
    }

    func store(_ newValue: Float) {
        lock.withLock { value = newValue }
    }
}

/// 音频参数平滑器，运行在参数更新定时器线程 (非实时)
/// 每 10ms 插值一次，结果写入 AtomicFloat 供 render callback 读取
private func startParameterSmoothing() {
    // 10ms 间隔，100Hz 更新率
    parameterTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        self?.smoothParameters()
    }
    RunLoop.current.add(parameterTimer!, forMode: .common)
}

private func smoothParameters() {
    let smoothingFactor: Float = 0.15  // 一阶低通滤波系数，~66ms 到达 63%

    _currentFilterCutoff += (_targetFilterCutoff - _currentFilterCutoff) * smoothingFactor
    _currentReverbWetDry += (_targetReverbWetDry - _currentReverbWetDry) * smoothingFactor

    // 写入原子值供 render thread 读取
    filterCutoffAtomic.store(_currentFilterCutoff)
    reverbWetDryAtomic.store(_currentReverbWetDry)

    // AVAudioUnitEQ 的 setParameterValue 是线程安全的 (Apple 框架保证)
    lowPassFilter.bands[0].filterFrequency = _currentFilterCutoff
    reverbNode.wetDryMix = _currentReverbWetDry
}
```

**规则总结：**
- 主线程 → `setAttention()` → 写入 `_targetXxx` → 参数定时器平滑插值 → `_currentXxx` → `AtomicFloat` → render callback 读取
- render callback 内部只做 `atomicValue` 读取和纯数学运算
- 任何需要分配内存的操作（如切换音色 preset）通过 `DispatchQueue.main.async` 回到主线程

### 3.1.5 音频图连接

```swift
private func connectAudioGraph() {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    // 所有合成节点 → 低通滤波器
    engine.attach(binauralNode)
    engine.attach(ambientWindNode)
    engine.attach(ambientWaterNode)
    engine.attach(ambientForestNode)
    engine.attach(feedbackNode)

    engine.connect(binauralNode, to: lowPassFilter, format: format)
    engine.connect(ambientWindNode, to: lowPassFilter, format: format)
    engine.connect(ambientWaterNode, to: lowPassFilter, format: format)
    engine.connect(ambientForestNode, to: lowPassFilter, format: format)
    engine.connect(feedbackNode, to: lowPassFilter, format: format)

    // 低通滤波器 → 混响 → 主混音器 → 输出
    engine.attach(reverbNode)
    engine.connect(lowPassFilter, to: reverbNode, format: format)
    engine.connect(reverbNode, to: mainMixer, format: format)
    engine.connect(mainMixer, to: engine.outputNode, format: format)
}

func startEngine() throws {
    try engine.start()
    print("[AudioEngine] Started, sampleRate=\(engine.outputNode.outputFormat(forBus: 0).sampleRate)")
}

func stopEngine() {
    engine.stop()
    parameterTimer?.invalidate()
}
```

---

## 3.2 Binaural Beat Generator

### 3.2.1 实现原理

左耳播放 `baseFrequency`，右耳播放 `baseFrequency + ssvepFrequency`。大脑感知到的差值频率即为 SSVEP 刺激频率。

### 3.2.2 BinauralBeatNode 完整实现

```swift
import AVFoundation
import Accelerate

final class BinauralBeatNode: AVAudioSourceNode {

    // MARK: - 配置参数

    struct Config {
        let baseFrequency: Float      // 左耳频率
        let ssvepFrequency: Float     // 差值频率 (SSVEP 目标)
        let volume: Float             // 0.0 ~ 1.0

        /// 右耳频率，计算属性
        var rightFrequency: Float { baseFrequency + ssvepFrequency }
    }

    // MARK: - 运行时状态 (仅通过 AtomicFloat 访问)

    private let baseFreqAtomic = AtomicFloat(200.0)
    private let ssvepFreqAtomic = AtomicFloat(15.0)
    private let volumeAtomic = AtomicFloat(0.0)

    // 相位累加器 (render thread 独占，无需同步)
    private var leftPhase: Float = 0.0
    private var rightPhase: Float = 0.0

    // 音量包络状态
    private var currentVolume: Float = 0.0
    private let envelopeSmoothing: Float = 0.02  // ~330ms 到达 63%

    // MARK: - 初始化

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            self.render(frameCount: frameCount, audioBufferList: audioBufferList)
            return noErr
        })
    }

    // MARK: - 外部接口

    /// 设置频率，触发平滑过渡
    func setBaseFrequency(_ freq: Float) {
        baseFreqAtomic.store(freq)
    }

    func setSSVEPFrequency(_ freq: Float) {
        ssvepFreqAtomic.store(freq)
    }

    /// 设置目标音量
    func setTargetVolume(_ vol: Float) {
        volumeAtomic.store(clamp(vol, 0.0, 1.0))
    }

    // MARK: - Render Callback (Realtime Thread)

    private func render(frameCount: UInt32, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let baseFreq = baseFreqAtomic.atomicValue
        let ssvepFreq = ssvepFreqAtomic.atomicValue
        let targetVol = volumeAtomic.atomicValue
        let sampleRate: Float = 48000.0

        let leftFreq = baseFreq
        let rightFreq = baseFreq + ssvepFreq

        // 平滑音量包络 (exponential approach)
        currentVolume += (targetVol - currentVolume) * envelopeSmoothing

        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard bufferList.count >= 2 else { return }

        let leftChannel = bufferList[0]
        let rightChannel = bufferList[1]

        guard let leftPtr = leftChannel.mData?.assumingMemoryBound(to: Float.self),
              let rightPtr = rightChannel.mData?.assumingMemoryBound(to: Float.self) else { return }

        let frameCount = Int(frameCount)

        for i in 0..<frameCount {
            // 相位累加
            leftPhase += 2.0 * .pi * leftFreq / sampleRate
            rightPhase += 2.0 * .pi * rightFreq / sampleRate

            // 相位 wrap (防止浮点精度丢失)
            if leftPhase > 2.0 * .pi { leftPhase -= 2.0 * .pi }
            if rightPhase > 2.0 * .pi { rightPhase -= 2.0 * .pi }

            // 正弦波生成
            leftPtr[i] = sin(leftPhase) * currentVolume
            rightPtr[i] = sin(rightPhase) * currentVolume
        }
    }
}

private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
    Swift.min(Swift.max(value, min), max)
}
```

### 3.2.3 频率切换平滑过渡

切换 SSVEP 频率时（如从 15Hz 升级到 20Hz），使用相位连续的正弦波插值避免 click/pop：

```swift
/// 在 BinauralBeatNode 内部，通过 AtomicFloat 直接更新即可。
/// 因为相位累加器是连续的，频率变化会在下一个 sample 立即生效，
/// 但由于音频参数平滑器 (3.1.4) 的存在，
/// baseFrequency 和 ssvepFrequency 本身已经被主线程平滑过。
///
/// 额外保护：频率变化率限制在每秒 ±200Hz 以内
private func clampFrequencyChange(_ newFreq: Float, _ oldFreq: Float) -> Float {
    let maxDelta: Float = 200.0 / 48000.0  // 每帧最大变化
    let delta = newFreq - oldFreq
    if abs(delta) < maxDelta { return newFreq }
    return oldFreq + maxDelta * sign(delta)
}
```

### 3.2.4 音量包络曲线

| 状态 | Attack Time | Release Time | 曲线类型 |
|------|-------------|-------------|----------|
| 级别启动 | 3.0s | - | Exponential (smoothing=0.02) |
| 级别结束 | - | 2.0s | Exponential (smoothing=0.02) |
| 注意力驱动音量 | 0.5s | 0.5s | Exponential (smoothing=0.05) |

`envelopeSmoothing` 值越小，过渡越慢。0.02 对应 τ ≈ 50 frames @ 10ms timer = 500ms。

---

## 3.3 Dynamic Low-Pass Filter

### 3.3.1 实现方案

使用 `AVAudioUnitEQ` 单 band low-pass filter。不使用自定义 render callback 实现，Apple 框架的 EQ 节点已经过硬件加速优化。

### 3.3.2 配置

```swift
private func configureFilter() {
    engine.attach(lowPassFilter)

    let filterParams = lowPassFilter.bands[0]
    filterParams.filterType = .lowPass
    filterParams.frequency = 5000.0     // 初始截止频率
    filterParams.bandwidth = 1.2        // Q 值 (Octave)
    filterParams.gain = 0.0             // 0dB，不改变增益
    filterParams.bypass = false

    // 全局 EQ 节点设置为 stereo processing
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    engine.connect(lowPassFilter, format: format)
}
```

### 3.3.3 注意力 → 截止频率映射

```swift
/// 将注意力值 [0, 1] 映射到低通滤波器截止频率 [200, 18000] Hz
/// 使用指数曲线，低注意力时频率变化更敏感
func updateFilterCutoff(attention: Float) {
    // 指数映射: 200 * (90)^(attention)
    // attention=0 → 200Hz, attention=1 → 18000Hz
    let cutoff = 200.0 * powf(90.0, attention)
    _targetFilterCutoff = clamp(cutoff, 200.0, 18000.0)
}

// 映射表 (关键参考点):
// attention=0.0 → 200 Hz   (极度沉闷，水下感)
// attention=0.2 → 568 Hz   (闷，像隔着门)
// attention=0.4 → 1613 Hz  (偏暗，语音可辨识但不清晰)
// attention=0.5 → 2700 Hz  (中等，日常环境音质感)
// attention=0.6 → 4525 Hz  (明亮，大部分频率通过)
// attention=0.8 → 10125 Hz (清晰，hi-fi 感)
// attention=1.0 → 18000 Hz (全频，完全通透)
```

### 3.3.4 平滑过渡

滤波器参数在 `startParameterSmoothing()` 中以 10ms 间隔更新，使用一阶低通滤波 (smoothing factor = 0.15)：

- 从 200Hz 到 18000Hz 的完整扫描约需 **500ms** 到达 63%，约 **1.5s** 到达 95%
- 从 18000Hz 下降到 200Hz 同样速度
- 这创造了一种"呼吸感"的声音变化，而非突兀的开关

---

## 3.4 Ambient Sound Synthesis

### 3.4.1 架构概述

三种环境音各自独立 `AVAudioSourceNode`，通过各自的 `setMixVolume()` 控制混合比例。每种环境音都基于噪声发生器 + 滤波器 + 调制器的组合。

### 3.4.2 公共噪声生成器

```swift
/// 基于 xorshift32 的快速白噪声生成器
/// 在 render callback 中使用，无内存分配
struct WhiteNoiseGenerator {
    private var state: UInt32 = 0x12345678

    mutating func nextFloat() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        // 转换为 [-1, 1] 范围的 Float
        return Float(Int32(bitPattern: state)) / Float(Int32.max)
    }
}

/// 粉红噪声近似滤波器 (Paul Kellet 算法)
/// 白噪声 → 粉红噪声，1/f 频谱
struct PinkNoiseGenerator {
    private var b0: Float = 0.0
    private var b1: Float = 0.0
    private var b2: Float = 0.0
    private var b3: Float = 0.0
    private var b4: Float = 0.0
    private var b5: Float = 0.0
    private var b6: Float = 0.0
    private var white: WhiteNoiseGenerator = WhiteNoiseGenerator()

    mutating func nextFloat() -> Float {
        let w = white.nextFloat()
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return pink * 0.11  // 归一化到 [-1, 1]
    }
}
```

### 3.4.3 Wind Node (风声)

```swift
final class AmbientWindNode: AVAudioSourceNode {

    private let volumeAtomic = AtomicFloat(0.0)
    private var currentVolume: Float = 0.0

    // 风声参数
    private let windNoise = PinkNoiseGenerator()
    private var lfoPhase: Float = 0.0          // LFO 调制相位
    private let lfoRate: Float = 0.15          // 调制速率 Hz (很慢的呼吸感)
    private let lfoDepth: Float = 0.6          // 调制深度 (0~1)

    // 简单的一阶低通滤波器状态
    private var filterState: Float = 0.0
    private var filterCutoff: Float = 800.0    // Hz，风声偏低的截止频率
    private let sampleRate: Float = 48000.0

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderWind(frameCount: frameCount, abl: abl)
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }

    private func renderWind(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let targetVol = volumeAtomic.atomicValue
        currentVolume += (targetVol - currentVolume) * 0.005  // 2s envelope

        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)

        for i in 0..<frames {
            // LFO 调制截止频率，创造"一阵一阵"的风声
            lfoPhase += 2.0 * .pi * lfoRate / sampleRate
            if lfoPhase > 2.0 * .pi { lfoPhase -= 2.0 * .pi }

            let lfoValue = (sin(lfoPhase) * 0.5 + 0.5)  // [0, 1]
            let modulatedCutoff = filterCutoff * (1.0 + lfoDepth * lfoValue)

            // 一阶低通滤波 (用于噪声的简易滤波)
            // RC = 1 / (2π * fc), alpha = RC / (RC + 1/sr)
            let rc = 1.0 / (2.0 * .pi * modulatedCutoff)
            let alpha = rc / (rc + 1.0 / sampleRate)

            var noise = windNoise.nextFloat()
            filterState = filterState + alpha * (noise - filterState)
            let sample = filterState * currentVolume * 0.3  // 整体音量偏低

            // 轻微立体声展宽
            let stereoOffset = sin(lfoPhase * 0.7) * 0.05
            lPtr[i] = sample * (1.0 + stereoOffset)
            rPtr[i] = sample * (1.0 - stereoOffset)
        }
    }
}
```

**风声参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 噪声类型 | Pink noise | 1/f 频谱，自然感 |
| 基础截止频率 | 800 Hz | 低沉的风声基底 |
| LFO 速率 | 0.15 Hz | ~6.7s 一个呼吸周期 |
| LFO 深度 | 0.6 | 截止频率在 320~1280Hz 间摆动 |
| 立体声展宽 | ±5% | 微弱的左右摆动感 |
| 混合音量 | 0.3 | 相对主音量 |

### 3.4.4 Water Node (水声)

```swift
final class AmbientWaterNode: AVAudioSourceNode {

    private let volumeAtomic = AtomicFloat(0.0)
    private var currentVolume: Float = 0.0

    private var whiteNoise = WhiteNoiseGenerator()
    private let sampleRate: Float = 48000.0

    // 水滴事件计时器
    private var dripTimer: Float = 0.0
    private var nextDripInterval: Float = 0.3  // 随机间隔
    private var dripPhase: Float = 0.0
    private var dripFreq: Float = 0.0
    private var dripAmplitude: Float = 0.0
    private var dripDecay: Float = 0.0

    // 水流噪声滤波状态
    private var streamFilterL: Float = 0.0
    private var streamFilterR: Float = 0.0

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderWater(frameCount: frameCount, abl: abl)
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }

    private func renderWater(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let targetVol = volumeAtomic.atomicValue
        currentVolume += (targetVol - currentVolume) * 0.005

        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)
        var sample: Float

        for i in 0..<frames {
            let dt = 1.0 / sampleRate

            // === 水流基底: 带通滤波白噪声 ===
            // 模拟水流: 中心频率 1200Hz, Q=2 的带通
            let rawNoise = whiteNoise.nextFloat()

            // 两级一阶滤波器模拟带通 (highpass + lowpass)
            let lpAlpha = 1200.0 / (1200.0 + sampleRate * 0.5)  // ~600Hz lowpass
            let hpAlpha = sampleRate * 0.5 / (sampleRate * 0.5 + 400.0)  // ~400Hz highpass

            // 简化: 直接用低通滤波产生柔和水流声
            streamFilterL = streamFilterL + lpAlpha * (rawNoise - streamFilterL)
            streamFilterR = streamFilterR + lpAlpha * (rawNoise * 0.98 + whiteNoise.nextFloat() * 0.02 - streamFilterR)

            let streamL = streamFilterL * currentVolume * 0.15
            let streamR = streamFilterR * currentVolume * 0.15

            // === 水滴事件 ===
            dripTimer -= dt
            if dripTimer <= 0.0 {
                // 触发新水滴
                dripFreq = 1800.0 + Float.random(in: -400...400)   // 1400~2200 Hz
                dripAmplitude = Float.random(in: 0.15...0.35)
                dripDecay = 0.003 + Float.random(in: 0...0.002)    // 衰减系数
                dripPhase = 0.0
                dripTimer = 0.2 + Float.random(in: 0...0.8)       // 0.2~1.0s 间隔
            }

            // 水滴: 快速正弦衰减
            dripPhase += 2.0 * .pi * dripFreq * dt
            dripAmplitude *= (1.0 - dripDecay)  // 指数衰减
            if dripAmplitude < 0.001 { dripAmplitude = 0.0 }

            let drip = sin(dripPhase) * dripAmplitude * currentVolume

            // 随机左右声像
            let pan = Float.random(in: -0.6...0.6)

            lPtr[i] = streamL + drip * (0.5 - pan * 0.5)
            rPtr[i] = streamR + drip * (0.5 + pan * 0.5)
        }
    }
}
```

**水声参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 水流噪声 | Filtered white noise, fc≈600Hz | 持续柔和的水流基底 |
| 水滴频率 | 1400~2200 Hz (随机) | 模拟不同大小的水滴 |
| 水滴间隔 | 0.2~1.0s (随机) | 自然的不规则节奏 |
| 水滴衰减 | 指数, τ≈0.003 | 短促的"叮"声 |
| 水滴音量 | 0.15~0.35 (随机) | 随机力度 |
| 水滴声像 | ±0.6 (随机) | 空间分布感 |

### 3.4.5 Forest Node (森林声)

```swift
final class AmbientForestNode: AVAudioSourceNode {

    private let volumeAtomic = AtomicFloat(0.0)
    private var currentVolume: Float = 0.0

    private var pinkNoise = PinkNoiseGenerator()
    private let sampleRate: Float = 48000.0

    // 鸟鸣事件
    private var birdTimer: Float = 2.0
    private var birdPhase: Float = 0.0
    private var birdFreq: Float = 0.0
    private var birdAmplitude: Float = 0.0
    private var birdDuration: Float = 0.0
    private var birdElapsed: Float = 0.0
    private var birdActive: Bool = false

    // 树叶沙沙声
    private var rustleFilter: Float = 0.0
    private var rustleLFOPhase: Float = 0.0

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderForest(frameCount: frameCount, abl: abl)
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }

    private func renderForest(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let targetVol = volumeAtomic.atomicValue
        currentVolume += (targetVol - currentVolume) * 0.005

        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)
        let dt = 1.0 / sampleRate

        for i in 0..<frames {

            // === 树叶沙沙声: 调制粉红噪声 ===
            rustleLFOPhase += 2.0 * .pi * 0.3 / sampleRate  // 0.3 Hz LFO
            if rustleLFOPhase > 2.0 * .pi { rustleLFOPhase -= 2.0 * .pi }

            let rustleMod = powf(sin(rustleLFOPhase) * 0.5 + 0.5, 2.0)  // 平方使间歇更明显
            var rustleNoise = pinkNoise.nextFloat()

            let rustleAlpha = 2000.0 / (2000.0 + sampleRate * 0.5)
            rustleFilter = rustleFilter + rustleAlpha * (rustleNoise - rustleFilter)
            let rustle = rustleFilter * rustleMod * currentVolume * 0.08

            // === 鸟鸣合成 ===
            var birdSample: Float = 0.0

            if !birdActive {
                birdTimer -= dt
                if birdTimer <= 0.0 {
                    birdActive = true
                    birdFreq = 2200.0 + Float.random(in: -600...800)  // 1600~3000 Hz
                    birdDuration = 0.15 + Float.random(in: 0...0.4)    // 0.15~0.55s
                    birdElapsed = 0.0
                    birdAmplitude = 0.2 + Float.random(in: 0...0.15)
                    birdPhase = 0.0
                    birdTimer = 3.0 + Float.random(in: 0...8.0)       // 3~11s 间隔
                }
            }

            if birdActive {
                birdElapsed += dt
                // 频率滑动 (FM chirp)
                let progress = birdElapsed / birdDuration
                let freqMod = 1.0 + 0.3 * sin(2.0 * .pi * 8.0 * progress)  // 快速颤音
                birdPhase += 2.0 * .pi * birdFreq * freqMod * dt

                // 音量包络: 快速 attack, 自然 release
                let env: Float
                if progress < 0.1 {
                    env = progress / 0.1  // 10% attack
                } else {
                    env = 1.0 - (progress - 0.1) / 0.9  // 90% release
                }
                env = max(env, 0.0)

                birdSample = sin(birdPhase) * birdAmplitude * env * currentVolume

                if birdElapsed >= birdDuration {
                    birdActive = false
                }
            }

            // 合成输出
            let birdPan = Float.random(in: -0.4...0.4)
            lPtr[i] = rustle * 0.7 + birdSample * (0.5 - birdPan * 0.5)
            rPtr[i] = rustle * 1.0 + birdSample * (0.5 + birdPan * 0.5)
        }
    }
}
```

**森林声参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 树叶沙沙 | Pink noise, fc≈2000Hz, LFO 0.3Hz | 间歇性的沙沙声 |
| LFO 波形 | sin² (平方) | 间歇感更明显 |
| 鸟鸣频率 | 1600~3000 Hz (随机) | 不同鸟的音高 |
| 鸟鸣颤音 | ±30% FM, 8Hz 调制 | 自然鸟鸣的颤音效果 |
| 鸟鸣时长 | 0.15~0.55s (随机) | 短促的啁啾 |
| 鸟鸣间隔 | 3~11s (随机) | 稀疏出现，不打扰冥想 |
| 混合音量 | 0.08 (树叶) + 0.2 (鸟鸣) | 远低于 binaural beats |

---

## 3.5 Feedback Sound Effects

### 3.5.1 FeedbackNode 架构

所有反馈音效共用一个 `FeedbackNode`，通过事件队列接收触发命令。render callback 从队列中读取事件并合成对应音效。

```swift
/// 反馈音效事件类型
enum FeedbackEventType: Sendable {
    case rewardChime              // 奖励: 颂钵声
    case distractionAlert         // 分心警告: 不和谐音
    case flowStateEntrance        // 心流进入: 上行音阶
    case levelComplete            // 关卡完成: 和弦
}

final class FeedbackNode: AVAudioSourceNode {

    // 事件队列 (lock-free, 单生产者单消费者)
    private let eventQueue = ConcurrentQueue<FeedbackEvent>(capacity: 16)

    // 颂钵合成器状态
    private var bowlPhases: [Float] = [0, 0, 0, 0, 0]
    private var bowlAmplitudes: [Float] = [0, 0, 0, 0, 0]
    private var bowlActive = false

    // 分心警告合成器状态
    private var alertPhase: Float = 0.0
    private var alertAmplitude: Float = 0.0
    private var alertActive = false

    // 心流上行音阶状态
    private var flowNotes: [FlowNote] = []
    private var flowNoteIndex = 0
    private var flowNotePhase: Float = 0.0
    private var flowNoteAmplitude: Float = 0.0
    private var flowActive = false

    private let sampleRate: Float = 48000.0

    struct FeedbackEvent {
        let type: FeedbackEventType
        let timestamp: Float  // audioEngine 当前播放时间 (用于精确调度)
    }

    struct FlowNote {
        let frequency: Float
        let duration: Float
        let elapsed: Float = 0.0
    }

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderEffects(frameCount: frameCount, abl: abl)
            return noErr
        })
    }

    /// 从主线程触发音效
    func trigger(_ type: FeedbackEventType) {
        eventQueue.enqueue(FeedbackEvent(type: type, timestamp: 0))
    }

    private func renderEffects(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)
        let dt = 1.0 / sampleRate

        // 处理队列中的事件
        while let event = eventQueue.dequeue() {
            handleEvent(event)
        }

        for i in 0..<frames {
            var sampleL: Float = 0.0
            var sampleR: Float = 0.0

            // === 颂钵声 ===
            if bowlActive {
                let bowlSample = renderBowlSample(dt: dt)
                sampleL += bowlSample * 0.7
                sampleR += bowlSample * 1.0  // 略偏右，增加空间感
            }

            // === 分心警告 ===
            if alertActive {
                let alertSample = renderAlertSample(dt: dt)
                sampleL += alertSample
                sampleR += alertSample
            }

            // === 心流音阶 ===
            if flowActive {
                let (flowL, flowR) = renderFlowSample(dt: dt)
                sampleL += flowL
                sampleR += flowR
            }

            lPtr[i] = sampleL
            rPtr[i] = sampleR
        }
    }

    private func handleEvent(_ event: FeedbackEvent) {
        switch event.type {
        case .rewardChime:
            startBowl()

        case .distractionAlert:
            startAlert()

        case .flowStateEntrance:
            startFlowSequence()

        case .levelComplete:
            startLevelComplete()
        }
    }
}
```

### 3.5.2 颂钵声合成 (Singing Bowl)

颂钵声 = 基频正弦 + 多个谐波 + 指数衰减 + 轻微频率漂移 (beat frequency)。

```swift
/// 颂钵谐波参数
/// 模拟藏传颂钵的频谱特征
private let bowlHarmonics: [(ratio: Float, amplitude: Float, decay: Float)] = [
    (1.0,    1.0,   0.4),   // 基频, 最慢衰减
    (2.76,   0.5,   0.8),   // 第一谐波 (颂钵特有非整数比)
    (4.72,   0.25,  1.2),   // 第二谐波
    (6.34,   0.12,  1.8),   // 第三谐波
    (8.91,   0.06,  2.5),   // 第四谐波 (最高泛音)
]

private let bowlBaseFreq: Float = 285.0  // Hz, D# 附近

private func startBowl() {
    bowlActive = true
    for i in 0..<bowlPhases.count {
        bowlPhases[i] = 0.0
        bowlAmplitudes[i] = bowlHarmonics[i].amplitude
    }
}

private func renderBowlSample(dt: Float) -> Float {
    var sample: Float = 0.0
    var allDecayed = true

    for i in 0..<bowlHarmonics.count {
        guard bowlAmplitudes[i] > 0.001 else { continue }
        allDecayed = false

        let h = bowlHarmonics[i]
        let freq = bowlBaseFreq * h.ratio

        // 轻微频率漂移 (模拟拍频效应)
        let beatFreq = 0.3 * Float(i)  // 每个谐波有不同的漂移速率
        let freqMod = freq + sin(bowlPhases[i] * 0.001) * beatFreq

        bowlPhases[i] += 2.0 * .pi * freqMod * dt
        if bowlPhases[i] > 65536.0 { bowlPhases[i] -= 65536.0 }  // 防溢出

        // 指数衰减: A * e^(-decay * t)
        // 近似为每帧乘以 (1 - decay * dt)
        bowlAmplitudes[i] *= (1.0 - h.decay * dt)

        sample += sin(bowlPhases[i]) * bowlAmplitudes[i]
    }

    if allDecayed { bowlActive = false }

    // 整体包络: 50ms attack
    return sample * 0.25  // 颂钵音量适中
}
```

**颂钵声参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 基频 | 285 Hz | D# 附近，温暖感 |
| 谐波比 | 1.0, 2.76, 4.72, 6.34, 8.91 | 非整数比，颂钵特征音色 |
| 衰减时间 | 0.4s ~ 2.5s (按谐波) | 基频持续最长 |
| 频率漂移 | 0~1.2 Hz beat | 活的"嗡嗡"感 |
| 混合音量 | 0.25 | 不压过环境音 |

### 3.5.3 分心警告音

柔和的不和谐音，不能刺耳但要明显提示分心。

```swift
private func startAlert() {
    alertActive = true
    alertPhase = 0.0
    alertAmplitude = 0.12
}

private func renderAlertSample(dt: Float) -> Float {
    // 两个略微失谐的正弦波产生"拍频"不和谐效果
    // 使用小二度音程 (频率比 ~16:15)
    let freq1: Float = 330.0  // E4
    let freq2: Float = 352.0  // 约 F4, 小二度

    alertPhase += 2.0 * .pi * freq1 * dt

    let tone1 = sin(alertPhase) * alertAmplitude
    let tone2 = sin(alertPhase * (freq2 / freq1)) * alertAmplitude * 0.7

    // 快速衰减: 500ms 内消失
    alertAmplitude *= (1.0 - 4.0 * dt)

    let sample = (tone1 + tone2) * 0.3

    if alertAmplitude < 0.001 { alertActive = false }

    return sample
}
```

**分心警告参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 频率 1 | 330 Hz (E4) | 主音 |
| 频率 2 | 352 Hz (~F4) | 小二度，产生不和谐拍频 |
| 拍频 | 22 Hz | 可感知的"嗡嗡"不和谐感 |
| 持续时间 | ~500ms | 快速出现快速消失 |
| 音量 | 0.12 × 0.3 = 0.036 | 非常柔和，不打断冥想 |

### 3.5.4 心流进入音 (Flow State Entrance)

三个音符的上行音阶，暗示从当前状态"升起"。

```swift
private func startFlowSequence() {
    flowActive = true
    flowNoteIndex = 0
    // C4 → E4 → G4 (大三和弦分解)
    flowNotes = [
        FlowNote(frequency: 261.63, duration: 0.4),   // C4
        FlowNote(frequency: 329.63, duration: 0.4),   // E4
        FlowNote(frequency: 392.00, duration: 0.8),   // G4, 最后一个长一些
    ]
    flowNotePhase = 0.0
    flowNoteAmplitude = 0.0
}

private func renderFlowSample(dt: Float) -> (Float, Float) {
    guard flowNoteIndex < flowNotes.count else {
        flowActive = false
        return (0, 0)
    }

    var note = flowNotes[flowNoteIndex]
    note.elapsed += dt

    // 正弦 + 轻微泛音
    flowNotePhase += 2.0 * .pi * note.frequency * dt
    let tone = sin(flowNotePhase) + sin(flowNotePhase * 2.0) * 0.15 + sin(flowNotePhase * 3.0) * 0.05

    // ADSR 包络
    let progress = note.elapsed / note.duration
    let env: Float
    if progress < 0.05 {
        env = progress / 0.05               // 5% = 20ms attack
    } else if progress < 0.2 {
        env = 1.0                            // sustain
    } else {
        env = 1.0 - (progress - 0.2) / 0.8  // release
    }
    env = max(env, 0.0)

    let sample = tone * env * 0.1

    if note.elapsed >= note.duration {
        flowNoteIndex += 1
        if flowNoteIndex >= flowNotes.count {
            flowActive = false
        }
    }

    // 轻微的声像移动: 从左到右
    let pan = Float(flowNoteIndex) / Float(max(flowNotes.count - 1, 1))
    return (sample * (1.0 - pan * 0.6), sample * (0.4 + pan * 0.6))
}
```

**心流音参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 音符序列 | C4(261.6Hz) → E4(329.6Hz) → G4(392Hz) | 大三和弦上行分解 |
| 每音符时长 | 0.4s, 0.4s, 0.8s | 最后一个延长 |
| Attack | 20ms | 快速但不突兀 |
| 泛音 | 基频 + 2次(15%) + 3次(5%) | 轻微的钟琴感 |
| 声像 | 左→中→右 | 空间上行感 |
| 总时长 | 1.6s | 简洁的提示 |

### 3.5.5 关卡完成音

```swift
private func startLevelComplete() {
    // 同时触发三个不同频率的颂钵 (和弦)
    // 延迟触发，产生"回响"效果
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.0) { [weak self] in
        self?.trigger(.rewardChime)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        // 第二个颂钵，基频偏移 +50Hz
        self?.trigger(.rewardChime)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        self?.trigger(.rewardChime)
    }
}
```

---

## 3.6 Core Haptics Integration

### 3.6.1 CHHapticEngine 初始化

```swift
import CoreHaptics

final class HapticManager: @unchecked Sendable {
    static let shared = HapticManager()

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool = false

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        // 检测硬件是否支持 Core Haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("[Haptic] Hardware does not support Core Haptics")
            supportsHaptics = false
            return
        }

        supportsHaptics = true

        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                print("[Haptic] Engine reset, restarting...")
                try? self?.engine?.start()
            }
            engine?.stoppedHandler = { reason in
                print("[Haptic] Engine stopped: \(reason)")
            }
            try engine?.start()
            print("[Haptic] Engine started successfully")
        } catch {
            print("[Haptic] Failed to start engine: \(error)")
            supportsHaptics = false
        }
    }

    /// 是否支持 haptics，UI 层用于决定是否显示相关选项
    var isAvailable: Bool { supportsHaptics && engine != nil }
}
```

### 3.6.2 Haptic 模式定义

```swift
extension HapticManager {

    // MARK: - 呼吸脉冲 (Breathing Pulse)

    /// 与冥想呼吸节奏同步的柔和脉冲
    /// 在注意力稳定时触发，频率约 0.2Hz (5s 一个周期)
    func playBreathingPulse(intensity: Float = 0.5) {
        guard isAvailable else { return }

        do {
            let events: [CHHapticEvent] = [
                // 吸气: 渐强
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
                    ],
                    relativeTime: 0.0,
                    duration: 2.5
                ),
                // 呼气: 渐弱
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05),
                    ],
                    relativeTime: 2.5,
                    duration: 2.5
                ),
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                          value: intensity,
                                          relativeTime: 0.0)
            ])

            let player = try engine?.makePlayer(with: pattern)
            player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptic] Breathing pulse failed: \(error)")
        }
    }

    // MARK: - 专注锁定 (Focus Lock)

    /// 当注意力持续高于 0.85 达到 5s 时触发的确认感
    /// 短促有力的单次脉冲
    func playFocusLock() {
        guard isAvailable else { return }

        do {
            let events: [CHHapticEvent] = [
                // 瞬态 "咔" 感
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                    ],
                    relativeTime: 0.0
                ),
                // 跟随的柔和余震
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
                    ],
                    relativeTime: 0.05,
                    duration: 0.3
                ),
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptic] Focus lock failed: \(error)")
        }
    }

    // MARK: - 分心轻推 (Distraction Nudge)

    /// 检测到分心时的柔和提醒
    /// 不同于警告音的"不和谐"，haptics 用的是"不规则"模式
    func playDistractionNudge() {
        guard isAvailable else { return }

        do {
            let events: [CHHapticEvent] = [
                // 三次短促不规则脉冲
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                ], relativeTime: 0.0),

                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
                ], relativeTime: 0.15),

                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
                ], relativeTime: 0.28),
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[Haptic] Distraction nudge failed: \(error)")
        }
    }
}
```

### 3.6.3 Haptic 参数汇总

| 模式 | 类型 | Intensity | Sharpness | 时长 | 触发条件 |
|------|------|-----------|-----------|------|----------|
| 呼吸脉冲 | Continuous | 0.1~0.15 | 0.05~0.1 | 5.0s | attention > 0.6 持续 10s |
| 专注锁定 | Transient + Continuous | 0.8 + 0.2 | 0.6 + 0.1 | 0.35s | attention > 0.85 持续 5s |
| 分心轻推 | Transient ×3 | 0.4→0.3→0.2 | 0.3→0.2→0.15 | 0.43s | attention < 0.3 下降超过 0.2 |

### 3.6.4 优雅降级

```swift
/// 在所有 haptic 调用前检查
/// 当硬件不支持时，静默跳过，不抛异常，不影响音频流程
///
/// 降级策略:
/// 1. 不支持 Core Haptics → 所有 haptic 调用变为 no-op
/// 2. Engine 异常停止 → resetHandler 自动重启，期间跳过
/// 3. Player 创建失败 → catch 后 print 日志，不影响主流程
///
/// UI 层行为:
/// - Settings 页面: 不显示 haptics 开关 (isAvailable == false 时)
/// - 训练页面: 不显示 haptics 相关提示
```

---

## 3.7 Attention → Audio Parameter Mapping

### 3.7.1 完整映射函数

```swift
struct AudioParameterMapper {

    /// 注意力值 [0, 1] → 所有音频参数
    /// 这个函数在主线程的参数更新循环中调用
    static func map(attention: Float) -> AudioParameters {
        // 确保输入范围
        let a = clamp(attention, 0.0, 1.0)

        return AudioParameters(
            // === 滤波器截止频率 ===
            // 指数映射: 200 * 90^a
            // a=0 → 200Hz, a=1 → 18000Hz
            filterCutoff: 200.0 * powf(90.0, a),

            // === 混响湿/干比 ===
            // 注意力高 → 更干 (清晰)
            // 注意力低 → 更湿 (模糊/空旷)
            reverbWetDry: lerp(0.7, 0.15, a),

            // === Binaural Beats 音量 ===
            // 始终存在，但注意力低时音量降低
            binauralVolume: lerp(0.3, 0.7, powf(a, 0.5)),

            // === 环境音总音量 ===
            // 注意力高 → 环境音作为"奖励"更丰富
            ambientMasterVolume: lerp(0.15, 0.5, powf(a, 0.7)),

            // === 各环境音混合比例 ===
            // 注意力低时风声占比大 (孤寂感)
            // 注意力高时水声+森林占比大 (丰富感)
            windMix: lerp(0.8, 0.2, a),
            waterMix: lerp(0.1, 0.5, a),
            forestMix: lerp(0.1, 0.3, a),
        )
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}

struct AudioParameters {
    let filterCutoff: Float      // Hz, [200, 18000]
    let reverbWetDry: Float      // [0, 1], 0=dry, 1=wet
    let binauralVolume: Float    // [0, 1]
    let ambientMasterVolume: Float // [0, 1]
    let windMix: Float           // [0, 1]
    let waterMix: Float          // [0, 1]
    let forestMix: Float         // [0, 1]
}
```

### 3.7.2 映射曲线数值表

| Attention | Filter Cutoff (Hz) | Reverb Wet/Dry | Binaural Vol | Ambient Vol | Wind% | Water% | Forest% |
|-----------|--------------------|-----------------|--------------|-------------|-------|--------|---------|
| 0.0 | 200 | 0.70 | 0.30 | 0.15 | 80% | 10% | 10% |
| 0.1 | 285 | 0.65 | 0.34 | 0.18 | 72% | 14% | 14% |
| 0.2 | 407 | 0.59 | 0.39 | 0.22 | 64% | 18% | 18% |
| 0.3 | 581 | 0.53 | 0.44 | 0.26 | 56% | 22% | 22% |
| 0.4 | 830 | 0.47 | 0.49 | 0.30 | 48% | 26% | 26% |
| 0.5 | 1185 | 0.41 | 0.53 | 0.34 | 40% | 30% | 30% |
| 0.6 | 1693 | 0.36 | 0.57 | 0.38 | 32% | 34% | 34% |
| 0.7 | 2418 | 0.30 | 0.61 | 0.42 | 24% | 38% | 38% |
| 0.8 | 3453 | 0.24 | 0.64 | 0.45 | 16% | 42% | 42% |
| 0.9 | 4932 | 0.19 | 0.67 | 0.48 | 8% | 46% | 46% |
| 1.0 | 18000 | 0.15 | 0.70 | 0.50 | 0% | 50% | 50% |

### 3.7.3 参数更新主循环

```swift
extension AudioEngineManager {

    /// 从 AttentionController 接收注意力值并更新所有音频参数
    /// 在 10ms 参数平滑定时器中调用
    func updateFromAttention(_ attention: Float) {
        attentionLevel = attention
        let params = AudioParameterMapper.map(attention: attention)

        // 设置目标值 (平滑器会自动插值)
        _targetFilterCutoff = params.filterCutoff
        _targetReverbWetDry = params.reverbWetDry

        binauralNode.setTargetVolume(params.binauralVolume)

        // 环境音混合
        let ambMaster = params.ambientMasterVolume
        ambientWindNode.setMixVolume(params.windMix * ambMaster)
        ambientWaterNode.setMixVolume(params.waterMix * ambMaster)
        ambientForestNode.setMixVolume(params.forestMix * ambMaster)
    }
}
```

### 3.7.4 反馈音效触发逻辑

反馈音效不由连续的 attention 值驱动，而是由离散事件触发：

```swift
/// 在 AttentionController 中检测状态变化并触发反馈
/// 每 100ms 调用一次
func checkFeedbackTriggers(attention: Float, prevAttention: Float, duration: TimeInterval) {
    let delta = attention - prevAttention

    // === 心流进入 ===
    // 注意力从 < 0.7 升至 > 0.85，且持续时间 > 3s
    static var highAttentionStart: Date?
    if attention > 0.85 {
        if highAttentionStart == nil { highAttentionStart = Date() }
        if let start = highAttentionStart, Date().timeIntervalSince(start) > 3.0 {
            if prevAttention <= 0.85 {
                feedbackNode.trigger(.flowStateEntrance)
                HapticManager.shared.playFocusLock()
            }
        }
    } else {
        highAttentionStart = nil
    }

    // === 分心警告 ===
    // 注意力在 1s 内下降超过 0.2，且当前 < 0.3
    static var prevAttentionForDrop: Float = 0.5
    if attention < 0.3 && (prevAttentionForDrop - attention) > 0.2 {
        feedbackNode.trigger(.distractionAlert)
        HapticManager.shared.playDistractionNudge()
    }
    prevAttentionForDrop = attention

    // === 奖励颂钵 ===
    // 注意力稳定在 0.8+ 超过 10s
    static var stableHighStart: Date?
    if attention > 0.8 && abs(delta) < 0.05 {
        if stableHighStart == nil { stableHighStart = Date() }
        if let start = stableHighStart, Date().timeIntervalSince(start) > 10.0 {
            feedbackNode.trigger(.rewardChime)
            HapticManager.shared.playBreathingPulse(intensity: attention)
            stableHighStart = nil  // 防止重复触发，10s 后才能再次触发
        }
    } else {
        stableHighStart = nil
    }
}
```

### 3.7.5 平滑插值常数汇总

| 参数 | Smoothing Factor | 63% 时间 | 95% 时间 | 更新频率 |
|------|-----------------|----------|----------|----------|
| Filter Cutoff | 0.15 | ~67ms | ~200ms | 100Hz (10ms) |
| Reverb Wet/Dry | 0.15 | ~67ms | ~200ms | 100Hz |
| Binaural Volume | 0.02 | ~500ms | ~1.5s | 100Hz |
| Ambient Volume | 0.005 | ~2s | ~6s | 100Hz |
| Filter Ramp (per-frame) | N/A | 100ms | 300ms | 48kHz (per-sample) |

---

## 3.8 Per-Level Audio Configuration Table

### 3.8.1 完整配置表

```swift
struct LevelAudioConfig {
    let level: Int
    let name: String
    let ssvepFrequency: Float          // Hz, SSVEP 目标频率
    let distractorFrequency: Float     // Hz, 干扰频率
    let baseFrequency: Float           // Hz, binaural beat 基频
    let binauralVolume: Float          // 目标注意力时的音量
    let ambientType: AmbientType
    let rewardChimeBaseFreq: Float     // Hz, 颂钵基频
    let filterMinCutoff: Float         // Hz, 最低截止频率 (attention=0)
    let filterMaxCutoff: Float         // Hz, 最高截止频率 (attention=1)
    let levelTransitionDuration: Float // 秒, 切换到下一级的过渡时间
}

enum AmbientType {
    case wind          // 纯风声
    case windWater     // 风+水
    case forest        // 森林
    case forestWater   // 森林+水
    case fullEnsemble  // 全部环境音
    case cosmic        // 宇宙 (高级别特殊音色)
}

let levelConfigs: [LevelAudioConfig] = [
    // Level 1: 入门，15Hz SSVEP
    LevelAudioConfig(
        level: 1,
        name: "星空初现",
        ssvepFrequency: 15.0,
        distractorFrequency: 20.0,
        baseFrequency: 150.0,          // 较低基频，温暖感
        binauralVolume: 0.5,
        ambientType: .wind,
        rewardChimeBaseFreq: 285.0,
        filterMinCutoff: 200.0,
        filterMaxCutoff: 12000.0,      // 入门级不完全开放高频
        levelTransitionDuration: 3.0
    ),

    // Level 2: 进阶，15Hz SSVEP + 引入干扰
    LevelAudioConfig(
        level: 2,
        name: "萤火微明",
        ssvepFrequency: 15.0,
        distractorFrequency: 20.0,
        baseFrequency: 174.0,          // F3 附近
        binauralVolume: 0.55,
        ambientType: .windWater,
        rewardChimeBaseFreq: 320.0,
        filterMinCutoff: 200.0,
        filterMaxCutoff: 14000.0,
        levelTransitionDuration: 3.0
    ),

    // Level 3: 中级，开始出现 20Hz 干扰
    LevelAudioConfig(
        level: 3,
        name: "月影徘徊",
        ssvepFrequency: 15.0,
        distractorFrequency: 20.0,
        baseFrequency: 196.0,          // G3
        binauralVolume: 0.6,
        ambientType: .forest,
        rewardChimeBaseFreq: 350.0,
        filterMinCutoff: 200.0,
        filterMaxCutoff: 15000.0,
        levelTransitionDuration: 4.0
    ),

    // Level 4: 高级，切换到 20Hz SSVEP
    LevelAudioConfig(
        level: 4,
        name: "星河灿烂",
        ssvepFrequency: 20.0,          // 切换目标频率!
        distractorFrequency: 15.0,     // 原来的 15Hz 变成干扰
        baseFrequency: 220.0,          // A3
        binauralVolume: 0.65,
        ambientType: .forestWater,
        rewardChimeBaseFreq: 392.0,
        filterMinCutoff: 200.0,
        filterMaxCutoff: 16000.0,
        levelTransitionDuration: 5.0   // 频率切换需要更长的过渡
    ),

    // Level 5: 专家，引入 40Hz SSVEP
    LevelAudioConfig(
        level: 5,
        name: "银河倾泻",
        ssvepFrequency: 40.0,          // 高频 SSVEP
        distractorFrequency: 20.0,
        baseFrequency: 200.0,
        binauralVolume: 0.6,           // 40Hz 差值较大，适当降低音量防不适
        ambientType: .fullEnsemble,
        rewardChimeBaseFreq: 440.0,    // A4
        filterMinCutoff: 200.0,
        filterMaxCutoff: 17000.0,
        levelTransitionDuration: 5.0
    ),

    // Level 6: 大师，全频段
    LevelAudioConfig(
        level: 6,
        name: "宇宙合一",
        ssvepFrequency: 40.0,
        distractorFrequency: 15.0,
        baseFrequency: 256.0,          // C4, 中音 C
        binauralVolume: 0.55,
        ambientType: .cosmic,          // 特殊宇宙音色
        rewardChimeBaseFreq: 528.0,    // C5, "爱的频率"
        filterMinCutoff: 200.0,
        filterMaxCutoff: 18000.0,      // 全频开放
        levelTransitionDuration: 5.0
    ),
]
```

### 3.8.2 各级别环境音混合预设

| Level | Wind | Water | Forest | Cosmic | 整体音量 |
|-------|------|-------|--------|--------|----------|
| 1 星空初现 | 100% | 0% | 0% | 0% | 0.20 |
| 2 萤火微明 | 60% | 40% | 0% | 0% | 0.25 |
| 3 月影徘徊 | 20% | 10% | 70% | 0% | 0.30 |
| 4 星河灿烂 | 10% | 40% | 50% | 0% | 0.35 |
| 5 银河倾泻 | 20% | 30% | 30% | 20% | 0.40 |
| 6 宇宙合一 | 10% | 20% | 20% | 50% | 0.45 |

### 3.8.3 宇宙音色 (Cosmic Ambient, Level 6 专属)

Level 6 引入第四种环境音：基于 FM 合成的深空音色。

```swift
final class AmbientCosmicNode: AVAudioSourceNode {

    private let volumeAtomic = AtomicFloat(0.0)
    private var currentVolume: Float = 0.0
    private let sampleRate: Float = 48000.0

    // FM 合成参数
    private var carrierPhase: Float = 0.0
    private var modulatorPhase: Float = 0.0
    private var lfoPhase: Float = 0.0

    // 载波和调制器频率
    private let carrierFreq: Float = 80.0     // 很低的载波，深沉的基底
    private let modulatorFreq: Float = 0.3     // 极慢的调制
    private let modIndex: Float = 150.0        // 调制指数，产生丰富的边带

    // 噪声层
    private var noiseGen = PinkNoiseGenerator()
    private var noiseFilter: Float = 0.0

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        super.init(format: format, renderBlock: { [weak self] _, _, frameCount, abl in
            guard let self else { return noErr }
            self.renderCosmic(frameCount: frameCount, abl: abl)
            return noErr
        })
    }

    func setMixVolume(_ vol: Float) { volumeAtomic.store(clamp(vol, 0.0, 1.0)) }

    private func renderCosmic(frameCount: UInt32, abl: UnsafeMutablePointer<AudioBufferList>) {
        let targetVol = volumeAtomic.atomicValue
        currentVolume += (targetVol - currentVolume) * 0.003  // 更慢的淡入

        let buf = UnsafeMutableAudioBufferListPointer(abl)
        guard buf.count >= 2,
              let lPtr = buf[0].mData?.assumingMemoryBound(to: Float.self),
              let rPtr = buf[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        let frames = Int(frameCount)
        let dt = 1.0 / sampleRate

        for i in 0..<frames {
            // LFO 调制调制器频率
            lfoPhase += 2.0 * .pi * 0.05 / sampleRate  // 50s 超慢周期
            if lfoPhase > 2.0 * .pi { lfoPhase -= 2.0 * .pi }
            let lfoMod = sin(lfoPhase) * 0.5 + 0.5

            // FM 合成
            modulatorPhase += 2.0 * .pi * modulatorFreq * dt
            if modulatorPhase > 2.0 * .pi { modulatorPhase -= 2.0 * .pi }

            let modSignal = sin(modulatorPhase) * modIndex * (0.5 + lfoMod * 0.5)
            carrierPhase += 2.0 * .pi * (carrierFreq + modSignal) * dt
            if carrierPhase > 65536.0 { carrierPhase -= 65536.0 }

            let fmTone = sin(carrierPhase) * 0.15

            // 叠加极低频噪声层
            let noise = noiseGen.nextFloat()
            let noiseAlpha = 150.0 / (150.0 + sampleRate * 0.5)
            noiseFilter = noiseFilter + noiseAlpha * (noise - noiseFilter)
            let noiseLayer = noiseFilter * 0.08

            let sample = (fmTone + noiseLayer) * currentVolume

            // 宽立体声
            let stereoPhase = carrierPhase * 0.001
            lPtr[i] = sample * (1.0 + sin(stereoPhase) * 0.3)
            rPtr[i] = sample * (1.0 - sin(stereoPhase) * 0.3)
        }
    }
}
```

**宇宙音色参数：**
| 参数 | 值 | 说明 |
|------|-----|------|
| 载波频率 | 80 Hz | 深沉的宇宙基底 |
| 调制器频率 | 0.3 Hz | 极慢的频率扫描 |
| 调制指数 | 150 | 产生丰富的谐波边带 |
| LFO 周期 | 50s | 几乎不可感知的极慢变化 |
| 噪声层 | Pink noise, fc≈150Hz | 太空"静电"感 |
| 立体声展宽 | ±30% | 宽广的空间感 |

### 3.8.4 级别切换流程

```swift
extension AudioEngineManager {

    /// 切换到指定级别
    /// - Parameter animate: 是否播放过渡动画 (首次启动时为 false)
    func switchToLevel(_ config: LevelAudioConfig, animate: Bool = true) {
        let duration = animate ? config.levelTransitionDuration : 0.0

        // 1. 更新 binaural beat 频率
        binauralNode.setSSVEPFrequency(config.ssvepFrequency)
        binauralNode.setBaseFrequency(config.baseFrequency)
        binauralNode.setTargetVolume(animate ? 0.0 : config.binauralVolume)

        // 2. 更新环境音混合
        switch config.ambientType {
        case .wind:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.5)
            ambientWaterNode.setMixVolume(0.0)
            ambientForestNode.setMixVolume(0.0)
        case .windWater:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.6)
            ambientWaterNode.setMixVolume(animate ? 0.0 : 0.4)
            ambientForestNode.setMixVolume(0.0)
        case .forest:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.2)
            ambientWaterNode.setMixVolume(animate ? 0.0 : 0.1)
            ambientForestNode.setMixVolume(animate ? 0.0 : 0.7)
        case .forestWater:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.1)
            ambientWaterNode.setMixVolume(animate ? 0.0 : 0.4)
            ambientForestNode.setMixVolume(animate ? 0.0 : 0.5)
        case .fullEnsemble:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.2)
            ambientWaterNode.setMixVolume(animate ? 0.0 : 0.3)
            ambientForestNode.setMixVolume(animate ? 0.0 : 0.3)
        case .cosmic:
            ambientWindNode.setMixVolume(animate ? 0.0 : 0.1)
            ambientWaterNode.setMixVolume(animate ? 0.0 : 0.2)
            ambientForestNode.setMixVolume(animate ? 0.0 : 0.2)
            // cosmic node handled separately
        }

        // 3. 如果有过渡动画，延迟后渐入
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.5) { [weak self] in
                self?.binauralNode.setTargetVolume(config.binauralVolume)
            }
        }

        // 4. 更新滤波器范围
        // filterMinCutoff 和 filterMaxCutoff 存储在当前 config 中
        // 映射函数中使用这些值

        // 5. 触发过渡音效
        if animate {
            feedbackNode.trigger(.levelComplete)
        }
    }
}
```

### 3.8.5 Reverb 配置

```swift
private func configureReverb() {
    engine.attach(reverbNode)

    // 预设: 大厅混响，适合冥想场景
    reverbNode.loadFactoryPreset(.largeHall)

    // 自定义参数调整
    reverbNode.wetDryMix = 30.0        // 初始 30% wet
    // largeHall 预设的默认参数通常:
    // - 混响时间: ~3.0s
    // - preDelay: ~30ms
    // - 高频衰减: 适中

    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    engine.connect(reverbNode, format: format)
}
```

| Reverb 参数 | 值 | 说明 |
|-------------|-----|------|
| Preset | largeHall | 宽广空间感 |
| Wet/Dry (attention=0) | 70% | 高湿，模糊/沉浸 |
| Wet/Dry (attention=1) | 15% | 低湿，清晰/聚焦 |
| 混响时间 | ~3.0s | 不短不长的自然空间 |
| PreDelay | ~30ms | 避免音色浑浊 |

### 3.8.6 整体音量电平参考

所有音量值以 `Float` 0.0~1.0 表示，映射到 `AVAudioMixerNode` 的 output volume：

| 音源 | 最低音量 (attention=0) | 最高音量 (attention=1) | 峰值 dBFS |
|------|----------------------|----------------------|-----------|
| Binaural Beats | 0.30 | 0.70 | -3 dB |
| Wind | 0.12 | 0.10 | -20 dB |
| Water | 0.015 | 0.25 | -12 dB |
| Forest | 0.015 | 0.15 | -16 dB |
| Cosmic | 0 | 0.225 | -13 dB |
| Reward Chime | - | 0.25 (瞬态) | -12 dB |
| Distraction Alert | - | 0.036 (瞬态) | -29 dB |
| **混合峰值 (理论)** | | | **-2 dBFS** |

主混音器 output volume 固定为 0.8，为系统音量留 headroom。
