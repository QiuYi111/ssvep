# 星空与萤火 — 技术实现计划

## Section 5: Simulated Attention System（模拟注意力系统）

> **核心原则：这不是随机噪声。模拟器必须产生一个"真实人类学习专注"的叙事弧线。** Demo 的目标是让观察者相信数据是真实的脑电信号。每一次注意力波动都应有可追溯的心理模型支撑。

---

### 5.1 AttentionProvider Protocol 与 SimulatedAttentionProvider

所有注意力数据源遵循统一 protocol，便于未来替换为真实 EEG 输入：

```swift
// MARK: - AttentionProvider Protocol
protocol AttentionProvider: AnyObject {
    /// 当前注意力水平，范围 0.0（完全走神）到 1.0（完全专注）
    var currentAttention: Float { get }
    
    /// 注意力值的更新回调，约 30Hz 触发
    var onAttentionUpdate: ((Float) -> Void)? { get set }
    
    /// 开始/停止数据流
    func start()
    func stop()
    
    /// 当前正在进行的分心事件（如有）
    var activeDistraction: DistractionEvent? { get }
}
```

`SimulatedAttentionProvider` 的完整实现：

```swift
final class SimulatedAttentionProvider: AttentionProvider, ObservableObject {
    // MARK: - Public State
    @Published private(set) var currentAttention: Float = 0.3
    @Published private(set) var activeDistraction: DistractionEvent?
    var onAttentionUpdate: ((Float) -> Void)?
    
    // MARK: - Session Configuration
    let sessionDuration: TimeInterval  // 秒，默认 300（5分钟demo）或 900（15分钟完整）
    let level: Level                    // 当前关卡，决定分心模式
    
    // MARK: - Internal Parameters（构成"人格"的维度）
    private var baselineAttention: Float     // 个体基线，范围 0.3-0.7
    private var focusTrend: Float            // 全局上升趋势，范围 0.0-0.3
    private var distractibility: Float       // 被分心的概率，范围 0.0-1.0
    private var recoveryRate: Float          // 从分心中恢复的速度，范围 0.1-1.0
    private var noiseAmplitude: Float        // 高频抖动幅度，范围 0.01-0.05
    
    // MARK: - Internal State
    private var sessionStartTime: Date?
    private var timer: Timer?
    private var nextDistractionTime: TimeInterval = 0
    private var attentionHistory: [Float] = []     // 保留最近 300 个采样点（10秒 @ 30Hz）
    private let historyMaxSamples = 300
    
    // MARK: - Keyboard Override
    var manualOverrideActive = false
    var manualAttentionValue: Float = 1.0
    
    // MARK: - Initialization
    init(level: Level, sessionDuration: TimeInterval = 300) {
        self.level = level
        self.sessionDuration = sessionDuration
        
        // 根据 Level 分配人格参数
        let profile = Self.profileForLevel(level)
        self.baselineAttention = profile.baseline
        self.focusTrend = profile.focusTrend
        self.distractibility = profile.distractibility
        self.recoveryRate = profile.recoveryRate
        self.noiseAmplitude = profile.noiseAmplitude
    }
}
```

---

### 5.2 Level Personality Profiles（关卡人格配置表）

每个关卡有独立的"注意力人格"，决定了这个关卡模拟出来的注意力曲线形态。实现者必须严格按照下表参数：

| 关卡 | Realm | `baselineAttention` | `focusTrend` | `distractibility` | `recoveryRate` | `noiseAmplitude` | 行为特征 |
|------|-------|--------------------:|-------------:|-------------------:|---------------:|-----------------:|----------|
| 1. 涟漪绽放 | 觉醒 | 0.50 | 0.08 | 0.15 | 0.80 | 0.02 | 稳定、缓慢上升、极少分心 |
| 2. 萤火引路 | 觉醒 | 0.45 | 0.10 | 0.20 | 0.70 | 0.03 | 偶有波动、中等恢复 |
| 3. 星图寻迹 | 共鸣 | 0.40 | 0.12 | 0.35 | 0.55 | 0.03 | 频繁注意力转移、分心中等 |
| 4. 真假萤火 | 共鸣 | 0.35 | 0.15 | 0.45 | 0.50 | 0.04 | 竞争性注意力、多干扰 |
| 5. 飞燕破云 | 心流 | 0.38 | 0.18 | 0.55 | 0.40 | 0.04 | 动态追踪、突发干扰多 |
| 6. 流星试炼 | 心流 | 0.35 | 0.20 | 0.65 | 0.35 | 0.05 | 高难度、突发"海啸"事件 |

```swift
// MARK: - Profile Factory
struct AttentionProfile {
    let baseline: Float
    let focusTrend: Float
    let distractibility: Float
    let recoveryRate: Float
    let noiseAmplitude: Float
}

extension SimulatedAttentionProvider {
    static func profileForLevel(_ level: Level) -> AttentionProfile {
        switch level.id {
        case 1: return AttentionProfile(baseline: 0.50, focusTrend: 0.08, distractibility: 0.15, recoveryRate: 0.80, noiseAmplitude: 0.02)
        case 2: return AttentionProfile(baseline: 0.45, focusTrend: 0.10, distractibility: 0.20, recoveryRate: 0.70, noiseAmplitude: 0.03)
        case 3: return AttentionProfile(baseline: 0.40, focusTrend: 0.12, distractibility: 0.35, recoveryRate: 0.55, noiseAmplitude: 0.03)
        case 4: return AttentionProfile(baseline: 0.35, focusTrend: 0.15, distractibility: 0.45, recoveryRate: 0.50, noiseAmplitude: 0.04)
        case 5: return AttentionProfile(baseline: 0.38, focusTrend: 0.18, distractibility: 0.55, recoveryRate: 0.40, noiseAmplitude: 0.04)
        case 6: return AttentionProfile(baseline: 0.35, focusTrend: 0.20, distractibility: 0.65, recoveryRate: 0.35, noiseAmplitude: 0.05)
        default: return AttentionProfile(baseline: 0.45, focusTrend: 0.10, distractibility: 0.20, recoveryRate: 0.60, noiseAmplitude: 0.03)
        }
    }
}
```

---

### 5.3 DistractionEvent（分心事件系统）

```swift
// MARK: - Distraction Event
struct DistractionEvent {
    let startTime: TimeInterval      // 相对于 session 开始时间
    let duration: TimeInterval        // 持续 2-8 秒
    let depth: Float                  // 注意力下降幅度 0.3-0.8
    let recoveryCurve: RecoveryCurve  // 恢复曲线类型
    let type: DistractionType         // 分心类型标签
}

enum RecoveryCurve: String, CaseIterable {
    case linear        // 匀速恢复
    case exponential   // 快速恢复后趋平
    case sigmoid       // 慢启动 → 快速恢复 → 趋平
}

enum DistractionType: String, CaseIterable {
    case mildDrift     // 轻微走神（思绪飘远）
    case external      // 外部干扰（模拟突然的声响/光线）
    case fatigue       // 疲劳性分心（长时间注视后的注意力衰退）
    case tsunami       // 海啸事件（心流关卡专属：突然剧烈分心）
}
```

**分心事件生成规则：**

每个 Realm 有独立的分心调度器。在 `start()` 时一次性生成整场 session 的分心事件队列：

```swift
// MARK: - Distraction Schedule Generator
func generateDistractionSchedule(sessionDuration: TimeInterval, level: Level) -> [DistractionEvent] {
    var events: [DistractionEvent] = []
    var currentTime: TimeInterval = 5.0  // 前 5 秒不打扰
    
    let realm = level.realm
    let config = realm.distractionConfig
    
    while currentTime < sessionDuration - 10 {
        // 间隔：基于配置的 minInterval..maxInterval 随机
        let interval = TimeInterval(
            Float.random(in: config.minInterval...config.maxInterval)
        )
        currentTime += interval
        
        // 深度：基于配置的 depthRange 随机
        let depth = Float.random(in: config.depthRange)
        
        // 持续时间：2-8 秒，深度越大持续越久
        let duration = TimeInterval(2.0 + Double(depth) * 6.0)
        
        // 恢复曲线：根据深度选择
        let recoveryCurve: RecoveryCurve = depth > 0.6 ? .sigmoid : (depth > 0.4 ? .exponential : .linear)
        
        // 类型：根据 realm 和随机
        let type = config.possibleTypes.randomElement() ?? .mildDrift
        
        events.append(DistractionEvent(
            startTime: currentTime,
            duration: duration,
            depth: depth,
            recoveryCurve: recoveryCurve,
            type: type
        ))
    }
    
    return events
}
```

**Realm 分心配置表：**

| Realm | `minInterval` (秒) | `maxInterval` (秒) | `depthRange` | `possibleTypes` |
|-------|-------------------:|-------------------:|-------------:|-----------------|
| 觉醒 (1-2) | 30 | 60 | 0.2...0.4 | `[.mildDrift, .fatigue]` |
| 共鸣 (3-4) | 15 | 30 | 0.3...0.6 | `[.mildDrift, .external, .fatigue]` |
| 心流 (5-6) | 10 | 20 | 0.4...0.8 | `[.external, .fatigue, .tsunami]` |

**海啸事件特殊规则：** 仅在心流关卡（Level 5, 6）中出现。概率为 15%。特征：depth = 0.7-0.8，duration = 6-8 秒，recovery = sigmoid。模拟一种"正在心流中突然被剧烈打断"的体验。

---

### 5.4 核心更新循环（30Hz Tick）

这是整个模拟器的核心算法。每秒调用约 30 次：

```swift
// MARK: - Core Update Loop (called ~30 times per second)
private func updateAttention() {
    guard let startTime = sessionStartTime else { return }
    
    let elapsed = Date().timeIntervalSince(startTime)
    let progress = Float(elapsed / sessionDuration)  // 0.0 → 1.0
    
    // ── Step 1: 计算 Base Attention（渐进上升曲线） ──
    // 使用 Hermite 插值创造 S 形叙事弧线
    let baseAttention = calculateProgressiveFocus(progress: progress)
    
    // ── Step 2: 应用分心事件修正 ──
    var distractionModifier: Float = 0.0
    if let event = activeDistraction {
        let eventProgress = Float((elapsed - event.startTime) / event.duration)
        distractionModifier = calculateDistractionImpact(
            depth: event.depth,
            progress: min(eventProgress, 1.0),
            recoveryCurve: event.recoveryCurve
        )
    }
    
    // ── Step 3: 检查是否应触发新的分心事件 ──
    checkDistractionTrigger(elapsed: elapsed)
    
    // ── Step 4: 添加高频生理噪声 ──
    let noise = Float.random(in: -noiseAmplitude...noiseAmplitude)
    // 叠加一个 0.3Hz 的低频正弦波模拟自然呼吸节律
    let breathWave = sin(elapsed * 0.3 * .pi * 2) * 0.015
    
    // ── Step 5: 合成最终注意力值 ──
    var rawAttention = baseAttention - distractionModifier + noise + breathWave
    
    // ── Step 6: 键盘 Override ──
    if manualOverrideActive {
        rawAttention = manualAttentionValue
    }
    
    // ── Step 7: 钳位到 [0.0, 1.0] ──
    let clamped = max(0.0, min(1.0, rawAttention))
    
    // ── Step 8: 一阶低通滤波（模拟 EEG 信号的时间分辨率） ──
    // α = 0.3 意味着 ~100ms 的时间常数，足够平滑但不迟钝
    let alpha: Float = 0.3
    currentAttention = currentAttention * (1.0 - alpha) + clamped * alpha
    
    // ── Step 9: 记录历史 ──
    attentionHistory.append(currentAttention)
    if attentionHistory.count > historyMaxSamples {
        attentionHistory.removeFirst()
    }
    
    // ── Step 10: 回调 ──
    onAttentionUpdate?(currentAttention)
}
```

---

### 5.5 Progressive Focus Curve（渐进专注曲线）

整场 session 的注意力基线不是线性的。采用分段 Hermite 插值产生"学习叙事"：

```swift
// MARK: - Progressive Focus Curve
/// 将 session 进度 (0.0-1.0) 映射到注意力基线
/// 设计目标：模拟"一个人从进入状态到进入心流"的过程
private func calculateProgressiveFocus(progress: Float) -> Float {
    // 四段关键帧：
    // progress=0.0  → attention=baseline * 0.85  (刚坐下，还在适应)
    // progress=0.2  → attention=baseline * 1.0    (适应完毕，回到基线)
    // progress=0.5  → attention=baseline + focusTrend * 0.5  (学习中)
    // progress=0.85 → attention=baseline + focusTrend * 0.9  (接近巅峰)
    // progress=1.0  → attention=baseline + focusTrend * 0.7  (轻微回落，真实感)
    
    let keyframes: [(Float, Float)] = [
        (0.00, baselineAttention * 0.85),
        (0.20, baselineAttention),
        (0.50, baselineAttention + focusTrend * 0.5),
        (0.85, baselineAttention + focusTrend * 0.9),
        (1.00, baselineAttention + focusTrend * 0.7),
    ]
    
    // 找到 progress 所在的区间
    guard let idx = keyframes.lastIndex(where: { $0.0 <= progress }) else {
        return keyframes.last!.1
    }
    
    if idx == keyframes.count - 1 { return keyframes[idx].1 }
    
    let (t0, v0) = keyframes[idx]
    let (t1, v1) = keyframes[idx + 1]
    
    // 局部参数 t ∈ [0, 1]
    let t = (progress - t0) / (t1 - t0)
    
    // Hermite 平滑插值（smoothstep）
    let s = t * t * (3.0 - 2.0 * t)
    
    return v0 + (v1 - v0) * s
}
```

**对于 15 分钟完整 session 的各阶段预期输出：**

| 时间段 | Session 进度 | 预期注意力范围（Level 1） | 预期注意力范围（Level 6） | 叙事描述 |
|--------|-------------:|-------------------------:|-------------------------:|----------|
| 0-3 分钟 | 0%-20% | 0.35-0.55 | 0.22-0.42 | 入座适应，建立基线 |
| 3-8 分钟 | 20%-53% | 0.45-0.65 | 0.30-0.52 | 学习阶段，注意力逐步上升 |
| 8-13 分钟 | 53%-87% | 0.55-0.78 | 0.38-0.62 | 稳定高专注，偶有波动 |
| 13-15 分钟 | 87%-100% | 0.50-0.72 | 0.35-0.55 | 巅峰期，有短暂 >0.8 的"心流时刻"，然后轻微回落 |

---

### 5.6 Distraction Impact Function（分心冲击函数）

```swift
// MARK: - Distraction Impact
/// 根据分心事件的深度和进度计算注意力扣除值
private func calculateDistractionImpact(
    depth: Float,
    progress: Float,  // 0.0 = 刚开始分心, 1.0 = 分心结束
    recoveryCurve: RecoveryCurve
) -> Float {
    switch recoveryCurve {
    case .linear:
        // 前半段快速下降，后半段线性恢复
        if progress < 0.4 {
            return depth * (progress / 0.4)
        } else {
            return depth * (1.0 - (progress - 0.4) / 0.6)
        }
        
    case .exponential:
        // 快速下降，指数恢复
        let attack = depth * (1.0 - exp(-5.0 * progress))
        let release = depth * exp(-3.0 * max(0, progress - 0.3))
        return max(attack, release)
        
    case .sigmoid:
        // 慢启动 → 剧烈下降 → 缓慢恢复（适合"海啸"事件）
        if progress < 0.3 {
            // 缓慢下沉
            return depth * smoothstep(0.0, 0.3, progress)
        } else if progress < 0.5 {
            // 剧烈分心谷底
            return depth
        } else {
            // 缓慢恢复
            return depth * (1.0 - smoothstep(0.5, 1.0, progress))
        }
    }
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)
}
```

---

### 5.7 Attention → Feedback Mapping（注意力到反馈的精确映射）

这是连接"数据层"和"表现层"的核心函数。所有视觉和音频效果从此函数获取参数：

```swift
// MARK: - Feedback Mapping
struct FeedbackState {
    let visualIntensity: Float     // 0.0-1.0，控制场景整体亮度/饱和度
    let audioLowPassCutoff: Float  // Hz，200-20000
    let bloomStrength: Float       // 0.0-2.0，Metal post-processing bloom
    let particleDensity: Int       // 粒子数量
    let fogDensity: Float          // 0.0-1.0，场景迷雾浓度
    let sceneBrightness: Float     // 0.1-1.0，整体曝光
    let stimulusOpacity: Float     // 0.3-1.0，SSVEP 刺激目标透明度
    let ambientVolume: Float       // 0.0-1.0，环境音量
    let rewardChimeProbability: Float  // 0.0-1.0，每秒触发正向音效的概率
}

func feedbackCurve(_ attention: Float) -> FeedbackState {
    // ── Visual Intensity: sigmoid 映射，死区 0.2 以下，甜区 0.7 以上 ──
    let visualIntensity = smoothstep(0.2, 0.8, attention)
    
    // ── Audio Low-Pass: 走神时声音"沉入水底" ──
    // attention=0.0 → cutoff=200Hz（几乎听不到高频）
    // attention=0.5 → cutoff=2000Hz（沉闷）
    // attention=1.0 → cutoff=18000Hz（明亮通透）
    let audioCutoff: Float = 200.0 + attention * attention * 17800.0
    
    // ── Bloom: 专注时场景发出柔和光晕 ──
    let bloomStrength = smoothstep(0.3, 0.9, attention) * 1.5
    
    // ── Particle Density: 专注时萤火虫聚拢增多 ──
    let particleDensity = Int(attention * 800) + 100  // 最少 100，最多 900
    
    // ── Fog: 走神时迷雾弥漫 ──
    let fogDensity = 1.0 - smoothstep(0.2, 0.7, attention)
    
    // ── Scene Brightness ──
    let sceneBrightness = 0.15 + attention * 0.85
    
    // ── Stimulus Opacity: 目标闪烁的可见度 ──
    let stimulusOpacity = 0.3 + attention * 0.7
    
    // ── Ambient Volume ──
    let ambientVolume = smoothstep(0.1, 0.6, attention)
    
    // ── Reward Chime: 高专注时有概率触发正向音效 ──
    let rewardChimeProbability = attention > 0.75 ? (attention - 0.75) * 4.0 : 0.0
    
    return FeedbackState(
        visualIntensity: visualIntensity,
        audioLowPassCutoff: audioCutoff,
        bloomStrength: bloomStrength,
        particleDensity: particleDensity,
        fogDensity: fogDensity,
        sceneBrightness: sceneBrightness,
        stimulusOpacity: stimulusOpacity,
        ambientVolume: ambientVolume,
        rewardChimeProbability: rewardChimeProbability
    )
}
```

**关键设计决策：**

- `audioCutoff` 使用 `attention²` 的二次曲线而非线性，因为人耳对低频变化的感知比对高频变化更敏感。二次曲线让"从走神到恢复"的音色变化更有戏剧性。
- `fogDensity` 的 smoothstep 区间 (0.2, 0.7) 比 `visualIntensity` 的 (0.2, 0.8) 更窄。这意味着迷雾会**先于**其他视觉元素开始消退，创造一种"迷雾散开之前，光就已经开始渗透"的层次感。
- `rewardChimeProbability` 只在 attention > 0.75 时才非零，且最高为 1.0（attention=1.0 时）。实际触发频率约每 1-4 秒一次，避免音效疲劳。

---

### 5.8 Keyboard / Mouse Override（演示控制模式）

用于 Demo 演示时的手动控制。**仅在 `DEBUG` 或 `DEMO` 编译 flag 下激活。**

```swift
// MARK: - Demo Keyboard Override
extension SimulatedAttentionProvider {
    func handleKeyEvent(_ event: NSEvent) {
        #if DEBUG || DEMO
        switch event.keyCode {
        case 49: // SPACE
            if event.type == .keyDown {
                manualOverrideActive = true
                manualAttentionValue = 1.0
            } else if event.type == .keyUp {
                manualOverrideActive = false
                // 注意力自然衰减，由 updateAttention() 的低通滤波处理
            }
            
        case 2: // D key - 触发随机分心
            if event.type == .keyDown && !manualOverrideActive {
                triggerManualDistraction()
            }
            
        case 18: // 1 key - Level 1
            if event.type == .keyDown { switchToLevel(1) }
        case 19: // 2 key - Level 2
            if event.type == .keyDown { switchToLevel(2) }
        case 20: // 3 key - Level 3
            if event.type == .keyDown { switchToLevel(3) }
        case 21: // 4 key - Level 4
            if event.type == .keyDown { switchToLevel(4) }
        case 23: // 5 key - Level 5
            if event.type = .keyDown { switchToLevel(5) }
        case 22: // 6 key - Level 6
            if event.type == .keyDown { switchToLevel(6) }
            
        case 45: // N key - Toggle noise overlay (展示"有噪声 vs 无噪声"的区别)
            if event.type == .keyDown {
                noiseAmplitude = noiseAmplitude > 0 ? 0 : 0.03
            }
            
        default:
            break
        }
        #endif
    }
    
    private func triggerManualDistraction() {
        let event = DistractionEvent(
            startTime: Date().timeIntervalSince(sessionStartTime ?? Date()),
            duration: TimeInterval(Float.random(in: 3...7)),
            depth: Float.random(in: 0.3...0.7),
            recoveryCurve: [.linear, .exponential, .sigmoid].randomElement()!,
            type: [.mildDrift, .external, .fatigue].randomElement()!
        )
        activeDistraction = event
        
        // 在 duration 后清除
        DispatchQueue.main.asyncAfter(deadline: .now() + event.duration) { [weak self] in
            self?.activeDistraction = nil
        }
    }
}
```

**完整快捷键表：**

| 按键 | 动作 | 用途 |
|------|------|------|
| SPACE（按住） | 注意力 = 1.0 | 展示"完美专注"时的视觉/音频效果 |
| SPACE（释放） | 注意力自然衰减 | 展示从专注恢复到走神的过渡 |
| D | 触发随机分心事件 | 展示分心 → 恢复的完整循环 |
| 1-6 | 切换到对应关卡参数 | 快速展示不同难度的注意力曲线 |
| N | 切换噪声开关 | 对比有/无生理噪声的差异 |

---

### 5.9 Session Metrics Aggregator（心念图谱数据聚合器）

Debrief 阶段的数据来源。在 session 过程中持续聚合，session 结束后输出：

```swift
// MARK: - Session Metrics
struct SessionMetrics {
    /// 定力深度：整场 session 的平均注意力
    let depthOfTrance: Float
    
    /// 抗扰韧性：分心后的平均恢复速度（越高越好）
    let resilience: Float
    
    /// 心流时刻：持续专注 > 30 秒的次数
    let flowMoments: Int
    
    /// 最长连续专注时长（秒）
    let longestFocusStreak: TimeInterval
    
    /// 注意力波形数据（用于生成曼陀罗）
    let attentionWaveform: [Float]
    
    /// 分心事件记录
    let distractionLog: [DistractionEventRecord]
    
    /// Session 整体评级：1-5 星
    let overallRating: Int
}

struct DistractionEventRecord {
    let startTime: TimeInterval
    let depth: Float
    let recoveryTime: TimeInterval  // 从分心结束到注意力恢复到 0.6 以上
}
```

**评级算法：**

```swift
func calculateRating(metrics: SessionMetrics) -> Int {
    var score: Float = 0
    
    // 定力深度贡献 (0-2 分)
    score += min(2.0, metrics.depthOfTrance * 2.5)
    
    // 心流时刻贡献 (0-2 分)
    score += min(2.0, Float(metrics.flowMoments) * 0.5)
    
    // 抗扰韧性贡献 (0-1 分)
    score += min(1.0, metrics.resilience * 1.5)
    
    return max(1, min(5, Int(round(score))))
}
```

---

## Section 6: UX Flow & SwiftUI Interface（交互流程与界面）

> **设计哲学：这不是一个游戏。** 界面应让人联想到 Apple Mindfulness app 与 Apple Weather 的交叉：安静、有深度、留白充足。没有任何"游戏化"的 UI 元素（分数、排行榜、成就徽章）。所有的"游戏感"都来自 Metal 渲染的场景本身。

---

### 6.1 App Architecture & Navigation（应用架构与导航）

```
StarryFireflyApp (App 入口)
 └── StarryFireflyContentView (根 View)
      ├── if isFirstLaunch → OnboardingView
      └── else → MainNavigationView
      
MainNavigationView (NavigationSplitView, sidebar hidden)
 ├── HomeView (首页)
 ├── SessionView (训练流程容器，全屏 Metal)
 └── SettingsView (设置)
```

**SwiftUI View 层级图：**

```
App
├── @main StarryFireflyApp
│   └── WindowGroup
│       └── StarryFireflyContentView
│
├── OnboardingFlow (首次启动)
│   ├── OnboardingPage1: "什么是 SSVEP" (图 + 2 行文字)
│   ├── OnboardingPage2: "如何训练" (三步引导)
│   └── OnboardingPage3: "开始旅程" (按钮)
│
├── HomeView (返回用户的主界面)
│   ├── HomeBackgroundView (Metal 星空，dimmed 30%)
│   ├── VStack
│   │   ├── RealmBanner (境界徽章 + 鼓励语)
│   │   ├── LevelGrid (2×3 关卡卡片)
│   │   └── RecentSessions (最近 5 条记录)
│   └── .toolbar { SettingsLink }
│
├── SessionContainerView (训练全流程)
│   ├── Phase: Calibration
│   │   └── CalibrationMetalView (全屏 MTKView)
│   ├── Phase: Immersion
│   │   └── (Transition animation, 无独立 View)
│   ├── Phase: Training
│   │   ├── TrainingMetalView (全屏 MTKView)
│   │   └── TrainingControlOverlay (3-finger tap 显隐)
│   └── Phase: Debrief
│       └── DebriefView (SwiftUI)
│           ├── MandalaView (Metal 渲染的曼陀罗)
│           ├── MetricsCards (SwiftUI HStack)
│           └── ActionButtons (返回首页 / 分享)
│
└── SettingsView
    ├── VolumeSliders
    ├── DurationPicker
    ├── AccessibilityToggles
    └── AboutSection
```

---

### 6.2 Home Screen（首页）

**整体布局：垂直滚动，三个区域，从上到下。**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  [Metal 星空背景，opacity: 0.3]                   │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  🌿 第二境 · 入静                           │  │  ← RealmBanner
│  │  "你的心如止水，渐入佳境"                     │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ 🪷       │  │ 🪲       │  │ ✨       │         │  ← LevelGrid
│  │ 涟漪绽放  │  │ 萤火引路  │  │ ★       │         │    (2×3 grid)
│  │ 觉醒·壹   │  │ 觉醒·贰   │  │ 🔒      │         │
│  └─────────┘  └─────────┘  └─────────┘         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ 🔒       │  │ 🔒       │  │ 🔒       │         │
│  │ 星图寻迹  │  │ 真假萤火  │  │ 飞燕破云  │         │
│  │ 共鸣·壹   │  │ 共鸣·贰   │  │ 心流·壹   │         │
│  └─────────┘  └─────────┘  └─────────┘         │
│                                                  │
│  ─── 最近训练 ─────────────────────────────       │
│  ┌────────────────────────────────────────────┐  │
│  │  涟漪绽放 · 5分钟  ·  定力深度 0.72  ★★★★   │  │  ← RecentSessions
│  │  萤火引路 · 5分钟  ·  定力深度 0.65  ★★★    │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
└──────────────────────────────────────────────────┘
```

**SwiftUI 实现规范：**

```swift
struct HomeView: View {
    @StateObject private var sessionStore = SessionStore()
    @State private var selectedLevel: Level?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // 背景层：dimmed Metal 星空
            DimmedStarfieldView()
                .ignoresSafeArea()
            
            // 内容层
            ScrollView {
                VStack(spacing: 32) {
                    RealmBanner(realm: sessionStore.currentRealm)
                    
                    LevelGrid(
                        levels: Level.allCases,
                        unlockedUpTo: sessionStore.maxUnlockedLevel,
                        onSelect: { level in selectedLevel = level }
                    )
                    
                    RecentSessionsSection(sessions: sessionStore.recentSessions)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $selectedLevel) { level in
            SessionContainerView(level: level)
        }
    }
}
```

---

### 6.3 LevelCard（关卡卡片）精确规范

```swift
struct LevelCard: View {
    let level: Level
    let isLocked: Bool
    let lastSessionRating: Int?  // 最近一次评分，nil 表示从未玩过
    
    var body: some View {
        VStack(spacing: 10) {
            // 图标区域
            ZStack {
                Circle()
                    .fill(level.realm.accentColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                
                Image(systemName: level.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isLocked ? .secondary : level.realm.accentColor)
            }
            
            // 关卡名称
            Text(level.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(isLocked ? .tertiary : .primary)
            
            // 境界标签
            Text(level.realmTag)  // 例："觉醒·壹"
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            
            // 最近评分（如果有）
            if let rating = lastSessionRating, !isLocked {
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Image(systemName: i < rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(level.realm.accentColor.opacity(isLocked ? 0.05 : 0.15), lineWidth: 1)
        )
        .opacity(isLocked ? 0.45 : 1.0)
        .scaleEffect(isLocked ? 0.97 : 1.0)
    }
}
```

**颜色体系（所有颜色的精确值）：**

| 用途 | Light Mode | Dark Mode | 说明 |
|------|-----------|-----------|------|
| 觉醒 accent | `#4CAF50` (Green 500) | `#66BB6A` (Green 400) | 生机、觉醒 |
| 共鸣 accent | `#FFA726` (Orange 400) | `#FFB74D` (Orange 300) | 温暖、共鸣 |
| 心流 accent | `#EF5350` (Red 400) | `#EF5350` (Red 400) | 强烈、心流 |
| Card background | `.ultraThinMaterial` | `.ultraThinMaterial` | Apple 毛玻璃 |
| Primary text | `#1C1B1F` | `#F5F5F5` | System label |
| Secondary text | `#49454F` | `#CAC4D0` | System secondaryLabel |
| Tertiary text | `#79747E` | `#938F99` | System tertiaryLabel |
| Screen background | `#FFFBFE` | `#1C1B1F` | System background |

**Realm 标签文案：**

| Level | `name` | `realmTag` | `icon` (SF Symbol) |
|-------|---------|------------|-------------------|
| 1 | 涟漪绽放 | 觉醒·壹 | `drop.circle` |
| 2 | 萤火引路 | 觉醒·贰 | `sparkles` |
| 3 | 星图寻迹 | 共鸣·壹 | `star.circle` |
| 4 | 真假萤火 | 共鸣·贰 | `circle.grid.3x3` |
| 5 | 飞燕破云 | 心流·壹 | `bird` |
| 6 | 流星试炼 | 心流·贰 | `meteors` |

---

### 6.4 Calibration Phase（校准阶段）

**持续时间：** 15 秒。

**视觉设计：** 全屏 Metal 渲染。中央一个"星象仪"动画。

**动画分镜：**

| 时间 | 视觉 | 文字（Metal 内渲染） |
|------|------|-------------------|
| 0-2s | 黑暗中，星象仪从中心缩放出现 | "正在连接..." |
| 2-5s | 星象仪外环开始缓慢旋转，"阻抗检测"模拟 | 静电噪点 → 逐渐清晰 |
| 5-6s | 阻抗成功：清脆音效 + 外环亮起金色光弧 | "信号稳定" |
| 6-14s | 频率扫描：中心光点依次闪烁 10Hz → 15Hz → 20Hz → 30Hz → 40Hz，每个频率停留约 1.5 秒 | "正在校准频率..." |
| 14-15s | 最佳频率锁定（15Hz 或 20Hz），光点稳定在该频率 | "校准完成" |

**Metal 渲染要求：**

- 星象仪由三层同心圆环组成，每层独立旋转
- 外环：64 个刻度线，旋转速度 0.5°/frame
- 中环：12 个星座符号位，旋转速度 -0.3°/frame
- 内环：中心光点，执行频率扫描
- 材质：金属质感（Metallic = 0.8, Roughness = 0.3）
- 背景：深蓝黑色渐变 `#0A0E1A → #050810`

**校准阶段的 SwiftUI 壳：**

```swift
struct CalibrationView: View {
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            CalibrationMetalView(onComplete: onComplete)
                .ignoresSafeArea()
        }
    }
}
```

无任何 SwiftUI overlay。所有文字和动画都在 Metal shader 中渲染。

---

### 6.5 Training Phase（核心训练阶段）

**这是整个应用最重要的部分。**

**规则：训练期间零 SwiftUI overlay。整个屏幕是纯 MTKView。**

唯一的例外是一个极简的控制浮层，通过 **三指点击** 或 **鼠标右键** 触发：

```swift
struct TrainingControlOverlay: View {
    @Binding var isPresented: Bool
    let onPause: () -> Void
    let onEnd: () -> Void
    let remainingTime: TimeInterval
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 24) {
                // 暂停/继续
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                
                // 剩余时间
                Text(timeString(from: remainingTime))
                    .font(.system(size: 14, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                
                // 结束 session
                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 60)
            .padding(.horizontal, 40)
        }
        .opacity(isPresented ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: isPresented)
        // 3 秒无操作自动隐藏
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { isPresented = false }
            }
        }
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

**自动隐藏机制：** 浮层出现后启动 3 秒计时器。任何触摸/点击事件重置计时器。3 秒无交互则自动隐藏。

---

### 6.6 Debrief Phase: 心念图谱

**这是 session 结束后的数据展示页面。不是图表，是一幅"生成艺术"。**

**页面结构（从上到下）：**

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │                                            │  │
│  │         [Metal 曼陀罗生成艺术]              │  │  ← MandalaView
│  │         注意力波形 → 极坐标变换              │  │     (300×300 pt)
│  │         颜色映射到 realm accent             │  │
│  │                                            │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  "涟漪绽放" · 5分钟 · 2026年4月22日              │
│                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐         │
│  │ 🏔️       │ │ 🛡️       │ │ ✨       │         │
│  │ 定力深度  │ │ 抗扰韧性  │ │ 心流时刻  │         │
│  │ 0.72     │ │ 0.85     │ │ 3 次     │         │  ← MetricsCards
│  │ ██████░░ │ │ █████░░░ │ │ ★★★★☆   │         │
│  └──────────┘ └──────────┘ └──────────┘         │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  总评: ★★★★☆                                │  │
│  │  "你的心念如湖面般平静，偶有涟漪"             │  │  ← RatingCard
│  └────────────────────────────────────────────┘  │
│                                                  │
│  [ 保存图片 ]  [ 返回首页 ]                       │  │  ← ActionButtons
│                                                  │
└──────────────────────────────────────────────────┘
```

**DebriefView 完整实现规范：**

```swift
struct DebriefView: View {
    let metrics: SessionMetrics
    let level: Level
    let attentionWaveform: [Float]
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // 深色背景
            Color(red: 0.04, green: 0.05, blue: 0.10)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 28) {
                    // 曼陀罗
                    MandalaView(
                        waveform: attentionWaveform,
                        accentColor: level.realm.accentColor,
                        size: 300
                    )
                    .frame(width: 300, height: 300)
                    .padding(.top, 40)
                    
                    // Session 标题
                    VStack(spacing: 4) {
                        Text(level.name)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text(sessionSubtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    
                    // 三项指标
                    HStack(spacing: 16) {
                        MetricCard(
                            title: "定力深度",
                            value: String(format: "%.2f", metrics.depthOfTrance),
                            icon: "mountain.2",
                            color: .green
                        )
                        MetricCard(
                            title: "抗扰韧性",
                            value: String(format: "%.2f", metrics.resilience),
                            icon: "shield",
                            color: .blue
                        )
                        MetricCard(
                            title: "心流时刻",
                            value: "\(metrics.flowMoments) 次",
                            icon: "sparkle",
                            color: .yellow
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // 总评
                    RatingCard(rating: metrics.overallRating, level: level)
                        .padding(.horizontal, 24)
                    
                    // 操作按钮
                    HStack(spacing: 16) {
                        Button(action: saveMandalaImage) {
                            Label("保存图片", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(level.realm.accentColor.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: onDismiss) {
                            Label("返回首页", systemImage: "house")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
```

**MetricCard 组件：**

```swift
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }
}
```

**评语映射表（`RatingCard` 的文案）：**

| Rating | 评语 | Realm 对应 |
|--------|------|-----------|
| ★☆☆☆☆ | "心猿意马，万念纷飞。不必急躁，修行重在坚持。" | 所有 |
| ★★☆☆☆ | "你的心念如风中烛火，虽有摇曳，却不曾熄灭。" | 所有 |
| ★★★☆☆ | "湖面泛起涟漪，但底下的水是静的。你在进步。" | 所有 |
| ★★★★☆ | "你的心念如湖面般平静，偶有涟漪。" | 觉醒/共鸣 |
| ★★★★☆ | "星河倒映心海，你与宇宙的频率渐渐同步。" | 心流 |
| ★★★★★ | "八风吹不动。此刻，你就是星空本身。" | 所有 |

---

### 6.7 Phase Transitions（阶段转场动画）

所有转场使用 `withAnimation(.easeInOut(duration:))` 或 Metal 内部的 shader transition。

| 转场 | 时长 | 缓动曲线 | 实现方式 | 描述 |
|------|-----:|---------|---------|------|
| Home → Calibration | 0.5s | `.easeInOut` | SwiftUI `.opacity` + `.scaleEffect` | 星空背景渐亮，UI 元素 fade out |
| Calibration → Immersion | 1.0s | `.easeIn` | Metal shader：星象仪环向外扩展至充满屏幕 | 星象仪"绽放"为场景 |
| Immersion → Training | 2.0s | `.easeInOut` | Metal shader：从纯黑渐入场景 | 场景从黑暗中浮现 |
| Training → Debrief | 1.5s | `.easeOut` | Metal shader：场景渐黑 → 曼陀罗 materialize | 双阶段：先暗场，再显形 |
| Debrief → Home | 0.8s | `.easeInOut` | SwiftUI `.matchedGeometryEffect` + `.scaleEffect` | 曼陀罗缩小回对应关卡卡片位置 |

**Immersion → Training 的 Metal shader 伪代码：**

```metal
// Fragment shader: fade_from_black
// uniform float uProgress; // 0.0 → 1.0, over 2.0 seconds

float4 fragment(VertexOutput in [[stage_in]],
                 constant FragmentUniforms &uniforms [[buffer(0)]]) {
    float4 sceneColor = renderScene(in.position);  // 完整场景渲染
    float fade = smoothstep(0.0, 0.6, uniforms.uProgress);
    return float4(sceneColor.rgb * fade, 1.0);
}
```

**Training → Debrief 的双阶段转场：**

Phase 1 (0-0.8s): 场景渐黑
Phase 2 (0.8-1.5s): 曼陀罗从中心扩展出现（scale 0.3 → 1.0, opacity 0 → 1）

---

### 6.8 Settings View（设置页面）

遵循 Apple HIG 标准 Settings 页面风格。使用 `Form` + `Section`：

```swift
struct SettingsView: View {
    @AppStorage("masterVolume") private var masterVolume = 0.7
    @AppStorage("binauralVolume") private var binauralVolume = 0.5
    @AppStorage("ambientVolume") private var ambientVolume = 0.6
    @AppStorage("sessionDuration") private var sessionDuration = 5  // 分钟
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("reduceMotion") private var reduceMotion = false
    
    var body: some View {
        Form {
            // MARK: - 音频
            Section("音频") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("主音量")
                    Slider(value: $masterVolume, in: 0...1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("双脑同步音波")
                    Slider(value: $binauralVolume, in: 0...1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("环境音效")
                    Slider(value: $ambientVolume, in: 0...1)
                }
            }
            
            // MARK: - 训练
            Section("训练") {
                Picker("训练时长", selection: $sessionDuration) {
                    Text("3 分钟").tag(3)
                    Text("5 分钟").tag(5)
                    Text("10 分钟").tag(10)
                    Text("15 分钟").tag(15)
                    Text("20 分钟").tag(20)
                }
                .pickerStyle(.segmented)
            }
            
            // MARK: - 辅助功能
            Section("辅助功能") {
                Toggle("触觉反馈", isOn: $hapticsEnabled)
                Toggle("减少动效", isOn: $reduceMotion)
            }
            
            // MARK: - 关于
            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0 (Demo)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("研究来源")
                    Spacer()
                    Text("详见「关于」")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://example.com/research")!) {
                    HStack {
                        Text("SSVEP 注意力训练研究")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
```

---

## Section 7: Apple HIG Alignment & Accessibility（Apple 设计规范与无障碍）

---

### 7.1 HIG Principles Mapping（Apple 人机界面原则映射表）

| Apple HIG 原则 | 在本应用中的具体实现 | 设计决策依据 |
|----------------|---------------------|-------------|
| **Aesthetic Integrity（美学完整性）** | 全程深色宇宙主题，Metal 渲染的场景和 SwiftUI UI 在视觉上无缝融合。毛玻璃卡片 (`.ultraThinMaterial`) 漂浮在星空之上。 | 应用本质是冥想工具，美学应传达"深邃、宁静、科技感"。 |
| **Consistency（一致性）** | 使用系统字体 (`.system(design: .rounded)`)、系统颜色 (`.label`, `.secondaryLabel`)、标准 SwiftUI 控件 (Toggle, Slider, Picker)。Navigation 使用标准 `NavigationSplitView`。 | 用户无需学习自定义 UI 模式。训练场景是唯一的"非常规"区域，但这是刻意设计。 |
| **Direct Manipulation（直接操控）** | Home 页关卡卡片直接点击进入。训练中无 UI，用户通过"眼神"（模拟注意力）直接操控场景。Debrief 页曼陀罗可拖拽旋转。 | 冥想训练的核心是"无中介"的体验。去除所有中间 UI 层。 |
| **Feedback（反馈）** | 专注 → 场景变亮、萤火虫聚拢、音色通透。走神 → 迷雾弥漫、音色沉闷。分心恢复 → 短促的正向音效 (haptic + audio)。 | 所有反馈都是"环境叙事"，不是"数字显示"。绝不出现进度条或数值。 |
| **Metaphors（隐喻）** | 星空 = 意识空间。萤火虫 = 注意力粒子。迷雾 = 分心/杂念。莲花绽放 = 进入心流。 | 东方正念哲学与神经科学的交汇。用自然现象描述心理状态。 |
| **User Control（用户控制）** | 训练前可选择关卡和时长。训练中可暂停/退出。所有数据本地存储。 | 用户始终拥有控制权，但不被不必要的选择干扰。 |

---

### 7.2 Accessibility（无障碍功能）

#### 7.2.1 Reduce Motion（减少动效）

当用户在系统设置中开启"减少动效"时，应用必须做出以下调整：

| 原始效果 | Reduce Motion 替代方案 |
|----------|----------------------|
| 粒子系统（萤火虫群） | 静态场景 + 缓慢呼吸亮度变化（2 秒周期） |
| 场景过渡（星象仪扩展、渐入等） | 简单 crossfade（0.3s） |
| Bloom post-processing | 禁用 bloom，使用静态光晕图片 |
| 迷雾动态变化 | 迷雾浓度跳变（不走渐变曲线） |
| 校准星象仪旋转动画 | 静态星象仪 + 进度文字 |

```swift
// 在所有动画处检查此环境变量
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// 替代方案
func animationDuration(_ normal: TimeInterval) -> TimeInterval {
    return reduceMotion ? 0.3 : normal
}

func shouldEnableParticles() -> Bool {
    return !reduceMotion
}
```

#### 7.2.2 VoiceOver 支持

Metal 渲染的内容无法被 VoiceOver 读取，因此需要周期性地通过 `Accessibility.post(notification:argument:)` 广播场景状态：

```swift
// 每 5 秒广播一次场景状态（训练阶段）
func announceSceneState(attention: Float, level: Level) {
    let description: String
    
    switch attention {
    case ..<0.2:
        description = "你的注意力较低，场景被迷雾笼罩。试着将目光集中在闪烁的光源上。"
    case 0.2..<0.5:
        description = "你的注意力一般。迷雾正在缓慢散开。"
    case 0.5..<0.7:
        description = "你的注意力较好。场景逐渐清晰，光线正在聚集。"
    case 0.7..<0.9:
        description = "你的注意力很好。萤火虫正在聚拢，光芒越来越亮。"
    default:
        description = "你进入了深度专注状态。万物宁静，星光灿烂。"
    }
    
    AccessibilityNotification.announcement(description).post()
}
```

**所有 SwiftUI View 必须设置 `.accessibilityLabel` 和 `.accessibilityHint`：**

```swift
LevelCard(level: level, isLocked: isLocked)
    .accessibilityLabel("\(level.name)，\(level.realmTag)")
    .accessibilityHint(isLocked ? "已锁定，完成前一关卡后解锁" : "双击开始训练")
    .accessibilityAddTraits(isLocked ? [] : [.isButton])
    .accessibilityRemoveTraits(isLocked ? [] : [.isStaticText])
```

#### 7.2.3 Color Blindness（色盲支持）

设计规范要求：**永远不依赖纯色彩差异来传达信息。**

在本应用中，目标 (Target, 15Hz) 和干扰项 (Distractor, 20Hz) 的区分方式：

| 区分维度 | Target (15Hz) | Distractor (20Hz) |
|----------|:------------:|:-----------------:|
| 颜色 | 生物荧光绿 `#CDDC39` | 幽冷星蓝 `#8AB4F8` |
| **形状** | **圆形** | **菱形** |
| **大小** | **较大** | **较小** |
| **闪烁频率** | 15 Hz | 20 Hz |
| **运动模式** | 缓慢漂浮 | 快速闪烁抖动 |

即使在完全色盲的情况下，用户也能通过形状、大小、运动模式区分目标和干扰项。

#### 7.2.4 Dynamic Type（动态字体）

所有 SwiftUI 文本（Metal 渲染的文字除外）必须支持 Dynamic Type：

```swift
Text(level.name)
    .font(.system(size: 15, weight: .semibold, design: .rounded))
    // 不写死 .font(.body)，而是使用 relative size
    // 让系统自动缩放

// 对于需要固定布局的卡片，使用 minimumScaleFactor
Text(level.realmTag)
    .font(.system(size: 12, weight: .regular))
    .minimumScaleFactor(0.8)
    .lineLimit(1)
```

---

### 7.3 System Integration（系统集成）

#### 7.3.1 Dark Mode（深色模式）

应用本质上是深色的。但在 SwiftUI 部分，所有颜色必须支持 Light/Dark 切换：

```swift
// 正确做法：使用语义颜色
.foregroundStyle(.primary)          // 自动适配
.background(.ultraThinMaterial)    // 自动适配

// 错误做法：写死颜色
.foregroundStyle(Color.white)      // Light mode 下不可读
```

训练阶段的 Metal 场景始终为深色，不随系统切换。

#### 7.3.2 Focus Modes（专注模式）

```swift
// 在训练 session 开始时，请求系统的专注模式权限
func requestFocusMode() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { granted in
        if granted {
            // 训练期间不推送通知
            // 但不需要主动设置 DND，只需不发送本地通知即可
        }
    }
}
```

应用本身不主动发送通知。唯一的本地通知场景是"每日训练提醒"（用户在设置中开启后），该通知应尊重系统 Focus Mode。

#### 7.3.3 Thermal Management（热管理）

Metal 渲染的粒子系统在设备发热时会自动降级：

```swift
class PerformanceMonitor {
    func adaptiveParticleCount(baseCount: Int) -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return baseCount
        case .fair:
            return Int(Double(baseCount) * 0.75)
        case .serious:
            return Int(Double(baseCount) * 0.5)
        case .critical:
            return Int(Double(baseCount) * 0.25)  // 仅保留最核心的粒子
        @unknown default:
            return baseCount
        }
    }
    
    func adaptiveBloomStrength(baseStrength: Float) -> Float {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return baseStrength
        case .fair: return baseStrength * 0.7
        case .serious: return baseStrength * 0.4
        case .critical: return 0.0  // 完全禁用 bloom
        @unknown default: return baseStrength
        }
    }
}
```

#### 7.3.4 Energy Efficiency（能效）

- Metal 渲染使用 `CAMetalLayer.present()` 而非 `CVDisplayLink`，让系统决定最佳刷新率
- 无活跃交互时（如 Debrief 页面静止状态），Metal view 降频至 30 FPS
- 使用 `os_signpost` 标记性能关键路径，便于 Instruments 分析

---

### 7.4 Performance Targets（性能目标）

| 指标 | 目标值 | 测量方式 | 备注 |
|------|-------|---------|------|
| **Frame Rate** | 120 FPS (ProMotion display) / 60 FPS (标准) | Xcode Metal GPU Frame Debugger | 训练阶段必须稳定，Debrief 可降至 30 FPS |
| **Frame Drop Rate** | <0.1% (千分之一) | 自定义 frame counter，每 1000 帧统计一次 | 连续 3 帧以上 drop 算一次"卡顿事件" |
| **Audio Latency** | <50ms（从注意力状态变化到音频参数更新） | `AVAudioEngine` 的 `inputTime` vs `outputTime` 差值 | 关键路径：SimulatedAttentionProvider.update → AVAudioNode parameters |
| **Memory** | <200MB RSS | Xcode Memory Graph | Metal 纹理池 < 80MB，粒子缓冲区 < 20MB |
| **CPU** | <30% on M1 MacBook Pro (8-core) | Activity Monitor → % CPU | 主线程 < 5%（仅 SwiftUI），Metal 专用线程 < 20%，Audio < 5% |
| **GPU** | <50% on M1 GPU (7-core) | Xcode Metal GPU Profiler | 包含 bloom post-processing |
| **App Launch to Interactive** | <2s (cold), <0.5s (warm) | Instruments → App Launch | Preload Metal pipeline state objects |
| **Metal View Setup** | <100ms | `MTKViewDelegate.draw(in:)` 首帧时间戳差 | Shader compilation 在启动时预编译 |

---

### 7.5 Metal Performance Budgets（Metal 渲染预算）

**每个 Frame 的 GPU 时间预算：**

| 60 FPS Display | 120 FPS Display |
|----------------|-----------------|
| 16.67ms / frame | 8.33ms / frame |

**预算分配（60 FPS 为例）：**

| Render Pass | 预算 | 占比 |
|-------------|-----:|-----:|
| Background (星空) | 2.0ms | 12% |
| Particles (萤火虫) | 3.0ms | 18% |
| Scene Elements (莲花/石碑/灵燕) | 2.0ms | 12% |
| SSVEP Stimulus (闪烁目标) | 0.5ms | 3% |
| Fog / Atmosphere | 1.0ms | 6% |
| Bloom Post-Process | 3.0ms | 18% |
| Composite & Output | 1.0ms | 6% |
| **Buffer** | **4.17ms** | **25%** |

---

### 7.6 Animation Timing Reference（动画时序参考）

**所有动画时序的权威规范：**

| 动画 | 时长 | 缓动曲线 | 用途 |
|------|-----:|---------|------|
| 卡片 hover | 0.2s | `.easeOut` | 鼠标悬停微反馈 |
| 卡片 press | 0.1s | `.easeIn` | 按下缩放 |
| 页面 push | 0.35s | `.easeInOut` | Navigation push |
| 页面 pop | 0.3s | `.easeInOut` | Navigation pop |
| Home → Calibration | 0.5s | `.easeInOut` | 进入训练流程 |
| Calibration → Immersion | 1.0s | `.easeIn` | 校准完成，场景展开 |
| Immersion → Training | 2.0s | `.easeInOut` | 黑暗到场景浮现 |
| Training → Debrief | 1.5s | `.easeOut` | 场景消失，数据显现 |
| Debrief → Home | 0.8s | `.easeInOut` | 返回首页 |
| Control overlay 显隐 | 0.3s | `.easeInOut` | 浮层淡入淡出 |
| 注意力 → 视觉反馈 | 实时 | 低通滤波 α=0.3 | ≈100ms 响应时间 |
| 注意力 → 音频反馈 | 实时 | 低通滤波 α=0.2 | ≈150ms 响应时间 |
| Haptic feedback | 0.1s | N/A | `UIImpactFeedbackGenerator(.soft)` |
| 心流达成音效 | 0.8s | `.easeOut` | 颂钵声 + 高频泛音衰减 |

---

### 7.7 Font Specification（字体规范）

**Metal 渲染内使用的字体（用于 Calibration 阶段文字）：**

| 用途 | 字体 | 大小 | 权重 | 颜色 |
|------|------|-----:|------|------|
| 校准主文字 | "PingFang SC" | 24pt | Regular | `#FFFFFF` opacity 0.8 |
| 校准副文字 | "PingFang SC" | 16pt | Light | `#FFFFFF` opacity 0.5 |

**SwiftUI 使用的字体：**

| 用途 | Font | 说明 |
|------|------|------|
| 关卡名称 | `.system(size: 15, weight: .semibold, design: .rounded)` | 圆角无衬线 |
| 境界标签 | `.system(size: 12, weight: .regular)` | 次级信息 |
| 首页标题 | `.system(size: 28, weight: .bold, design: .rounded)` | RealmBanner |
| 首页副标题 | `.system(size: 15, weight: .regular)` | 鼓励语 |
| 指标数值 | `.system(size: 28, weight: .bold, design: .rounded)` | MetricCard |
| 指标标签 | `.system(size: 12)` | MetricCard |
| 评语 | `.system(size: 16, weight: .regular, design: .rounded)` | RatingCard |
| 按钮文字 | `.system(size: 15, weight: .medium)` | ActionButtons |
| 设置标题 | `.system(size: 20, weight: .semibold)` | Section header |
| 设置正文 | `.system(size: 17)` | Form content |

**设计约束：** 不使用任何自定义字体。全部使用 SF Pro / PingFang SC 系统字体。`design: .rounded` 仅用于标题和关卡名称，正文使用默认的 `.default` design。
