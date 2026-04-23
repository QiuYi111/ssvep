# 星空与萤火（Starfield & Fireflies）— 技术实现计划

> **版本**: v1.0
> **平台**: macOS 14+ (Sonoma), Apple Silicon
> **技术栈**: Swift + Metal + SwiftUI + AVAudioEngine
> **目标**: Demo 演示应用，展示 SSVEP 注意力训练的最佳视听体验
> **约定**: 中文正文 + 英文技术术语保持原样，代码块中全英文

---

**目录**

1. 项目架构与工程基础
2. Metal 渲染管线与 SSVEP 频率控制器
3. 音频引擎与反馈系统
4. 六关卡详细规格
5. 模拟注意力系统
6. 交互流程与界面
7. Apple HIG 对齐与无障碍

---

# 星空与萤火 — 技术实现计划 · Section 1: 工程基础架构

> **版本**: v1.0-draft
> **目标读者**: 实现工程师（可直接编码，无需额外讨论）
> **约定**: 中文正文 + 英文技术术语保持原样，代码块中全英文

---

## 1.1 项目结构

### 1.1.1 Xcode 项目配置

**项目类型**: 单 App Target，不使用 SPM package，不做 framework 拆分。Demo 阶段所有代码在一个 target 内。

| 配置项 | 值 |
|---|---|
| Product Name | `StarfieldFireflies` |
| Organization Identifier | `com.yourorg.ssvep`（替换为实际值） |
| Interface | SwiftUI |
| Language | Swift |
| Deployment Target | **macOS 14.0 (Sonoma)** |
| Minimum Xcode | Xcode 15.0+ |
| Architecture | Apple Silicon (arm64) |

> **为什么 macOS 14+**: ProMotion 120Hz 在 MacBook Pro 14"/16" (2021 以后) 上需要 macOS 14 的 CADisplayLink / MTKView 才能正确请求 120fps preferredFrameRateRange。macOS 13 及以下即使硬件支持，API 层面也拿不到稳定的 120Hz。

### 1.1.2 文件夹层级

在 Xcode Navigator 中创建以下 group 结构（对应文件系统中 `StarfieldFireflies/` 下的目录）：

```
StarfieldFireflies/
├── App/
│   ├── StarfieldFirefliesApp.swift          // @main 入口，定义 WindowGroup
│   └── AppDelegate.swift                     // NSApplicationDelegateAdapter（仅当需要非 SwiftUI 窗口操作时）
│
├── Models/
│   ├── AppState.swift                        // 全局 app 状态枚举 + ObservableObject
│   ├── SessionPhase.swift                    // 会话阶段状态机
│   ├── LevelID.swift                         // 6 个关卡的 ID 与配置
│   ├── AttentionState.swift                  // 注意力状态枚举
│   ├── AttentionSample.swift                 // 单条注意力采样数据结构
│   └── UserProfile.swift                     // 用户进度（UserDefaults 持久化）
│
├── Services/
│   ├── Attention/
│   │   ├── AttentionProvider.swift           // protocol：注意力数据源抽象
│   │   ├── SimulatedAttention.swift          // demo 用：模拟注意力数据生成
│   │   └── AttentionManager.swift            // 注意力状态判定 + Combine publisher
│   │
│   ├── Audio/
│   │   ├── AudioEngine.swift                 // AVAudioEngine 管理器
│   │   ├── SoundscapeGenerator.swift         // 环境音生成（binaural beats）
│   │   └── FeedbackSoundBank.swift           // 注意力反馈音效池
│   │
│   ├── Haptics/
│   │   └── HapticEngine.swift                // CoreHaptics 封装（macOS 轨迹板）
│   │
│   └── Session/
│       ├── SessionController.swift           // 会话生命周期控制器
│       └── CalibrationEngine.swift           // 校准流程引擎
│
├── Rendering/
│   ├── Metal/
│   │   ├── MetalRenderer.swift                // MTKViewDelegate 主渲染器
│   │   ├── MetalEngine.swift                  // MTLDevice / MTLCommandQueue 初始化
│   │   ├── Shaders/
│   │   │   ├── Shared.metal                   // Metal shader 共享头文件
│   │   │   ├── Starfield.metal                // 星空粒子 compute + vertex + fragment
│   │   │   ├── Firefly.metal                  // 萤火虫粒子系统
│   │   │   ├── SSVEPStimulus.metal            // SSVEP 刺激渲染（频闪 overlay）
│   │   │   ├── PostProcess.metal              // 后处理（bloom, 色调映射）
│   │   │   └── AttentionVisual.metal          // 注意力状态视觉反馈 shader
│   │   ├── Buffers/
│   │   │   ├── ParticleBufferManager.swift    // GPU 粒子 buffer 管理
│   │   │   └── UniformBufferManager.swift     // Uniform buffer 跨帧更新
│   │   └── Pipelines/
│   │       ├── PipelineStateCache.swift       // MTLRenderPipelineState 缓存
│   │       └── ComputePipelineCache.swift     // MTLComputePipelineState 缓存
│   │
│   └── SwiftUI/
│       ├── MetalView.swift                    // NSViewRepresentable 包装 MTKView
│       ├── OverlayView.swift                  // SwiftUI overlay（非 HUD，自然视觉元素）
│       └── TransitionOverlay.swift            // 场景切换过渡动画
│
├── Views/
│   ├── Home/
│   │   ├── HomeView.swift                     // 主界面：星空背景 + 关卡选择
│   │   ├── LevelCard.swift                    // 单个关卡卡片
│   │   └── LevelGridView.swift                // 关卡网格布局
│   │
│   ├── Session/
│   │   ├── SessionContainerView.swift         // 会话容器：MetalView + Overlay
│   │   ├── CalibrationView.swift              // 校准界面
│   │   ├── ImmersionView.swift                // 沉浸引导
│   │   ├── DebriefView.swift                  // 结束回顾
│   │   └── SessionHUDView.swift               // 极简 HUD（仅显示时间，可隐藏）
│   │
│   └── Onboarding/
│       ├── OnboardingView.swift               // 首次使用引导
│       └── OnboardingPage.swift               // 单页引导内容
│
├── Utilities/
│   ├── FrameCounter.swift                     // 严格帧计数器（SSVEP 刺激用）
│   ├── ThermalMonitor.swift                   // NSProcessInfo.thermalState 监控
│   ├── PerformanceMonitor.swift               // FPS / Metal 性能统计
│   └── Extensions/
│       ├── Float+Helpers.swift                // 数学工具扩展
│       ├── Color+Metal.swift                  // SwiftUI.Color ↔ SIMD3<Float> 转换
│       └── MTKView+ProMotion.swift            // ProMotion 120Hz 配置扩展
│
├── Resources/
│   ├── Assets.xcassets/                       // App icon, 颜色, 图片资源
│   └── Audio/
│       └── (无预录制文件，全部实时合成)          // binaural beats, 反馈音效均由 AVAudioEngine 生成
│
└── Info.plist
    └── (无特殊 entry，全部使用 Xcode target 设置)
```

### 1.1.3 Build Settings 关键配置

在 Xcode Target → Build Settings 中确认以下设置：

```
SWIFT_VERSION = 5.9
MACOSX_DEPLOYMENT_TARGET = 14.0
ALWAYS_SEARCH_USER_PATHS = NO
CLANG_ENABLE_MODULES = YES
OTHER_LDFLAGS = (空，不手动链接 framework)
ENABLE_PREVIEWS = YES
COMBINE_HIDPI_IMAGES = YES
```

> Xcode 15+ 对 Apple frameworks 使用自动 linking，无需手动在 `OTHER_LDFLAGS` 中添加 `-framework Metal` 等。在代码中 `import Metal` 即可。但如果有链接问题，手动添加。

---

## 1.2 依赖列表

### 1.2.1 Apple Framework 依赖（全部内置，零第三方）

| Framework | Import 语句 | 用途 | 使用位置 |
|---|---|---|---|
| **Metal** | `import Metal` | GPU 渲染核心，所有视觉效果通过 Metal shader 渲染 | `Rendering/Metal/` 全部文件 |
| **MetalKit** | `import MetalKit` | `MTKView` 视图容器 + `MTKViewDelegate` 渲染循环 | `MetalView.swift`, `MetalRenderer.swift` |
| **MetalPerformanceShaders** | `import MetalPerformanceShaders` | MPS 提供的高性能后处理（`MPSImageGaussianBlur` 用于 bloom） | `PostProcess.metal`, `MetalRenderer.swift` |
| **SwiftUI** | `import SwiftUI` | UI 层，所有非 Metal 的视图组件 | `Views/` 全部文件 |
| **AppKit** | `import AppKit` | macOS 窗口管理、`NSView`、`NSWindow` 配置 | `MetalView.swift` (NSViewRepresentable), `AppDelegate.swift` |
| **AVFoundation** | `import AVFoundation` | `AVAudioEngine` 实时音频生成与播放 | `Services/Audio/` 全部文件 |
| **CoreHaptics** | `import CoreHaptics` | 触觉反馈（macOS 轨迹板震动） | `HapticEngine.swift` |
| **Combine** | `import Combine` | 响应式数据流，连接 AttentionManager → UI / Audio / Haptics | `AttentionManager.swift`, `SessionController.swift` |
| **Accelerate** | `import Accelerate` | `vDSP` 信号处理（未来真实 EEG 信号时用于 FFT；demo 阶段可不用但保留 import） | `CalibrationEngine.swift`（预留） |
| **QuartzCore** | `import QuartzCore` | `CADisplayLink`（备选：MTKView delegate 优先，CADisplayLink 仅作 fallback 或性能监控） | `PerformanceMonitor.swift` |
| **CoreGraphics** | `import CoreGraphics` | `CGDirectDisplayID` 获取显示器刷新率，确认 ProMotion 生效 | `MTKView+ProMotion.swift` |
| **Foundation** | `import Foundation` | 基础类型、`DispatchQueue`、`Timer`、`UserDefaults` | 全局 |
| **GameplayKit** | `import GameplayKit` | `GKRandomSource` / `GKPerlinNoise` 用于萤火虫运动路径噪声生成 | `Firefly.metal` 对应的 Swift 端初始化 |
| **Observation** | `import Observation` | macOS 14+ `@Observable` 宏，替代部分 `ObservableObject` + `@Published` | `AppState.swift`, `SessionController.swift` |

### 1.2.2 各 Framework 详细用途说明

**Metal / MetalKit / MetalPerformanceShaders**

这是整个 app 视觉层的基石。所有像素都通过 Metal 渲染，SwiftUI 仅负责布局容器和 overlay 文字。

- `MTKView` 作为渲染目标，嵌入 SwiftUI 视图层级
- `MTKViewDelegate.draw(in:)` 是每帧渲染入口
- Metal Shaders（`.metal` 文件）负责：星空粒子更新/渲染、萤火虫运动/发光、SSVEP 频闪刺激叠加、bloom 后处理
- MPS `MPSImageGaussianBlur` 或自定义 compute shader 做 bloom pass（建议自定义，MPS 的 blur 在某些 Apple Silicon 上有延迟 spike）

**AVFoundation**

音频全部实时合成，不播放预录制文件：

- `AVAudioEngine` 作为音频图：`AVAudioSourceNode` → `AVAudioMixerNode` → `AVAudioOutputNode`
- `AVAudioSourceNode` 的 render block 中实时生成 binaural beats（左右声道差频 = SSVEP 目标频率）
- 注意力反馈音效（进入专注 / 失焦）通过动态修改音频参数实现（滤波器、音量渐变）
- 音频线程独立于 Metal 渲染线程，通过 `AttentionManager` 的 Combine publisher 同步

**CoreHaptics（macOS 限制说明）**

macOS 上 CoreHaptics 仅在支持触觉反馈的 Mac 上可用（MacBook Pro 2021+ 的 Force Touch 轨迹板）。

- `CHHapticEngine` 创建引擎，`CHHapticAdvancedPatternPlayer` 播放参数化触觉模式
- Demo 中使用轻柔的"呼吸感"触觉脉冲，在注意力状态变化时触发
- **必须检测硬件支持**：`CHHapticEngine.capabilitiesForHardware().supportsHaptics`，不支持时静默降级（无触觉，不 crash）
- 注意力从 distracted → focused 时触发一次"入定"触觉；focused → distracted 时触发柔和的"提醒"

**Combine**

数据流的中枢神经：

- `AttentionManager` 通过 `@Published` / `CurrentValueSubject<AttentionState, Never>` 发布注意力状态
- `MetalRenderer`、`AudioEngine`、`HapticEngine` 各自订阅此 publisher
- 使用 `.receive(on:)` 确保各 consumer 在正确线程执行（Metal 在 render 线程，Audio 在 audio render callback）
- 使用 `.debounce(for: .milliseconds(50))` 防止注意力状态抖动导致视觉/音频闪烁

**Accelerate**

Demo 阶段暂不处理真实 EEG 信号，但架构上预留：

- `vDSP_fft_zrip` 用于 FFT 计算
- `vDSP_vsmul` / `vDSP_vadd` 用于信号预处理
- 这些函数仅在 `CalibrationEngine` 中使用，未来替换 `SimulatedAttention` 时激活

**Observation (macOS 14+)**

使用 Swift 5.9 的 `@Observable` 宏替代部分 `ObservableObject`：

- `AppState` 使用 `@Observable`
- 需要与 SwiftUI `@Bindable` / `@Environment` 配合
- **注意**：`@Observable` 的 `@ObservationIgnored` 标记高频更新属性（如 `currentFrameCount`），避免每帧触发 SwiftUI 视图重绘

**GameplayKit**

- `GKPerlinNoise` 生成 3D Perlin 噪声场，作为萤火虫运动的流场
- 噪声种子在 app 启动时固定，保证同一关卡萤火虫运动路径一致（可复现的"自然感"）
- 也可以在 Metal compute shader 中实现 Perlin 噪声（更高效），GKPerlinNoise 仅作为 CPU 端 fallback 或配置工具

---

## 1.3 App 生命周期架构

### 1.3.1 状态机定义

```swift
// ============================================
// Models/AppState.swift
// ============================================

import Observation

/// App 级别的顶层状态
/// 只用于控制导航，不包含高频数据
@Observable
final class AppState {
    var currentScreen: AppScreen = .home
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    
    init() {
        if !hasCompletedOnboarding {
            currentScreen = .onboarding
        }
    }
}

enum AppScreen: Hashable {
    case onboarding
    case home
    case session(LevelID)
}
```

```swift
// ============================================
// Models/SessionPhase.swift
// ============================================

/// 单次会话内的阶段状态机
/// 严格按照箭头方向流转，不允许跳过
enum SessionPhase: Equatable, CaseIterable {
    case calibration      // 校准：用户适应 SSVEP 频率
    case immersion        // 沉浸：引导进入冥想状态
    case training         // 训练：正式注意力训练循环
    case debrief          // 回顾：本次训练数据总结
    
    /// 下一阶段，training 和 debrief 是终态
    var next: SessionPhase? {
        switch self {
        case .calibration:  return .immersion
        case .immersion:    return .training
        case .training:     return .debrief
        case .debrief:      return nil
        }
    }
}
```

```swift
// ============================================
// Models/LevelID.swift
// ============================================

/// 6 个关卡定义
/// 每个关卡有独立的视觉主题、SSVEP 频率、难度参数
enum LevelID: Int, CaseIterable, Identifiable, Hashable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5
    case level6 = 6
    
    var id: Int { rawValue }
    
    /// 关卡显示名称
    var displayName: String {
        switch self {
        case .level1: return "初识星空"
        case .level2: return "萤火低语"
        case .level3: return "星河漫步"
        case .level4: return "深空冥想"
        case .level5: return "量子涟漪"
        case .level6: return "永恒之息"
        }
    }
    
    /// SSVEP 目标频率（Hz）
    var ssvepFrequency: Int {
        switch self {
        case .level1, .level2: return 15
        case .level3, .level4: return 15  // 基础频率始终为 15Hz
        case .level5:       return 20      // 进阶
        case .level6:       return 40      // RIFT / 高级
        }
    }
    
    /// 干扰频率（Hz），制造注意力挑战
    var distractorFrequency: Int? {
        switch self {
        case .level1: return nil       // 无干扰
        case .level2: return 20
        case .level3: return 20
        case .level4: return 20
        case .level5: return 15        // 反向干扰
        case .level6: return 15
        }
    }
    
    /// 训练时长（秒）
    var trainingDuration: TimeInterval {
        switch self {
        case .level1: return 120       // 2 分钟
        case .level2: return 180       // 3 分钟
        case .level3: return 240       // 4 分钟
        case .level4: return 300       // 5 分钟
        case .level5: return 300
        case .level6: return 360       // 6 分钟
        }
    }
    
    /// 校准时长（秒）
    var calibrationDuration: TimeInterval {
        switch self {
        case .level1: return 30
        case .level2: return 20
        case .level3: return 15
        case .level4: return 10
        case .level5: return 15
        case .level6: return 15
        }
    }
    
    /// 视觉粒子密度系数（相对 level1 的倍数）
    var particleDensityMultiplier: Float {
        switch self {
        case .level1: return 1.0
        case .level2: return 1.5
        case .level3: return 2.0
        case .level4: return 2.5
        case .level5: return 3.0
        case .level6: return 3.5
        }
    }
    
    /// 视觉主题色调
    var themeColor: SIMD3<Float> {
        switch self {
        case .level1: return SIMD3<Float>(0.1, 0.3, 0.8)   // 深蓝
        case .level2: return SIMD3<Float>(0.0, 0.6, 0.4)   // 深绿
        case .level3: return SIMD3<Float>(0.4, 0.2, 0.7)   // 暗紫
        case .level4: return SIMD3<Float>(0.7, 0.2, 0.3)   // 暗红
        case .level5: return SIMD3<Float>(0.2, 0.5, 0.7)   // 冰蓝
        case .level6: return SIMD3<Float>(0.9, 0.7, 0.3)   // 金色
        }
    }
    
    /// 是否已解锁
    var isUnlocked: Bool {
        if self == .level1 { return true }
        let previousLevel = LevelID(rawValue: self.rawValue - 1)!
        let previousBest = UserDefaults.standard.double(forKey: "bestScore_level\(previousLevel.rawValue)")
        return previousBest >= 0.6  // 上一关最佳专注度 >= 60% 则解锁
    }
}
```

```swift
// ============================================
// Models/AttentionState.swift
// ============================================

/// 注意力状态，由 AttentionManager 判定
/// 这是驱动所有视觉/音频/触觉反馈的核心信号
enum AttentionState: Equatable, Hashable {
    case focused        // 专注：注意力集中，SSVEP 信号强
    case neutral        // 中性：基线状态
    case distracted     // 分心：注意力偏离，SSVEP 信号弱或消失
    
    /// 用于视觉反馈的归一化值：-1.0（分心）到 +1.0（专注）
    var normalizedValue: Float {
        switch self {
        case .focused:    return  1.0
        case .neutral:    return  0.0
        case .distracted: return -1.0
        }
    }
}
```

```swift
// ============================================
// Models/AttentionSample.swift
// ============================================

/// 单条注意力采样数据
/// SimulatedAttention 每帧（~8ms，即 120fps 的间隔）产生一条
struct AttentionSample {
    let timestamp: TimeInterval          // CACurrentMediaTime()
    let ssvepSNR: Float                  // 信噪比 (dB)，demo 中为模拟值
    let attentionScore: Float            // 0.0 ~ 1.0 归一化注意力分数
    let rawSSVEPAmplitude: Float         // 原始 SSVEP 分量幅度
    let isReliable: Bool                 // 数据是否可靠（信号质量足够）
}
```

### 1.3.2 完整状态流转图

```
App Launch
    │
    ├─ hasCompletedOnboarding == false ──→ OnboardingView
    │                                          │
    │                                    (完成引导)
    │                                          │
    │                                    hasCompletedOnboarding = true
    │                                          │
    └─ hasCompletedOnboarding == true ──→ HomeView
                                               │
                                         (选择关卡)
                                               │
                                    ┌──────────┴──────────┐
                                    │   SessionContainer  │
                                    │                     │
                                    │  ┌───────────────┐  │
                                    │  │ Calibration   │  │
                                    │  │ (适应SSVEP频率) │  │
                                    │  └───────┬───────┘  │
                                    │          │          │
                                    │  ┌───────▼───────┐  │
                                    │  │  Immersion    │  │
                                    │  │ (引导放松)     │  │
                                    │  └───────┬───────┘  │
                                    │          │          │
                                    │  ┌───────▼───────┐  │
                                    │  │   Training    │◄─┼── MetalView 在此阶段运行完整渲染
                                    │  │ (注意力训练)   │  │    AttentionManager 持续采样
                                    │  │               │  │    视觉/音频/触觉实时反馈
                                    │  └───────┬───────┘  │
                                    │          │          │
                                    │  ┌───────▼───────┐  │
                                    │  │   Debrief     │  │
                                    │  │ (回顾总结)     │  │
                                    │  └───────┬───────┘  │
                                    │          │          │
                                    └──────────┴──────────┘
                                               │
                                         (返回 Home)
```

### 1.3.3 App 入口代码

```swift
// ============================================
// App/StarfieldFirefliesApp.swift
// ============================================

import SwiftUI

@main
struct StarfieldFirefliesApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)       // 强制深色模式
                .onAppear {
                    configureWindowForProMotion()
                }
        }
        .windowStyle(.hiddenTitleBar)               // 隐藏标题栏，全屏沉浸感
        .windowResizability(.contentSize)           // 固定窗口大小（不随用户拖拽缩放）
        .defaultSize(width: 1024, height: 768)      // 默认窗口尺寸
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Group {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView()
            case .home:
                HomeView()
            case .session(let levelID):
                SessionContainerView(levelID: levelID)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: appState.currentScreen)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

/// 配置 NSWindow 支持 ProMotion
func configureWindowForProMotion() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        guard let window = NSApplication.shared.windows.first else { return }
        
        // 全屏选项（可选，demo 中也可以不全屏）
        // window.toggleFullScreen(nil)
        
        // 设置窗口背景为不透明黑色（Metal 全屏渲染时避免闪白）
        window.backgroundColor = .black
        window.isOpaque = true
        
        // 禁止用户调整窗口大小（固定比例）
        window.styleMask.remove(.resizable)
    }
}
```

---

## 1.4 数据流架构

### 1.4.1 核心数据流图

```
┌─────────────────────────────────────────────────────────────┐
│                        SimulatedAttention                      │
│  (生产者：模拟注意力数据，未来替换为真实 EEG 硬件数据源)        │
│                                                               │
│  每 ~8ms 生成一条 AttentionSample                             │
│  模拟注意力波动：正弦波 + 随机噪声 + 状态跳变                   │
└──────────────────────┬──────────────────────────────────────┘
                       │ AttentionSample
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                      AttentionManager                         │
│                                                               │
│  输入：AttentionSample 流                                     │
│  处理：滑动窗口平滑 + 阈值判定 → AttentionState               │
│  输出：CurrentValueSubject<AttentionState, Never>             │
│                                                               │
│  判定逻辑：                                                   │
│    attentionScore > 0.7 (持续 >500ms) → .focused              │
│    attentionScore < 0.3 (持续 >500ms) → .distracted           │
│    其他 → .neutral                                           │
└────┬────────────────────┬────────────────────┬───────────────┘
     │                    │                    │
     │ Combine pipeline   │ Combine pipeline   │ Combine pipeline
     │ .receive(on: ...)  │ .receive(on: ...)  │ .receive(on: ...)
     ▼                    ▼                    ▼
┌─────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ MetalRenderer│  │   AudioEngine   │  │  HapticEngine   │
│              │  │                 │  │                 │
│ 渲染线程     │  │ 音频 render     │  │ 主线程调用      │
│              │  │ callback 线程   │  │ CHHapticEngine  │
│ 注意力→视觉: │  │                 │  │                 │
│ 星空亮度变化 │  │ 注意力→音频:    │  │ 状态变化→触觉:  │
│ 萤火虫行为   │  │ binaural 强度   │  │ 专注脉冲/分心   │
│ SSVEP叠加   │  │ 环境音滤波      │  │ 提醒            │
│ Bloom强度   │  │ 反馈音效触发    │  │                 │
└─────────────┘  └─────────────────┘  └─────────────────┘
```

### 1.4.2 Protocol 定义

```swift
// ============================================
// Services/Attention/AttentionProvider.swift
// ============================================

import Foundation
import Combine

/// 注意力数据源的抽象协议
/// Demo 中由 SimulatedAttention 实现
/// 未来替换为真实 EEG 硬件数据源时，只需实现此 protocol
protocol AttentionProvider {
    
    /// 注意力数据流
    /// 生产者以 ~120Hz（每帧一次）的频率发送 AttentionSample
    var sampleStream: AnyPublisher<AttentionSample, Never> { get }
    
    /// 开始采样
    func startSampling() -> AnyCancellable
    
    /// 停止采样
    func stopSampling()
    
    /// 当前 SSVEP 目标频率（Hz），由 SessionController 设置
    var targetFrequency: Int { get set }
    
    /// 当前干扰频率（Hz），nil 表示无干扰
    var distractorFrequency: Int? { get set }
}
```

```swift
// ============================================
// Services/Attention/AttentionManager.swift
// ============================================

import Foundation
import Combine

/// 注意力状态管理器
/// 接收原始 AttentionSample 流，输出判定后的 AttentionState
@Observable
final class AttentionManager {
    
    // MARK: - Published Output
    
    /// 注意力状态变化流，供 UI / Audio / Haptics 订阅
    private let _attentionStateSubject = CurrentValueSubject<AttentionState, Never>(.neutral)
    var attentionStatePublisher: AnyPublisher<AttentionState, Never> {
        _attentionStateSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// 当前注意力状态（供 MetalRenderer 直接读取，避免 Publisher 延迟）
    var currentAttentionState: AttentionState {
        _attentionStateSubject.value
    }
    
    /// 注意力分数（0.0~1.0），用于视觉平滑插值
    var currentAttentionScore: Float = 0.0
    
    /// 原始 SSVEP 信噪比，用于调试 overlay
    @ObservationIgnored var currentSNR: Float = 0.0
    
    // MARK: - Configuration
    
    /// 状态判定阈值
    var focusedThreshold: Float = 0.7
    var distractedThreshold: Float = 0.3
    
    /// 状态确认延迟（防止抖动）
    var stateConfirmDelay: TimeInterval = 0.5  // 500ms
    
    // MARK: - Internal State
    
    private var cancellables = Set<AnyCancellable>()
    private var pendingState: AttentionState?
    private var stateChangeTimer: Timer?
    private var scoreHistory: [Float] = []
    private let scoreHistoryWindowSize = 15  // ~125ms 的滑动窗口 @ 120fps
    
    // MARK: - Input
    
    private let sampleSubject = PassthroughSubject<AttentionSample, Never>()
    
    /// 外部注入 AttentionSample
    func ingest(_ sample: AttentionSample) {
        sampleSubject.send(sample)
    }
    
    // MARK: - Lifecycle
    
    init(provider: AttentionProvider) {
        setupPipeline(provider: provider)
    }
    
    deinit {
        stateChangeTimer?.invalidate()
    }
    
    private func setupPipeline(provider: AttentionProvider) {
        // 1. 从 provider 获取原始数据流
        let rawStream = provider.sampleStream
        
        // 2. 滑动窗口平滑
        rawStream
            .map(\.attentionScore)
            .buffer(size: scoreHistoryWindowSize, prefetch: .byRequest)
            .compactMap { scores -> Float? in
                guard scores.count == self.scoreHistoryWindowSize else { return nil }
                // 加权移动平均（近期权重更高）
                var weightedSum: Float = 0
                var weightTotal: Float = 0
                for (i, score) in scores.enumerated() {
                    let weight = Float(i + 1) / Float(scores.count)
                    weightedSum += score * weight
                    weightTotal += weight
                }
                return weightedSum / weightTotal
            }
            .sink { [weak self] smoothedScore in
                self?.updateState(smoothedScore: smoothedScore)
            }
            .store(in: &cancellables)
    }
    
    private func updateState(smoothedScore: Float) {
        currentAttentionScore = smoothedScore
        
        let newState: AttentionState
        if smoothedScore >= focusedThreshold {
            newState = .focused
        } else if smoothedScore <= distractedThreshold {
            newState = .distracted
        } else {
            newState = .neutral
        }
        
        // 延迟确认机制：只有持续 stateConfirmDelay 才真正切换
        if newState != currentAttentionState {
            if pendingState != newState {
                pendingState = newState
                stateChangeTimer?.invalidate()
                stateChangeTimer = Timer.scheduledTimer(
                    withTimeInterval: stateConfirmDelay,
                    repeats: false
                ) { [weak self] _ in
                    guard let self, let pending = self.pendingState else { return }
                    self._attentionStateSubject.send(pending)
                    self.pendingState = nil
                }
            }
            // 如果 pendingState 和新检测到的状态一致，保持 timer（持续确认中）
        } else {
            // 状态一致，取消 pending
            pendingState = nil
            stateChangeTimer?.invalidate()
        }
    }
    
    /// 重置状态（会话开始时调用）
    func reset() {
        _attentionStateSubject.send(.neutral)
        currentAttentionScore = 0.0
        pendingState = nil
        stateChangeTimer?.invalidate()
        scoreHistory.removeAll()
    }
}
```

### 1.4.3 Feedback 接收端（Metal / Audio / Haptics 订阅方式）

```swift
// ============================================
// MetalRenderer 中的订阅示例（在 SessionController 中配置）
// ============================================

// SessionController.swift 中的连接逻辑

func connectAttentionFeedback(
    attentionManager: AttentionManager,
    metalRenderer: MetalRenderer,
    audioEngine: AudioEngine,
    hapticEngine: HapticEngine
) {
    // Metal：直接读取属性（最快，无 Publisher 开销）
    // MetalRenderer 在每帧 draw(in:) 中直接读取
    // attentionManager.currentAttentionState
    // attentionManager.currentAttentionScore
    // 这避免了 Combine 的调度延迟
    
    // Audio：通过 Publisher，debounce 防止频繁参数变化
    attentionManager.attentionStatePublisher
        .removeDuplicates()
        .debounce(for: .milliseconds(100))      // 音频不需要 120Hz 更新率
        .receive(on: audioEngine.audioQueue)     // 切到音频线程
        .sink { [weak audioEngine] state in
            audioEngine?.updateForAttention(state: state)
        }
        .store(in: &cancellables)
    
    // Haptics：通过 Publisher，只响应状态变化（不是每帧）
    attentionManager.attentionStatePublisher
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink { [weak hapticEngine] state in
            hapticEngine?.playFeedback(for: state)
        }
        .store(in: &cancellables)
}
```

> **为什么 Metal 不走 Combine**: Metal 渲染循环本身就是 120Hz 的 `draw(in:)` 调用。在每帧渲染时直接读取 `attentionManager.currentAttentionScore`（一个 `Float` 属性）即可，延迟为 0。Combine 的 `receive(on:)` 调度至少引入 1 帧延迟，且增加不必要的对象开销。

### 1.4.4 SimulatedAttention 实现

```swift
// ============================================
// Services/Attention/SimulatedAttention.swift
// ============================================

import Foundation
import Combine
import GameplayKit

/// 模拟注意力数据生成器
/// 用于 demo，未来替换为真实 EEG 硬件数据源
final class SimulatedAttention: AttentionProvider {
    
    // MARK: - AttentionProvider
    
    var targetFrequency: Int = 15
    var distractorFrequency: Int? = nil
    
    private let _sampleSubject = PassthroughSubject<AttentionSample, Never>()
    var sampleStream: AnyPublisher<AttentionSample, Never> {
        _sampleSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Simulation Parameters
    
    /// 模拟难度系数：0.0（一直专注）到 1.0（频繁分心）
    /// 由 LevelID 决定
    var difficulty: Float = 0.3
    
    /// 模拟"自然的"注意力波动周期（秒）
    private let focusCyclePeriod: TimeInterval = 15.0
    private let distractionCyclePeriod: TimeInterval = 8.0
    
    // MARK: - Internal State
    
    private var timer: Timer?
    private let random = GKMersenneTwisterRandomSource(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    private var simulationStartTime: TimeInterval = 0
    private var currentBaseScore: Float = 0.5
    private var cancellable: AnyCancellable?
    
    // MARK: - Simulation Logic
    
    func startSampling() -> AnyCancellable {
        simulationStartTime = CACurrentMediaTime()
        
        // 以 ~120Hz 生成样本（与 MTKView 渲染帧率同步）
        // 注意：实际中由 MetalRenderer.draw(in:) 调用 generateSample() 更精确
        // 这里用 Timer 作为 fallback
        let timerPublisher = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.generateSample()
            }
        
        return timerPublisher
    }
    
    func stopSampling() {
        timer?.invalidate()
        timer = nil
    }
    
    /// 由 MetalRenderer 每帧调用，确保与渲染帧精确同步
    func generateSample() {
        let now = CACurrentMediaTime()
        let elapsed = now - simulationStartTime
        
        // 基础注意力分数：正弦波模拟自然波动
        let focusWave = sin(Float(elapsed / focusCyclePeriod) * .pi * 2)
        let distractionWave = sin(Float(elapsed / distractionCyclePeriod) * .pi * 2) * difficulty
        
        // 基础分数 = 0.5 + 正弦波动
        currentBaseScore = 0.5 + focusWave * 0.25 - distractionWave * 0.15
        
        // 添加随机噪声
        let noise = Float.random(in: -0.05 ... 0.05)
        var score = (currentBaseScore + noise).clamped(to: 0.0 ... 1.0)
        
        // 模拟偶发的"深度分心"事件（突然掉到 0.1~0.2）
        let distractionEvent = sin(Float(elapsed / 23.0) * .pi * 2)
        if distractionEvent > 0.95 && difficulty > 0.4 {
            score = Float.random(in: 0.1 ... 0.2)
        }
        
        // 模拟"深度专注"事件（突然升到 0.9~1.0）
        let focusEvent = sin(Float(elapsed / 37.0) * .pi * 2)
        if focusEvent > 0.9 && difficulty < 0.6 {
            score = Float.random(in: 0.85 ... 0.98)
        }
        
        // 模拟 SSVEP 信噪比（与注意力分数正相关 + 额外噪声）
        let snr = score * 15.0 + Float.random(in: -2.0 ... 2.0)
        
        let sample = AttentionSample(
            timestamp: now,
            ssvepSNR: snr,
            attentionScore: score,
            rawSSVEPAmplitude: score * 0.8 + Float.random(in: -0.05 ... 0.05),
            isReliable: score > 0.2  // 低分数时标记为不可靠
        )
        
        _sampleSubject.send(sample)
    }
}
```

```swift
// Float clamp 扩展（放在 Utilities/Extensions/Float+Helpers.swift）
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
```

---

## 1.5 Build & Run 指令

### 1.5.1 从零创建项目的精确步骤

**Step 1: 创建 Xcode 项目**

```
1. 打开 Xcode 15+
2. File → New → Project
3. 选择 macOS → App → Next
4. 填写：
   - Product Name: StarfieldFireflies
   - Team: (选择你的开发团队)
   - Organization Identifier: com.yourorg.ssvep
   - Interface: SwiftUI
   - Language: Swift
   - Storage: None (不用 Core Data / CloudKit)
5. Next → 选择保存位置 → Create
```

**Step 2: 配置 Deployment Target**

```
1. 点击左侧 Navigator 中的项目根节点 (StarfieldFireflies)
2. 选择 Target "StarfieldFireflies"
3. General → Deployment Info → Minimum Deployments:
   - macOS: 14.0 (Sonoma)
4. 关闭 iPad / iPhone 支持（纯 macOS app）
```

**Step 3: 配置 Window 设置**

```
1. Target → General → Deployment Info:
   - App Category: Utilities 或 Utilities (demo)
2. Target → Info:
   - Application Scene Manifest → Configuration → Application → 
     Disable "Enable Multiple Windows"（单窗口 app）
```

**Step 4: 配置 Entitlements（如需全屏）**

```
1. File → New → File → Property List
2. 命名为 StarfieldFireflies.entitlements
3. Target → Signing & Capabilities → + Capability
4. 添加：
   - App Sandbox → 勾选 "Outgoing Network Connections"（如果需要网络）
   - Hardware Access → 勾选需要的权限
5. Build Settings → Code Signing Entitlements → 设置路径
```

> **注意**: Demo 阶段如果只是本地运行，不需要任何 entitlements。CoreHaptics 不需要特殊权限。

**Step 5: 创建文件夹结构**

在 Xcode 中按以下顺序创建 group：

```
1. 右键项目 → New Group → App
2. 右键项目 → New Group → Models
3. 右键项目 → New Group → Services
   - 在 Services 下创建子 group: Attention, Audio, Haptics, Session
4. 右键项目 → New Group → Rendering
   - 在 Rendering 下创建子 group: Metal, SwiftUI
   - 在 Metal 下创建子 group: Shaders, Buffers, Pipelines
5. 右键项目 → New Group → Views
   - 在 Views 下创建子 group: Home, Session, Onboarding
6. 右键项目 → New Group → Utilities
   - 在 Utilities 下创建子 group: Extensions
7. 右键项目 → New Group → Resources
   - 在 Resources 下创建子 group: Audio
```

**Step 6: 添加 Metal Shader 文件**

```
1. 右键 Rendering/Metal/Shaders → New File
2. 选择 Metal → Metal File → Next
3. 命名为 Shared.metal → Create
4. 重复上述步骤创建：
   - Starfield.metal
   - Firefly.metal
   - SSVEPStimulus.metal
   - PostProcess.metal
   - AttentionVisual.metal
```

**重要**: 确保 Metal 文件被添加到 Target 的 "Compile Sources" 中。Xcode 通常自动处理，但如果 shader 不生效，检查 Target → Build Phases → Compile Sources 中是否包含所有 `.metal` 文件。

**Step 7: 配置 MTKView 支持 120Hz ProMotion**

```swift
// ============================================
// Utilities/Extensions/MTKView+ProMotion.swift
// ============================================

import MetalKit
import QuartzCore

extension MTKView {
    
    /// 配置 MTKView 以支持 ProMotion 120Hz
    func configureForProMotion() {
        // 1. 设置首选帧率
        self.preferredFramesPerSecond = 120
        
        // 2. 启用 VSync（与显示器刷新同步）
        // MTKView 默认就是 VSync 的，但显式确认
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        
        // 3. 颜色格式：HDR 支持时使用 bgr10a2，否则 bgra8unsorm
        if self.device?.supportsBGR10A2Unorm == true {
            self.colorPixelFormat = .bgr10a2Unorm
        } else {
            self.colorPixelFormat = .bgra8Unorm
        }
        
        // 4. 设置 sample count（抗锯齿）
        // 星空场景用 4x MSAA 足够，太高影响性能
        self.sampleCount = 4
        
        // 5. 深度缓冲（如果需要粒子深度排序）
        self.depthStencilPixelFormat = .depth32Float
        
        // 6. 确保 drawable 大小正确
        self.drawableSize = self.bounds.size * NSScreen.main?.backingScaleFactor ?? 2.0
        
        // 7. 设置 CADisplayLink preferredFrameRateRange（macOS 14+ API）
        if #available(macOS 14.0, *) {
            // 通过 NSView 的 layer 来设置
            if let layer = self.layer {
                // CATiledLayer 或 CAMetalLayer
                // MTKView 内部使用 CAMetalLayer
                // preferredFrameRateRange 在 NSView 级别设置
            }
        }
    }
}
```

```swift
// ============================================
// Rendering/SwiftUI/MetalView.swift
// ============================================

import SwiftUI
import MetalKit

/// 将 MTKView 嵌入 SwiftUI 视图层级
struct MetalView: NSViewRepresentable {
    
    let renderer: MetalRenderer
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        // 设置 Metal device
        mtkView.device = MetalEngine.shared.device
        
        // 设置 delegate
        mtkView.delegate = context.coordinator
        
        // 配置 ProMotion 120Hz
        mtkView.configureForProMotion()
        
        // 背景色设为纯黑
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // 允许 framebuffer only（性能优化：不需要 CPU 读取 GPU 绘制内容）
        mtkView.framebufferOnly = true
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // MetalRenderer 的状态更新在这里处理
        // 注意：不要在这里做重活，SwiftUI 可能频繁调用
    }
    
    func makeCoordinator() -> RendererCoordinator {
        RendererCoordinator(renderer: renderer)
    }
    
    class RendererCoordinator: NSObject, MTKViewDelegate {
        let renderer: MetalRenderer
        
        init(renderer: MetalRenderer) {
            self.renderer = renderer
        }
        
        func draw(in view: MTKView) {
            renderer.draw(in: view)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.drawableSizeWillChange(size: size)
        }
    }
}
```

**Step 8: 验证 120Hz 生效**

```swift
// ============================================
// Utilities/PerformanceMonitor.swift
// ============================================

import Foundation
import QuartzCore

/// 实时监控渲染性能
final class PerformanceMonitor {
    
    @ObservationIgnored var currentFPS: Int = 0
    @ObservationIgnored var frameTimeMS: Double = 0
    
    private var frameTimestamps: [CFTimeInterval] = []
    private let maxFrameHistory = 120
    private var lastDrawTime: CFTimeInterval = 0
    
    func recordFrame() {
        let now = CACurrentMediaTime()
        
        if lastDrawTime > 0 {
            frameTimeMS = (now - lastDrawTime) * 1000.0
        }
        lastDrawTime = now
        
        frameTimestamps.append(now)
        
        // 保留最近 120 帧
        if frameTimestamps.count > maxFrameHistory {
            frameTimestamps.removeFirst()
        }
        
        // 计算 FPS
        if frameTimestamps.count >= 2 {
            let elapsed = frameTimestamps.last! - frameTimestamps.first!
            if elapsed > 0 {
                currentFPS = Int(Double(frameTimestamps.count - 1) / elapsed)
            }
        }
    }
    
    /// 检查是否达到 120 FPS
    var isRunningAt120fps: Bool {
        return currentFPS >= 115  // 允许 5fps 容差
    }
}
```

> **运行后检查**: 在 Xcode Debug Navigator 中观察 Metal frame rate。如果显示 ~60fps 而非 ~120fps，检查：
> 1. 确认 MacBook Pro 是 2021 或更新型号（ProMotion 硬件支持）
> 2. 确认 macOS 14.0+
> 3. 确认系统设置 → 显示器 → 刷新率 设为 "ProMotion"（不是节能模式）
> 4. 确认 `MTKView.preferredFramesPerSecond = 120`

**Step 9: 确认项目编译通过**

```
1. Cmd+B 编译
2. 如果报 "Metal shader compilation failed"，检查 .metal 文件语法
3. 如果报 linker error，确认 framework 已自动链接
4. Cmd+R 运行，应该看到黑色窗口（此时还没有渲染内容）
```

---

## 1.6 关键工程约束

### 1.6.1 120 FPS 锁定（硬性要求）

**约束**: 渲染循环必须稳定运行在 120fps，这是 SSVEP 刺激正确性的基础。

```swift
// ============================================
// Rendering/Metal/MetalEngine.swift
// ============================================

import Metal

/// Metal 设备与命令队列的单例管理器
final class MetalEngine {
    
    static let shared = MetalEngine()
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    private init() {
        // 优先选择独占 GPU
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        
        guard let queue = device.makeCommandQueue(maxCommandBufferCount: 3) else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue
        
        print("[MetalEngine] Device: \(device.name)")
        print("[MetalEngine] Max threads per group: \(device.maxThreadsPerThreadgroup)")
        print("[MetalEngine] Supports BGR10A2: \(device.supportsBGR10A2Unorm)")
    }
}
```

```swift
// MetalRenderer 中的帧率控制

// ============================================
// Rendering/Metal/MetalRenderer.swift
// ============================================

import MetalKit

final class MetalRenderer: NSObject {
    
    private let device: MetalEngine
    private let performanceMonitor = PerformanceMonitor()
    
    /// 帧计数器 — 这是 SSVEP 刺激的唯一时钟
    /// 绝对不能使用 CACurrentMediaTime() 或 Date() 来决定刺激状态
    @ObservationIgnored private(set) var frameCount: UInt64 = 0
    
    /// SSVEP 刺激的当前显示状态（亮/暗）
    @ObservationIgnored var ssvepStimulusActive: Bool = false
    
    /// 当前 SSVEP 频率（由 SessionController 设置）
    var ssvepFrequency: Int = 15
    
    // ... 其他属性 ...
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        let commandBuffer = device.commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Frame \(frameCount)"
        
        // ========================================
        // 1. 更新帧计数器
        // ========================================
        frameCount &+= 1
        
        // ========================================
        // 2. 计算 SSVEP 刺激状态
        //    核心公式：frameCount % (120 / frequency) == 0 → toggle
        //    120 是固定帧率，frequency 是 SSVEP 目标频率
        //    15Hz → 每 8 帧切换一次 (120/15=8)
        //    20Hz → 每 6 帧切换一次 (120/20=6)
        //    40Hz → 每 3 帧切换一次 (120/40=3)
        // ========================================
        let framesPerCycle = 120 / ssvepFrequency
        if frameCount % UInt64(framesPerCycle) == 0 {
            ssvepStimulusActive.toggle()
        }
        
        // ========================================
        // 3. 执行 Metal 渲染命令
        // ========================================
        // ... (具体渲染逻辑在 Section 2 中定义)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // ========================================
        // 4. 性能监控
        // ========================================
        performanceMonitor.recordFrame()
        
        // 每 120 帧（约 1 秒）检查一次帧率
        if frameCount % 120 == 0 {
            if !performanceMonitor.isRunningAt120fps {
                print("[MetalRenderer] ⚠️ FPS dropped to \(performanceMonitor.currentFPS)")
                // TODO: 降低粒子数量，触发 thermal mitigation
            }
        }
    }
}
```

### 1.6.2 SSVEP 帧计数（硬性要求）

**约束**: SSVEP 刺激的亮/暗切换必须严格基于帧计数，禁止使用 wall-clock time。

**原因**: `CACurrentMediaTime()` 的精度虽然很高，但存在系统调度抖动。如果 app 在某一帧被操作系统挂起（即使只延迟 1ms），wall-clock 计算会导致刺激周期偏移，累积误差会影响 SSVEP 诱发效果。帧计数器与显示器刷新严格同步，不存在累积误差。

```swift
// ============================================
// Utilities/FrameCounter.swift
// ============================================

import Foundation

/// 严格帧计数器
/// 用于 SSVEP 刺激时序控制
///
/// 设计原则：
/// 1. 仅递增，不回退，不跳跃
/// 2. 每帧恰好递增 1
/// 3. 与 MTKView draw(in:) 调用 1:1 绑定
struct FrameCounter {
    
    private(set) var count: UInt64 = 0
    
    /// 目标 SSVEP 频率
    let targetFPS: Int = 120
    
    mutating func increment() {
        count &+= 1
    }
    
    /// 给定 SSVEP 频率，当前帧是否应该切换刺激状态
    /// - Parameter frequency: SSVEP 频率 (Hz)
    /// - Returns: true 表示应该 toggle
    func shouldToggleStimulus(frequency: Int) -> Bool {
        let framesPerHalfCycle = UInt64(targetFPS / frequency)
        return count % framesPerHalfCycle == 0
    }
    
    /// 当前刺激状态（基于帧计数）
    /// - Parameter frequency: SSVEP 频率
    /// - Returns: true = 亮, false = 暗
    func stimulusState(frequency: Int) -> Bool {
        let framesPerFullCycle = UInt64(2 * targetFPS / frequency)
        return (count / framesPerFullCycle) % 2 == 0
    }
    
    /// 重置（新会话开始时调用）
    mutating func reset() {
        count = 0
    }
}
```

### 1.6.3 音视频同步（硬性要求）

**约束**: 从注意力状态变化到视觉反馈和音频反馈的延迟都必须 < 100ms。

**延迟预算分解**:

| 环节 | 预期延迟 | 说明 |
|---|---|---|
| SimulatedAttention 生成 | < 0.1ms | CPU 内存操作 |
| AttentionManager 判定 | < 1ms | 滑动窗口计算 |
| MetalRenderer 读取状态 | 0ms | 直接读属性，同帧生效 |
| Metal 渲染完成到屏幕显示 | 1 帧 ≈ 8.3ms | 120Hz 显示器 |
| AudioEngine 参数更新 | < 5ms | AVAudioEngine 内部延迟 |
| 音频输出缓冲区 | 1~2 个 buffer ≈ 5~10ms | 256 samples @ 48kHz |
| **总延迟（视觉）** | **< 10ms** | 同帧渲染 |
| **总延迟（音频）** | **< 20ms** | |

**关键实现**: MetalRenderer 在每帧 `draw(in:)` 中直接读取 `attentionManager.currentAttentionScore`（一个 Float 属性），不经过任何中间层。这保证了视觉反馈的延迟为 0（同帧生效）。

### 1.6.4 主线程不阻塞（硬性要求）

**约束**: 所有计算密集型操作必须在非主线程执行。

**线程分配**:

| 操作 | 线程 | 说明 |
|---|---|---|
| SwiftUI 视图更新 | Main | 必须在主线程，但保持轻量 |
| Metal draw(in:) | Metal render thread | MTKView 自动管理 |
| Metal compute shader | GPU | 粒子物理模拟 |
| Audio render callback | Audio render thread | AVAudioEngine 自动管理 |
| AttentionManager 判定 | AttentionManager 内部队列 | 通过 Combine 调度 |
| SimulatedAttention 生成 | Main 或 Background | Timer 回调，计算量极小 |
| UserDefaults 读写 | Main | 仅在会话开始/结束时，频率极低 |
| CoreHaptics 播放 | Main (API 调用) | 实际振动由系统管理 |

**SwiftUI 视图优化原则**:

```swift
// ❌ 错误做法：高频属性触发视图重绘
@Observable
final class BadExample {
    var frameCount: UInt64 = 0  // 120fps 变化 → SwiftUI 每帧重绘 → 卡顿
}

// ✅ 正确做法：高频属性标记为 @ObservationIgnored
@Observable
final class GoodExample {
    @ObservationIgnored var frameCount: UInt64 = 0  // SwiftUI 不追踪此变化
    var sessionPhase: SessionPhase = .training       // 低频变化，正常追踪
}
```

### 1.6.5 内存预算（硬性要求）

**约束**: Demo 阶段峰值内存 < 200MB。

**内存分配预估**:

| 组件 | 预估内存 | 说明 |
|---|---|---|
| Metal 粒子 buffer | ~20MB | 10 万粒子 × 128 bytes/粒子 |
| Metal 纹理 | ~30MB | bloom 中间纹理 + 环境贴图 |
| Metal pipeline states | ~5MB | ~20 个 pipeline state |
| Audio buffer | ~5MB | AVAudioEngine 内部缓冲 |
| SwiftUI 视图层级 | ~10MB | 轻量级 overlay |
| 系统开销 | ~50MB | Metal driver, runtime |
| **总计** | **~120MB** | 在 200MB 预算内 |

**内存监控**:

```swift
// 在 SessionController 中周期性检查
func checkMemoryUsage() {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
        }
    }
    
    if result == KERN_SUCCESS {
        let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
        if usedMB > 180.0 {
            print("[Memory] ⚠️ High memory usage: \(String(format: "%.1f", usedMB)) MB")
            // 触发内存优化：减少粒子数量，释放未使用的纹理
        }
    }
}
```

### 1.6.6 热管理（硬性要求）

**约束**: 监控设备热状态，过热时自动降低视觉复杂度。

```swift
// ============================================
// Utilities/ThermalMonitor.swift
// ============================================

import Foundation
import Combine

/// 设备热状态监控器
/// macOS 上通过 NSProcessInfo.thermalState 获取
final class ThermalMonitor {
    
    enum ThermalLevel {
        case nominal      // 正常：全特效
        case fair          // 轻度发热：减少 25% 粒子
        case serious       // 明显发热：减少 50% 粒子，关闭 bloom
        case critical      // 过热：最低特效，仅保留核心渲染
    }
    
    let thermalLevelPublisher = CurrentValueSubject<ThermalLevel, Never>(.nominal)
    
    private var timer: Timer?
    
    func startMonitoring() {
        // 每 5 秒检查一次热状态
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkThermalState()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
    }
    
    private func checkThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        
        let level: ThermalLevel
        switch state {
        case .nominal:
            level = .nominal
        case .fair:
            level = .fair
        case .serious:
            level = .serious
        @unknown default:
            level = .serious  // 保守降级
        }
        
        let previous = thermalLevelPublisher.value
        thermalLevelPublisher.send(level)
        
        if level != previous {
            print("[ThermalMonitor] State changed: \(previous) → \(level)")
        }
    }
    
    /// 根据热状态返回粒子数量缩放因子
    var particleScaleFactor: Float {
        switch thermalLevelPublisher.value {
        case .nominal:  return 1.0
        case .fair:     return 0.75
        case .serious:  return 0.5
        case .critical: return 0.25
        }
    }
    
    /// 根据热状态返回是否应该启用 bloom
    var shouldEnableBloom: Bool {
        switch thermalLevelPublisher.value {
        case .nominal, .fair: return true
        case .serious, .critical: return false
        }
    }
}
```

### 1.6.7 SSVEP 刺激视觉约束（硬性要求）

**约束**: SSVEP 刺激是全屏亮/暗闪烁，必须满足以下条件：

1. **对比度**: 亮态和暗态的亮度差必须足够大（Michelson 对比度 > 0.8）
2. **占空比**: 50%（亮/暗各占半个周期）
3. **叠加方式**: SSVEP 刺激作为 overlay 叠加在星空场景上，不能破坏场景的连续性
4. **渲染方式**: 使用 Metal fragment shader 中基于 `frameCount` uniform 的 alpha 混合，不创建额外的 view 层

```metal
// SSVEPStimulus.metal 中的核心逻辑示意

// Vertex shader 传递 frameCount 到 fragment shader
// Fragment shader 中：

fragment float4 ssvepStimulusFragment(
    VertexOut in [[stage_in]],
    constant FrameUniforms& uniforms [[buffer(0)]]
) {
    // 1. 先渲染正常的场景像素
    float4 sceneColor = /* ... 正常场景渲染 ... */;
    
    // 2. 计算 SSVEP 刺激 alpha
    // uniforms.ssvepFrequency = 15 (或其他频率)
    // uniforms.frameCount 由 CPU 每帧递增
    uint framesPerHalfCycle = 120 / uniforms.ssvepFrequency;
    uint halfCyclePosition = uniforms.frameCount % framesPerHalfCycle;
    
    // 使用平滑过渡而非硬切换，减少视觉闪烁不适感
    // 但过渡时间不能超过周期的 10%，否则影响 SSVEP 诱发效果
    float transitionWidth = float(framesPerHalfCycle) * 0.1;
    float ssvepAlpha;
    
    if (halfCyclePosition < float(framesPerHalfCycle) * 0.5) {
        // 亮态：前半周期
        ssvepAlpha = smoothstep(0, transitionWidth, float(halfCyclePosition));
    } else {
        // 暗态：后半周期
        ssvepAlpha = 1.0 - smoothstep(0, transitionWidth,
            float(halfCyclePosition) - float(framesPerHalfCycle) * 0.5);
    }
    
    // 3. SSVEP 刺激叠加（additive blending，增强亮态）
    float3 stimulusColor = float3(0.1, 0.1, 0.15); // 极微弱的白色偏蓝叠加
    sceneColor.rgb += stimulusColor * ssvepAlpha * uniforms.ssvepIntensity;
    
    return sceneColor;
}
```

> **注意**: 上面的 `smoothstep` 过渡仅占周期的 10%。这是为了减少视觉上的硬切换不适感，同时保持 SSVEP 诱发效果。如果 10% 的过渡影响诱发效果（在真实 EEG 测试中确认），则改为硬切换（`ssvepAlpha = halfCyclePosition < framesPerHalfCycle/2 ? 1.0 : 0.0`）。

### 1.6.8 关卡解锁数据持久化（轻量要求）

```swift
// ============================================
// Models/UserProfile.swift
// ============================================

import Foundation

/// 用户进度数据（UserDefaults 持久化）
/// Demo 阶段不需要 Core Data，UserDefaults 足够
final class UserProfile {
    
    private static let bestScorePrefix = "bestScore_level"
    private static let completionCountPrefix = "completionCount_level"
    private static let totalTrainingTimeKey = "totalTrainingTime"
    
    /// 记录关卡最佳专注度分数
    static func saveBestScore(levelID: LevelID, score: Float) {
        let key = "\(bestScorePrefix)\(levelID.rawValue)"
        let previous = UserDefaults.standard.float(forKey: key)
        if score > previous {
            UserDefaults.standard.set(score, forKey: key)
        }
    }
    
    /// 获取关卡最佳分数
    static func getBestScore(levelID: LevelID) -> Float {
        let key = "\(bestScorePrefix)\(levelID.rawValue)"
        return UserDefaults.standard.float(forKey: key)
    }
    
    /// 记录关卡完成次数
    static func incrementCompletionCount(levelID: LevelID) {
        let key = "\(completionCountPrefix)\(levelID.rawValue)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }
    
    /// 累计训练时间
    static func addTrainingTime(_ seconds: TimeInterval) {
        let current = UserDefaults.standard.double(forKey: totalTrainingTimeKey)
        UserDefaults.standard.set(current + seconds, forKey: totalTrainingTimeKey)
    }
    
    /// 获取总训练时间（格式化为字符串）
    static func getTotalTrainingTimeString() -> String {
        let total = UserDefaults.standard.double(forKey: totalTrainingTimeKey)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }
}
```

### 1.6.9 完整的 SessionController（连接所有组件）

```swift
// ============================================
// Services/Session/SessionController.swift
// ============================================

import Foundation
import Combine

/// 会话生命周期控制器
/// 负责管理一次完整的训练会话，协调所有子系统
@Observable
final class SessionController {
    
    // MARK: - State
    
    var currentPhase: SessionPhase = .calibration {
        didSet {
            onPhaseChanged()
        }
    }
    
    var levelID: LevelID
    var remainingTime: TimeInterval = 0
    var phaseStartTime: Date = Date()
    
    @ObservationIgnored var isSessionActive: Bool = false
    
    // MARK: - Subsystems
    
    let attentionManager: AttentionManager
    let metalRenderer: MetalRenderer
    let audioEngine: AudioEngine
    let hapticEngine: HapticEngine
    let thermalMonitor: ThermalMonitor
    
    // MARK: - Private
    
    private var phaseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let simulatedAttention: SimulatedAttention
    
    // MARK: - Stats
    
    @ObservationIgnored var focusDuration: TimeInterval = 0
    @ObservationIgnored var neutralDuration: TimeInterval = 0
    @ObservationIgnored var distractedDuration: TimeInterval = 0
    private var stateChangeTimestamp: Date = Date()
    
    // MARK: - Init
    
    init(levelID: LevelID) {
        self.levelID = levelID
        
        // 创建模拟注意力源
        let sim = SimulatedAttention()
        sim.difficulty = levelID == .level1 ? 0.2 : 0.4
        sim.targetFrequency = levelID.ssvepFrequency
        sim.distractorFrequency = levelID.distractorFrequency
        self.simulatedAttention = sim
        
        // 创建子系统
        self.attentionManager = AttentionManager(provider: sim)
        self.metalRenderer = MetalRenderer()
        self.audioEngine = AudioEngine()
        self.hapticEngine = HapticEngine()
        self.thermalMonitor = ThermalMonitor()
    }
    
    // MARK: - Session Lifecycle
    
    func startSession() {
        isSessionActive = true
        
        // 配置 Metal renderer
        metalRenderer.ssvepFrequency = levelID.ssvepFrequency
        
        // 启动热监控
        thermalMonitor.startMonitoring()
        thermalMonitor.thermalLevelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateQualitySettings()
            }
            .store(in: &cancellables)
        
        // 启动模拟注意力数据
        _ = simulatedAttention.startSampling()
        
        // 开始校准阶段
        transitionToPhase(.calibration)
    }
    
    func endSession() {
        isSessionActive = false
        phaseTimer?.invalidate()
        simulatedAttention.stopSampling()
        thermalMonitor.stopMonitoring()
        audioEngine.stop()
        hapticEngine.stop()
        attentionManager.reset()
        
        // 保存用户进度
        let avgFocusScore = focusDuration / max(focusDuration + neutralDuration + distractedDuration, 0.001)
        UserProfile.saveBestScore(levelID: levelID, score: Float(avgFocusScore))
        UserProfile.incrementCompletionCount(levelID: levelID)
    }
    
    // MARK: - Phase Management
    
    private func transitionToPhase(_ phase: SessionPhase) {
        phaseTimer?.invalidate()
        currentPhase = phase
        phaseStartTime = Date()
        
        switch phase {
        case .calibration:
            remainingTime = levelID.calibrationDuration
            audioEngine.playCalibrationTone(frequency: levelID.ssvepFrequency)
            
        case .immersion:
            remainingTime = 15  // 固定 15 秒引导
            audioEngine.playImmersionSoundscape()
            
        case .training:
            remainingTime = levelID.trainingDuration
            audioEngine.playTrainingSoundscape()
            startAttentionTracking()
            
        case .debrief:
            remainingTime = 0
            audioEngine.playDebriefAmbient()
        }
        
        startPhaseTimer()
    }
    
    private func onPhaseChanged() {
        if let next = currentPhase.next {
            // 自动推进到下一阶段
            // 在实际 UI 中，可能需要用户确认
        }
    }
    
    private func startPhaseTimer() {
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isSessionActive else { return }
            
            self.remainingTime -= 1.0
            
            if self.remainingTime <= 0 {
                self.phaseTimer?.invalidate()
                if let nextPhase = self.currentPhase.next {
                    self.transitionToPhase(nextPhase)
                } else {
                    self.endSession()
                }
            }
        }
    }
    
    private func startAttentionTracking() {
        stateChangeTimestamp = Date()
        
        attentionManager.attentionStatePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let now = Date()
                let duration = now.timeIntervalSince(self.stateChangeTimestamp)
                
                switch self.attentionManager.currentAttentionState {
                case .focused:    self.focusDuration += duration
                case .neutral:    self.neutralDuration += duration
                case .distracted: self.distractedDuration += duration
                }
                
                self.stateChangeTimestamp = now
            }
            .store(in: &cancellables)
    }
    
    private func updateQualitySettings() {
        metalRenderer.particleScale = thermalMonitor.particleScaleFactor
        metalRenderer.enableBloom = thermalMonitor.shouldEnableBloom
    }
}
```

---

> **Section 1 完毕**。以上定义了项目的完整工程基础：项目结构、依赖、状态机、数据流、构建步骤和硬性约束。实现工程师可以按照此文档从零搭建项目骨架，并在此基础上实现 Section 2（Metal 渲染管线）和 Section 3（音频引擎）的具体逻辑。

---

# 第2节 Metal 渲染管线与 SSVEP 频率控制器

> 本节为"星空与萤火"SSVEP 冥想 macOS 应用的核心渲染子系统设计。所有代码片段可直接用于实现，无需二次推断。

---

## 2.1 MTKView 配置

### 2.1.1 精确配置

```swift
final class MeditationView: MTKView {
    
    init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        
        // ── 刷新率：锁定 120Hz ProMotion ──
        preferredFramesPerSecond = 120
        isPaused = false
        enableSetNeedsDisplay = false   // 持续渲染，不由系统驱动
        
        // ── 像素格式 ──
        colorPixelFormat = .bgra8Unorm  // 见 2.1.2 分析
        depthStencilPixelFormat = .depth32Float_stencil8
        sampleCount = 1                 // 见 2.1.3 分析：不用 MSAA
        
        // ── 清屏色：深蓝黑夜空 ──
        clearColor = MTLClearColor(
            red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0
        )
        
        // ── 显示相关 ──
        autoResizeDrawable = true
        drawableSize = window?.screen?.nativeBounds.size ?? CGSize(width: 1728, height: 1117)
        contentScaleFactor = window?.screen?.backingScaleFactor ?? 2.0
        
        // ──CAMetalLayer 配置 ──
        if let layer = layer as? CAMetalLayer {
            layer.displaySyncEnabled = true           // VSync 锁定
            layer.allowsNextDrawableTimeout = false    // 不丢帧
            layer.maximumDrawableCount = 3             // 三重缓冲
        }
    }
}
```

### 2.1.2 像素格式决策：`.bgra8Unorm` vs `.rgba16Float`

**结论：使用 `.bgra8Unorm`。**

理由如下：

| 维度 | `.bgra8Unorm` | `.rgba16Float` |
|------|--------------|----------------|
| 带宽 | 4 bytes/pixel | 8 bytes/pixel |
| 120fps 填充率 | 基准 | 翻倍，影响 10000+ 粒子性能 |
| HDR 萤火发光 | 不支持真 HDR | 支持 |
| Bloom 模拟效果 | 可通过后处理叠加实现 | 原生 |
| ProMotion 120Hz 兼容 | 完美 | 部分设备可能降频 |

**萤火发光的实现策略**：在 `.bgra8Unorm` 帧缓冲上通过多 pass bloom（见 2.5）实现视觉上的 HDR 效果。萤火核心亮度写入 >1.0 的值到 `.rgba16Float` 中间纹理，模糊后 clamp 回 `.bgra8Unorm` 显示。这个中间纹理只存在于 bloom pipeline 内部，不影响主渲染开销。

```swift
// 帧缓冲链：主缓冲 + bloom 中间缓冲
// 主缓冲：.bgra8Unorm（MTKView drawable）
// Bloom 中间缓冲：.rgba16Float（离屏渲染用，见 2.5）
private let bloomSourceTexture: MTLTexture  // .rgba16Float, 全分辨率
private let bloomHalfTexture: MTLTexture    // .rgba16Float, 半分辨率
private let bloomQuarterTexture: MTLTexture // .rgba16Float, 1/4 分辨率
```

### 2.1.3 MSAA 决策：不使用

**结论：`sampleCount = 1`。**

| 场景 | MSAA 4x 开销 | 替代方案 |
|------|-------------|---------|
| 10000 粒子 @120fps | 填充率 ×4，几乎不可能维持 120fps | 粒子本身就是 soft circle，自带抗锯齿 |
| 萤火发光边缘 | 高斯模糊已经柔化边缘 | Bloom pass 自带柔化 |
| 星座连线 | 几何简单，锯齿不明显 | Line width + alpha blending |
| 树木/建筑剪影 | 复杂几何会有锯齿 | 用预烘焙的 SDF 轮廓代替实时光栅化 |

如果后续发现剪影锯齿严重，可以对剪影层单独使用 MSAA 2x，但默认不用。

### 2.1.4 Render Loop

```swift
final class MeditationRenderer: NSObject, MTKViewDelegate {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ssvepController: SSVEPController
    
    // ── Pipeline States ──
    private var backgroundPipeline: MTLRenderPipelineState
    private var particlePipeline: MTLComputePipelineState
    private var stimulusPipeline: MTLRenderPipelineState
    private var bloomPipeline: MTLRenderPipelineState
    
    // ── SSVEP 帧同步 ──
    private var frameCounter: UInt64 = 0
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        // ① 更新 SSVEP 控制器（必须在渲染前）
        ssvepController.onFrame()
        frameCounter += 1
        
        // ② 获取当前帧的 SSVEP 状态
        let ssvepState = ssvepController.currentState
        
        // ③ 构建 Command Buffer
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = "MeditationFrame_\(frameCounter)"
        
        // ④ 依次执行渲染 Pass（见 2.3）
        executeBackgroundPass(commandBuffer: commandBuffer, descriptor: renderPassDescriptor)
        executeParticleComputePass(commandBuffer: commandBuffer)
        executeStimulusPass(commandBuffer: commandBuffer, descriptor: renderPassDescriptor)
        executeBloomPass(commandBuffer: commandBuffer, drawable: drawable)
        
        // ⑤ 提交
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // ⑥ 帧率监控（Debug 用）
        #if DEBUG
        frameTimeLogger.record(timestamp: CACurrentMediaTime())
        #endif
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 重建所有依赖分辨率的纹理
        rebuildResolutionDependentTextures(width: Int(size.width), height: Int(size.height))
    }
}
```

---

## 2.2 SSVEP 频率控制器

### 2.2.1 核心设计

SSVEP 控制器是整个应用的心脏。它必须保证**帧精确**（frame-exact）的刺激频率，因为 EEG 的稳态视觉诱发电位高度依赖精确的频率。哪怕 0.1Hz 的偏差都会导致信噪比下降。

```swift
/// SSVEP 刺激状态：每帧计算一次，传递给所有渲染 Pass
struct SSVEPState {
    var targetOpacity: Float      // 15Hz 刺激当前透明度 [0.6, 1.0]
    var distractorOpacity: Float  // 20Hz 干扰刺激当前透明度 [0.6, 1.0]
    var advancedOpacity: Float    // 40Hz 高级刺激当前透明度 [0.6, 1.0]
    var targetActive: Bool        // 方波模式下的开关状态
    var distractorActive: Bool
    var frameIndex: UInt64        // 当前帧序号（用于调试）
}

/// SSVEP 刺激参数：定义单个频率通道
struct SSVEPChannel {
    let frequency: Int            // 目标频率 Hz
    let label: String             // "target" / "distractor" / "advanced"
    let waveType: SSVEPWaveType   // .sine 或 .square
    let minOpacity: Float         // 正弦波最小值，通常 0.6
    let maxOpacity: Float         // 正弦波最大值，通常 1.0
    let enabled: Bool             // 是否激活
    
    var phaseStep: Float {
        // 每帧相位增量 = 2π × freq / refreshRate
        Float(2.0 * Double.pi) * Float(frequency) / Float(SSVEPController.refreshRate)
    }
}

enum SSVEPWaveType {
    case sine     // 正弦波：opacity = 0.8 + 0.2 * sin(phase)
    case square   // 方波：opacity 在 0.0 和 1.0 之间切换
}

/// SSVEP 频率控制器
/// 设计原则：
/// 1. 所有频率通道共享同一个 frameCounter，保证帧同步
/// 2. 使用累积相位而非 mod 运算，避免浮点累积误差
/// 3. 提供 sin 查找表加速（2.1.2 决策的延伸）
final class SSVEPController {
    
    static let refreshRate: Int = 120
    
    // ── 频率通道 ──
    private(set) var targetChannel: SSVEPChannel
    private(set) var distractorChannel: SSVEPChannel
    private(set) var advancedChannel: SSVEPChannel
    
    // ── 帧计数 ──
    private var frameCount: UInt64 = 0
    
    // ── 累积相位（弧度） ──
    private var targetPhase: Float = 0.0
    private var distractorPhase: Float = 0.0
    private var advancedPhase: Float = 0.0
    
    // ── 正弦查找表 ──
    private let sinLUT: [Float]
    private let lutResolution: Int = 4096   // 4096 级精度，足够覆盖所有频率
    
    // ── 仿真数据（Demo 用） ──
    var simulatedAttention: Float = 0.7     // 0.0（分心）~ 1.0（专注）
    var simulatedLevel: Int = 2             // 当前关卡 1-6
    
    init() {
        targetChannel = SSVEPChannel(
            frequency: 15, label: "target", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: true
        )
        distractorChannel = SSVEPChannel(
            frequency: 20, label: "distractor", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: false
        )
        advancedChannel = SSVEPChannel(
            frequency: 40, label: "advanced", waveType: .sine,
            minOpacity: 0.6, maxOpacity: 1.0, enabled: false
        )
        
        // 预计算正弦查找表
        sinLUT = (0..<lutResolution).map { i in
            sin(2.0 * Float.pi * Float(i) / Float(lutResolution))
        }
    }
    
    /// 每帧调用一次。必须在渲染之前调用。
    func onFrame() {
        frameCount += 1
        
        // 累积相位
        targetPhase += targetChannel.phaseStep
        distractorPhase += distractorChannel.phaseStep
        advancedPhase += advancedChannel.phaseStep
        
        // 防止浮点溢出：每 120 帧（1 秒）重置相位到 [0, 2π)
        // 这不会造成视觉跳变，因为 120 是所有频率的公倍数
        if frameCount % 120 == 0 {
            let twoPi = Float(2.0 * Double.pi)
            targetPhase = targetPhase.truncatingRemainder(dividingBy: twoPi)
            distractorPhase = distractorPhase.truncatingRemainder(dividingBy: twoPi)
            advancedPhase = advancedPhase.truncatingRemainder(dividingBy: twoPi)
        }
    }
    
    /// 计算当前帧的 SSVEP 状态，供渲染 Pass 使用
    var currentState: SSVEPState {
        SSVEPState(
            targetOpacity: targetChannel.enabled
                ? opacityForChannel(channel: targetChannel, phase: targetPhase)
                : 1.0,
            distractorOpacity: distractorChannel.enabled
                ? opacityForChannel(channel: distractorChannel, phase: distractorPhase)
                : 1.0,
            advancedOpacity: advancedChannel.enabled
                ? opacityForChannel(channel: advancedChannel, phase: advancedPhase)
                : 1.0,
            targetActive: squareWaveActive(channel: targetChannel, phase: targetPhase),
            distractorActive: squareWaveActive(channel: distractorChannel, phase: distractorPhase),
            frameIndex: frameCount
        )
    }
    
    /// 正弦波透明度：opacity = 0.8 + 0.2 * sin(phase)
    private func opacityForChannel(channel: SSVEPChannel, phase: Float) -> Float {
        let range = channel.maxOpacity - channel.minOpacity
        let mid = (channel.maxOpacity + channel.minOpacity) / 2.0
        let sinValue = fastSin(phase)
        return mid + (range / 2.0) * sinValue
    }
    
    /// 方波模式：前半周期亮，后半周期暗
    private func squareWaveActive(channel: SSVEPChannel, phase: Float) -> Bool {
        let twoPi = Float(2.0 * Double.pi)
        let normalizedPhase = phase.truncatingRemainder(dividingBy: twoPi)
        return normalizedPhase < Float.pi
    }
    
    /// 查找表加速的 sin 函数
    /// 相比标准库 sin() 快约 3-5 倍，精度误差 < 0.001
    private func fastSin(_ x: Float) -> Float {
        let twoPi = Float(2.0 * Double.pi)
        let normalizedX = x.truncatingRemainder(dividingBy: twoPi)
        let positiveX = normalizedX < 0 ? normalizedX + twoPi : normalizedX
        let index = Int((positiveX / twoPi) * Float(lutResolution)) % lutResolution
        return sinLUT[index]
    }
    
    /// 重置所有状态（切换关卡时调用）
    func reset() {
        frameCount = 0
        targetPhase = 0.0
        distractorPhase = 0.0
        advancedPhase = 0.0
    }
    
    /// 配置关卡频率
    func configureForLevel(_ level: Int) {
        reset()
        targetChannel.enabled = true
        simulatedLevel = level
        
        switch level {
        case 1:  // 涟漪绽放：仅 15Hz
            targetChannel.frequency = 15
            distractorChannel.enabled = false
            advancedChannel.enabled = false
        case 2:  // 萤火引路：仅 15Hz
            targetChannel.frequency = 15
            distractorChannel.enabled = false
            advancedChannel.enabled = false
        case 3:  // 星图寻迹：15Hz + 20Hz 干扰
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 4:  // 真假萤火：15Hz + 20Hz 双色
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 5:  // 飞燕破云：15Hz + 20Hz
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.enabled = false
        case 6:  // 流星试炼：15Hz + 突发 40Hz
            targetChannel.frequency = 15
            distractorChannel.frequency = 20
            distractorChannel.enabled = true
            advancedChannel.frequency = 40
            advancedChannel.enabled = true   // RIFT mode 激活
        default:
            break
        }
    }
}
```

### 2.2.2 正弦波 vs 方波：性能与生理效果

设计文档明确要求"透明度正弦波形变（60%~100% 波动）"，因此默认使用正弦波。

**正弦波公式**：
```
opacity = 0.8 + 0.2 × sin(2π × freq × frameCount / 120)
```

其中：
- `0.8` 是中心透明度（60% 和 100% 的均值）
- `0.2` 是振幅（波动范围的一半）
- 结果范围：[0.6, 1.0]

**sin() 性能对比**：

| 方法 | 每次调用耗时 | 精度 | 适用场景 |
|------|------------|------|---------|
| `Foundation.sin()` | ~5ns | IEEE 754 全精度 | 初始化、非热路径 |
| `fastSin()` 查找表 | ~1.5ns | <0.001 误差 | 每帧热路径 |
| Metal shader 内 `sin()` | GPU 并行，忽略 | GPU 精度 | Fragment shader |

**结论**：CPU 端使用查找表 `fastSin()`，Metal shader 内使用 GPU 原生 `sin()`。查找表分辨率 4096 对于 120Hz 刷新率下所有 SSVEP 频率都绰绰有余。

**方波保留的理由**：方波 SSVEP 的谐波更丰富，某些频率下诱发电位更强。后续可作为高级选项提供给用户选择，但默认用正弦波，因为视觉效果更柔和、不刺眼。

### 2.2.3 频率验证表

| 频率 | 120Hz 半周期帧数 | 每帧相位步进 | 精度 | 生理备注 |
|------|-----------------|------------|------|---------|
| **15Hz** | 120/15 = 8 帧 | π/4 = 0.7854 rad | 完美整除 | α 波段附近，最强 SSVEP 响应 |
| **20Hz** | 120/20 = 6 帧 | π/3 = 1.0472 rad | 完美整除 | β 波段，中等响应 |
| **40Hz** | 120/40 = 3 帧 | 2π/3 = 2.0944 rad | 完美整除 | 接近临界闪烁融合频率(CFF)，部分人可能感知不到闪烁 |
| **56Hz** | 120/56 = 2.14 帧 | 0.9333π rad | 近似 | ⚠️ 非整除，需要累积相位法 |

**非整除频率的处理**：

15Hz、20Hz、40Hz 在 120Hz 下都是完美整除的，这是选择这三个频率的根本原因。如果未来需要支持 56Hz 等非整除频率：

```swift
// ❌ 错误做法：frameCount mod 会累积误差
let wrong = Float(frameCount % 8) / 8.0

// ✅ 正确做法：累积相位，每秒归零
var phase: Float = 0.0
phase += phaseStep  // phaseStep = 2π × 56 / 120
// 每秒归零防止浮点溢出
if frameCount % 120 == 0 {
    phase = phase.truncatingRemainder(dividingBy: 2.0 * .pi)
}
```

### 2.2.4 SSVEPState 的 Metal Buffer 传递

SSVEP 控制器的输出需要传递给 compute shader 和 fragment shader。使用 constant buffer：

```swift
/// Metal 端的 SSVEP 状态（与 Swift 端 SSVEPState 对齐）
struct SSVEPStateMetal {
    var targetOpacity: float     // offset 0
    var distractorOpacity: float // offset 4
    var advancedOpacity: float   // offset 8
    var targetActive: bool       // offset 12
    var distractorActive: bool   // offset 13
    var advancedActive: bool     // offset 14
    var _padding: uint8          // offset 15（对齐）
    var attentionLevel: float    // offset 16：仿真注意力 [0,1]
    var frameIndex: uint64       // offset 20
    var deltaTime: float         // offset 28
}

// 在 Metal shader 中
struct SSVEPParams {
    float targetOpacity;
    float distractorOpacity;
    float advancedOpacity;
    bool  targetActive;
    bool  distractorActive;
    bool  advancedActive;
    float attentionLevel;
    uint64_t frameIndex;
    float deltaTime;
};
```

每帧更新 buffer：

```swift
func updateSSVEPBuffer(commandBuffer: MTLCommandBuffer) {
    let state = ssvepController.currentState
    var metalState = SSVEPStateMetal(
        targetOpacity: state.targetOpacity,
        distractorOpacity: state.distractorOpacity,
        advancedOpacity: state.advancedOpacity,
        targetActive: state.targetActive,
        distractorActive: state.distractorActive,
        advancedActive: false,
        _padding: 0,
        attentionLevel: ssvepController.simulatedAttention,
        frameIndex: state.frameIndex,
        deltaTime: 1.0 / Float(SSVEPController.refreshRate)
    )
    
    ssvepBuffer.contents().copyMemory(
        from: &metalState,
        byteCount: MemoryLayout<SSVEPStateMetal>.size
    )
}
```

---

## 2.3 Metal 渲染管线架构

### 2.3.1 整体架构

```
┌──────────────────────────────────────────────────────────────┐
│                    Meditation Render Pipeline                 │
│                                                              │
│  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │ Background  │───▶│  Particle Compute │───▶│ Stimulus  │ │
│  │   Pass      │    │     Pass          │    │   Pass     │ │
│  │ (Static)    │    │ (Fireflies/Stars) │    │ (SSVEP)    │ │
│  └─────────────┘    └──────────────────┘    └─────┬──────┘ │
│                                                    │         │
│                                              ┌─────▼──────┐ │
│                                              │   Bloom    │ │
│                                              │   Pass     │ │
│                                              │ (Glow)     │ │
│                                              └─────┬──────┘ │
│                                                    │         │
│                                              ┌─────▼──────┐ │
│                                              │  Composite │ │
│                                              │   & Output │ │
│                                              └────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 2.3.2 Buffer 布局总表

所有 buffer 在初始化时一次性分配，每帧只更新数据内容。

```swift
/// Buffer 索引约定（所有 shader 统一使用）
enum BufferIndex: Int {
    case vertices    = 0   // 顶点数据
    case uniforms    = 1   // 变换矩阵、时间等全局参数
    case ssvep       = 2   // SSVEP 频率状态
    case particles   = 3   // 粒子数组（compute shader 读写）
    case attention   = 4   // 注意力状态（粒子行为控制）
    case levelConfig = 5   // 关卡配置参数
    case noise       = 6   // Perlin 噪声参数
}
```

**全局 Uniform Buffer**：

```swift
struct SceneUniforms {
    var viewProjectionMatrix: matrix_float4x4  // offset 0, 64 bytes
    var inverseViewProjection: matrix_float4x4  // offset 64, 64 bytes
    var cameraPosition: simd_float3             // offset 128, 12 bytes
    var _pad0: Float                            // offset 140, 4 bytes
    var time: Float                             // offset 144, 4 bytes
    var deltaTime: Float                        // offset 148, 4 bytes
    var resolution: simd_float2                 // offset 152, 8 bytes
    var mousePosition: simd_float2              // offset 160, 8 bytes
    // 总计: 168 bytes，对齐到 256 bytes
}

/// 关卡配置 Buffer
struct LevelConfig {
    var levelID: Int32            // offset 0
    var particleCount: Int32      // offset 4
    var maxParticleCount: Int32   // offset 8
    var hasDistractor: Bool       // offset 12
    var hasAdvanced: Bool         // offset 13
    var _pad: [UInt8]             // offset 14-15
    var backgroundColor: simd_float4  // offset 16
    var fogDensity: Float         // offset 32
    var fogColor: simd_float4     // offset 36
    var ambientLight: Float       // offset 52
    // 总计: 56 bytes，对齐到 64 bytes
}
```

### 2.3.3 Pass 1: Background Pass（背景渲染）

背景是静态或缓慢变化的环境元素（星空、山脉剪影、水面）。大部分帧不需要重绘，可以缓存。

**Vertex Shader 输入**：

```metal
struct BackgroundVertex {
    float3 position [[attribute(0)]];  // 屏幕空间 quad 顶点
    float2 uv       [[attribute(1)]];  // UV 坐标
};
```

**Vertex Shader 输出 / Fragment Shader 输入**：

```metal
struct BackgroundFragmentIn {
    float4 position [[position]];
    float2 uv;
};
```

**Fragment Shader 逻辑**：

```metal
fragment float4 backgroundFragment(
    BackgroundFragmentIn in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(BufferIndex.uniforms)]],
    constant LevelConfig& config   [[buffer(BufferIndex.levelConfig)]],
    texture2d<float, access::sample> starTexture [[texture(0)]],
    texture2d<float, access::sample> noiseTexture [[texture(1)]],
    sampler starSampler [[sampler(0)]]
) {
    // ① 基础天空渐变
    float2 uv = in.uv;
    float skyGradient = uv.y;
    float3 skyColor = mix(
        float3(0.02, 0.02, 0.05),  // 底部：深蓝黑
        float3(0.04, 0.06, 0.12),  // 顶部：稍亮的深蓝
        skyGradient
    );
    
    // ② 星空层（从预烘焙纹理采样）
    float4 starSample = starTexture.sample(starSampler, uv * 2.0);
    skyColor += starSample.rgb * starSample.a * config.ambientLight;
    
    // ③ 山脉剪影（通过 noise texture + UV 阈值化）
    float mountainNoise = noiseTexture.sample(starSampler, float2(uv.x * 3.0, 0.5)).r;
    float mountainHeight = smoothstep(0.3, 0.6, mountainNoise) * 0.15;
    if (uv.y < mountainHeight) {
        skyColor = float3(0.01, 0.01, 0.02);  // 纯黑剪影
    }
    
    // ④ 轻微的 noise 动态（呼吸感）
    float breathe = sin(uniforms.time * 0.5) * 0.005 + 1.0;
    skyColor *= breathe;
    
    return float4(skyColor, 1.0);
}
```

**优化：背景缓存策略**

背景大部分帧不变。使用一个离屏纹理缓存背景，仅在以下情况重绘：
1. 窗口大小变化
2. 关卡切换
3. 每 N 帧更新一次星空闪烁（N = 4，即 30fps 更新星空）

```swift
private var backgroundCacheTexture: MTLTexture?
private var backgroundDirty = true

func executeBackgroundPass(commandBuffer: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor) {
    // 检查是否需要重绘背景
    let shouldRedraw = backgroundDirty || (frameCounter % 4 == 0)
    
    if shouldRedraw {
        // 渲染到离屏纹理
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = backgroundCacheTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        
        // ... 执行背景渲染 ...
        backgroundDirty = false
    }
    
    // 将缓存的背景 blit 到主渲染目标
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
    blitEncoder.copy(
        from: backgroundCacheTexture!,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceSize: MTLSize(width: backgroundCacheTexture!.width,
                            height: backgroundCacheTexture!.height,
                            depth: 1),
        to: descriptor.colorAttachments[0].texture!,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
    )
    blitEncoder.endEncoding()
}
```

### 2.3.4 Pass 2: Particle Compute Pass（粒子模拟）

详见 2.4。

### 2.3.5 Pass 3: SSVEP Stimulus Pass（刺激渲染）

此 Pass 负责将 SSVEP 控制器的输出应用到需要闪烁的视觉元素上。

**渲染策略**：SSVEP 刺激不是单独渲染一层，而是**调制已有元素的透明度**。萤火虫、星星等元素在 Fragment Shader 中读取 SSVEP 透明度，直接乘以自身颜色。

```metal
fragment float4 stimulusFragment(
    ParticleFragmentIn in [[stage_in]],
    constant SSVEPParams& ssvep [[buffer(BufferIndex.ssvep)]],
    constant AttentionState& attention [[buffer(BufferIndex.attention)]]
) {
    // ① 基础粒子颜色（来自粒子属性）
    float4 baseColor = float4(in.color, in.brightness);
    
    // ② 判断此粒子属于哪个 SSVEP 通道
    float ssvepOpacity = 1.0;
    if (in.ssvepChannel == 0) {
        // 目标频率通道
        ssvepOpacity = ssvep.targetOpacity;
    } else if (in.ssvepChannel == 1) {
        // 干扰频率通道
        ssvepOpacity = ssvep.distractorOpacity;
    } else if (in.ssvepChannel == 2) {
        // 高级频率通道
        ssvepOpacity = ssvep.advancedOpacity;
    }
    
    // ③ 应用 SSVEP 透明度
    baseColor.a *= ssvepOpacity;
    
    // ④ 注意力调制（分心时粒子变暗，专注时粒子变亮）
    float attentionBoost = mix(0.6, 1.0, attention.level);
    baseColor.rgb *= attentionBoost;
    
    // ⑤ Soft circle（萤火虫不是方块）
    float dist = length(in.uv - float2(0.5));
    float softCircle = smoothstep(0.5, 0.2, dist);
    baseColor.a *= softCircle;
    
    return baseColor;
}
```

**Particle Vertex/Fragment 数据流**：

```metal
// Vertex Shader 输出
struct ParticleFragmentIn {
    float4 position   [[position]];
    float2 uv;         // 粒子局部 UV [0,1]
    float3 color;      // 粒子颜色
    float brightness;  // 基础亮度
    float size;        // 屏幕空间大小
    int   ssvepChannel; // 0=target, 1=distractor, 2=advanced, -1=none
};
```

### 2.3.6 Pass 4: Post-Processing / Bloom Pass（后处理）

详见 2.5。

---

## 2.4 粒子系统（Compute Shader）

### 2.4.1 粒子数据结构

```metal
/// 粒子结构体：每个粒子 64 bytes，对齐友好
struct Particle {
    packed_float2 position;    // offset 0:  世界空间位置 [meters]
    packed_float2 velocity;    // offset 8:  速度 [m/s]
    float         life;        // offset 16: 生命值 [0.0 = 刚出生, 1.0 = 死亡]
    float         maxLife;     // offset 20: 最大寿命 [seconds]
    packed_float3 color;       // offset 24: RGB 颜色
    float         brightness;  // offset 36: 基础亮度 [0, 1]
    float         size;        // offset 40: 屏幕空间半径 [pixels]
    float         phase;       // offset 44: Perlin 噪声相位偏移
    float         noiseScale;  // offset 48: 噪声缩放因子
    int           ssvepChannel; // offset 52: SSVEP 通道 (-1=无, 0=目标, 1=干扰, 2=高级)
    int           type;        // offset 56: 粒子类型 (0=萤火, 1=星星, 2=落叶, 3=水滴)
    float         _pad;        // offset 60: 对齐填充
};
// 总计: 64 bytes
```

**内存布局确认**：

```swift
// Swift 端对齐声明
struct ParticleSwift {
    var position: SIMD2<Float>     // 8 bytes
    var velocity: SIMD2<Float>     // 8 bytes
    var life: Float                // 4 bytes
    var maxLife: Float             // 4 bytes
    var color: SIMD3<Float>        // 12 bytes
    var brightness: Float          // 4 bytes
    var size: Float                // 4 bytes
    var phase: Float               // 4 bytes
    var noiseScale: Float          // 4 bytes
    var ssvepChannel: Int32        // 4 bytes
    var type: Int32                // 4 bytes
    var _pad: Float                // 4 bytes
    // 总计: 64 bytes ✅ 与 Metal 端一致
}
```

### 2.4.2 粒子数量分配

| 关卡 | 萤火虫 | 星星 | 其他粒子 | 总计 | Thread Group 数 |
|------|-------|------|---------|------|----------------|
| 1 涟漪绽放 | 500 (荷花发光) | 200 | 1000 水滴 | 1700 | 7 |
| 2 萤火引路 | 5000 | 300 | 500 雾气 | 5800 | 23 |
| 3 星图寻迹 | 200 | 5000 | 300 连线节点 | 5500 | 22 |
| 4 真假萤火 | 3000 绿黄 + 2000 蓝色 | 200 | 500 树叶 | 5700 | 23 |
| 5 飞燕破云 | 1000 | 100 | 2000 雨 | 3100 | 13 |
| 6 流星试炼 | 500 | 8000 | 200 流星 + 300 极光 | 9000 | 36 |

**Thread Group 配置**：

```swift
static let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)

func threadGridSize(for particleCount: Int) -> MTLSize {
    let groups = (particleCount + 255) / 256
    return MTLSize(width: groups * 256, height: 1, depth: 1)
    // 注意：实际粒子数可能小于 grid 大小
    // Compute shader 内通过 id < particleCount 判断
}
```

### 2.4.3 Compute Shader 完整实现

```metal
#include <metal_stdlib>
using namespace metal;

// ── Perlin 噪声（简化版 2D） ──
// 完整实现应放在独立头文件中
float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // smoothstep
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise2D(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// ── SSVEP 参数 ──
struct SSVEPParams {
    float targetOpacity;
    float distractorOpacity;
    float advancedOpacity;
    bool  targetActive;
    bool  distractorActive;
    bool  advancedActive;
    float attentionLevel;
    uint64_t frameIndex;
    float deltaTime;
};

// ── 注意力状态 ──
struct AttentionState {
    float level;           // [0, 1] 当前注意力
    float targetPositonX;  // 注意力聚焦目标位置
    float targetPositionY;
    float transitionSpeed; // 状态转换速度
};

// ── 场景 Uniforms ──
struct SceneUniforms {
    float4x4 viewProjectionMatrix;
    float4x4 inverseViewProjection;
    float3   cameraPosition;
    float    time;
    float    deltaTime;
    float2   resolution;
    float2   mousePosition;
};

// ── 粒子结构体（与 2.4.1 一致） ──
struct Particle {
    float2 position;
    float2 velocity;
    float  life;
    float  maxLife;
    float3 color;
    float  brightness;
    float  size;
    float  phase;
    float  noiseScale;
    int    ssvepChannel;
    int    type;
    float  _pad;
};

// ── 粒子模拟 Kernel ──
kernel void simulateParticles(
    device Particle* particles       [[buffer(0)]],
    constant uint&    particleCount  [[buffer(1)]],
    constant SceneUniforms& uniforms [[buffer(2)]],
    constant SSVEPParams& ssvep      [[buffer(3)]],
    constant AttentionState& attention [[buffer(4)]],
    uint id [[thread_position_in_grid]]
) {
    // 边界检查
    if (id >= particleCount) return;
    
    device Particle& p = particles[id];
    float dt = uniforms.deltaTime;
    float time = uniforms.time;
    
    // ═══════════════════════════════════════
    // 1. 生命周期管理
    // ═══════════════════════════════════════
    p.life += dt / p.maxLife;
    
    if (p.life >= 1.0) {
        // 重生粒子
        respawnParticle(p, uniforms, time);
        return;
    }
    
    // 生命曲线：淡入淡出
    float lifeAlpha = smoothstep(0.0, 0.1, p.life) * smoothstep(1.0, 0.8, p.life);
    p.brightness = lifeAlpha;
    
    // ═══════════════════════════════════════
    // 2. Perlin 噪声漫游
    // ═══════════════════════════════════════
    float2 noiseCoord = p.position * p.noiseScale + float2(p.phase, p.phase * 0.7);
    float2 noiseForce = float2(
        noise2D(noiseCoord + float2(time * 0.3, 0.0)),
        noise2D(noiseCoord + float2(0.0, time * 0.3))
    ) * 2.0 - 1.0;  // 归一化到 [-1, 1]
    
    // 噪声驱动的加速度
    float2 noiseAcceleration = noiseForce * 0.5;
    
    // ═══════════════════════════════════════
    // 3. 注意力行为
    // ═══════════════════════════════════════
    float2 attentionForce = float2(0.0);
    float2 attentionTarget = float2(attention.targetPositonX, attention.targetPositionY);
    
    if (p.ssvepChannel == 0) {
        // 目标频率粒子：专注时聚集，分心时散开
        float2 toTarget = attentionTarget - p.position;
        float distToTarget = length(toTarget);
        float2 direction = distToTarget > 0.001 ? normalize(toTarget) : float2(0.0);
        
        // 聚集力（专注时强，分心时弱）
        float gatherStrength = attention.level * 2.0;
        // 散开力（分心时激活）
        float scatterStrength = (1.0 - attention.level) * 1.5;
        
        attentionForce = direction * gatherStrength - direction * scatterStrength;
        
        // 距离衰减：太近时排斥，太远时吸引
        float idealDist = 0.15;  // 理想聚集半径
        float distFactor = smoothstep(0.0, idealDist, distToTarget);
        attentionForce *= distFactor;
    }
    
    // ═══════════════════════════════════════
    // 4. 速度更新与阻尼
    // ═══════════════════════════════════════
    p.velocity += (noiseAcceleration + attentionForce) * dt;
    p.velocity *= 0.95;  // 阻尼系数：0.95，防止速度爆炸
    
    // 限速
    float speed = length(p.velocity);
    if (speed > 0.5) {
        p.velocity = p.velocity / speed * 0.5;
    }
    
    // ═══════════════════════════════════════
    // 5. 位置更新
    // ═══════════════════════════════════════
    p.position += p.velocity * dt;
    
    // ═══════════════════════════════════════
    // 6. 边界处理（软边界，粒子会被推回）
    // ═══════════════════════════════════════
    float2 bounds = float2(1.0, 0.7);  // 世界空间边界
    float margin = 0.1;
    
    if (p.position.x < -bounds.x + margin) {
        p.velocity.x += 0.1 * dt;
    } else if (p.position.x > bounds.x - margin) {
        p.velocity.x -= 0.1 * dt;
    }
    if (p.position.y < -bounds.y + margin) {
        p.velocity.y += 0.1 * dt;
    } else if (p.position.y > bounds.y - margin) {
        p.velocity.y -= 0.1 * dt;
    }
    
    // ═══════════════════════════════════════
    // 7. 亮度微闪烁（独立于 SSVEP 的自然闪烁）
    // ═══════════════════════════════════════
    float flicker = noise2D(float2(time * 3.0, p.phase)) * 0.3 + 0.7;
    p.brightness *= flicker;
}

// ── 粒子重生 ──
void respawnParticle(device Particle& p, constant SceneUniforms& uniforms, float time) {
    p.life = 0.0;
    p.maxLife = 3.0 + hash(float2(p.phase, time)) * 5.0;  // 3~8 秒寿命
    
    // 随机位置（世界空间 [-1, 1] x [-0.7, 0.7]）
    p.position = float2(
        (hash(float2(p.phase * 1.1, time * 0.1)) - 0.5) * 2.0,
        (hash(float2(p.phase * 0.7, time * 0.3)) - 0.5) * 1.4
    );
    
    p.velocity = float2(0.0);
    p.brightness = 0.0;  // 从 0 开始淡入
}
```

### 2.4.4 粒子渲染 Vertex Shader

```metal
struct ParticleRenderVertexOut {
    float4 position   [[position]];
    float2 uv;
    float3 color;
    float brightness;
    float size;
    int   ssvepChannel;
};

vertex ParticleRenderVertexOut particleVertex(
    uint vid [[vertex_id]],
    uint pid [[instance_id]],
    device Particle* particles [[buffer(0)]],
    constant SceneUniforms& uniforms [[buffer(2)]]
) {
    ParticleRenderVertexOut out;
    
    device Particle& p = particles[pid];
    
    // Billboard quad：4 个顶点共享 instance_id
    // vid 0,1,2,3 → 左下, 右下, 左上, 右上
    float2 quadOffsets[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 offset = quadOffsets[vid] * p.size;
    
    // 投影到屏幕空间
    float4 worldPos = float4(p.position, 0.0, 1.0);
    float4 screenPos = uniforms.viewProjectionMatrix * worldPos;
    
    // 像素空间偏移
    float2 pixelOffset = offset / uniforms.resolution * 2.0;
    screenPos.xy += pixelOffset * screenPos.w;
    
    out.position = screenPos;
    out.uv = (quadOffsets[vid] + 1.0) * 0.5;  // [0, 1]
    out.color = p.color;
    out.brightness = p.brightness;
    out.size = p.size;
    out.ssvepChannel = p.ssvepChannel;
    
    return out;
}
```

### 2.4.5 注意力状态对粒子行为的影响

这是 No-HUD 设计的核心。玩家的注意力状态不通过任何 UI 显示，而是完全通过粒子行为传达。

```swift
/// 注意力状态机
struct AttentionStateMachine {
    enum State {
        case focused       // 专注：粒子聚集，亮度稳定
        case neutral       // 中性：粒子自然漫游
        case distracted    // 分心：粒子散开，亮度降低
    }
    
    var currentState: State = .neutral
    var attentionValue: Float = 0.7    // [0, 1]，从仿真数据获取
    var transitionProgress: Float = 0.0 // 状态转换进度 [0, 1]
    
    mutating func update(attentionLevel: Float) {
        let previousValue = attentionValue
        attentionValue = attentionLevel
        
        // 状态判断阈值
        let focusThreshold: Float = 0.75
        let distractThreshold: Float = 0.4
        
        let newState: State
        if attentionValue > focusThreshold {
            newState = .focused
        } else if attentionValue < distractThreshold {
            newState = .distracted
        } else {
            newState = .neutral
        }
        
        if newState != currentState {
            currentState = newState
            transitionProgress = 0.0
        }
        
        // 平滑过渡（约 1 秒完成）
        transitionProgress = min(transitionProgress + 1.0 / 120.0, 1.0)
    }
    
    /// 传递给 GPU 的注意力参数
    var metalState: AttentionState {
        let gatherStrength: Float
        let scatterStrength: Float
        
        switch currentState {
        case .focused:
            gatherStrength = transitionProgress * 2.0
            scatterStrength = 0.0
        case .neutral:
            gatherStrength = 0.0
            scatterStrength = 0.0
        case .distracted:
            gatherStrength = 0.0
            scatterStrength = transitionProgress * 1.5
        }
        
        return AttentionState(
            level: attentionValue,
            targetPositonX: 0.0,  // 聚集中心（可配置）
            targetPositionY: 0.0,
            transitionSpeed: transitionProgress
        )
    }
}
```

---

## 2.5 Bloom / Glow 后处理

### 2.5.1 管线设计

标准的多级降采样 Bloom 管线：

```
源纹理 (全分辨率, .rgba16Float)
    │
    ├─ 提取亮部 (threshold)
    ▼
半分辨率纹理 (1/2)
    │
    ├─ 水平高斯模糊
    ├─ 垂直高斯模糊
    ▼
1/4 分辨率纹理
    │
    ├─ 水平高斯模糊
    ├─ 垂直高斯模糊
    ▼
1/8 分辨率纹理 (可选，用于大面积光晕)
    │
    └─ 叠加回主纹理 (additive blend)
```

### 2.5.2 纹理分配

```swift
class BloomPipeline {
    let device: MTLDevice
    
    // 中间纹理
    private(set) var halfTexture: MTLTexture?      // 1/2 分辨率
    private(set) var quarterTexture: MTLTexture?    // 1/4 分辨率
    private(set) var eighthTexture: MTLTexture?     // 1/8 分辨率（可选）
    
    // Pipeline States
    private var thresholdPipeline: MTLComputePipelineState
    private var blurHorizontalPipeline: MTLComputePipelineState
    private var blurVerticalPipeline: MTLComputePipelineState
    private var compositePipeline: MTLRenderPipelineState
    
    // 高斯模糊权重（9-tap）
    private let blurWeights: [Float] = [
        0.0162, 0.0540, 0.1217, 0.1945, 0.2270,
        0.1945, 0.1217, 0.0540, 0.0162
    ]
    
    func rebuildTextures(width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width / 2,
            height: height / 2,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        halfTexture = device.makeTexture(descriptor: descriptor)
        
        descriptor.width = width / 4
        descriptor.height = height / 4
        quarterTexture = device.makeTexture(descriptor: descriptor)
        
        descriptor.width = width / 8
        descriptor.height = height / 8
        eighthTexture = device.makeTexture(descriptor: descriptor)
    }
}
```

### 2.5.3 Bloom 阈值

**萤火绿 (#cddc39) 的 Bloom 阈值**：

将 #cddc39 转换为线性亮度：
```
R = 0.804, G = 0.863, B = 0.224
Luminance = 0.2126 × 0.804 + 0.7152 × 0.863 + 0.0722 × 0.224 = 0.829
```

**星星蓝 (#8ab4f8) 的 Bloom 阈值**：
```
R = 0.541, G = 0.706, B = 0.973
Luminance = 0.2126 × 0.541 + 0.7152 × 0.706 + 0.0722 × 0.973 = 0.672
```

**统一阈值：0.5**。低于此亮度的不产生 bloom，高于此亮度的按比例叠加光晕。

```metal
/// Bloom 亮部提取
kernel void bloomExtract(
    texture2d<float, access::read> source   [[texture(0)]],
    texture2d<float, access::write> dest   [[texture(1)]],
    constant float& threshold              [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 color = source.read(gid);
    
    // 亮度计算（Rec.709）
    float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // 软阈值：不是硬截断，而是平滑过渡
    float contribution = smoothstep(threshold, threshold + 0.3, luminance);
    
    dest.write(float4(color.rgb * contribution, 1.0), gid);
}
```

### 2.5.4 高斯模糊

使用可分离的 9-tap 高斯模糊，分别进行水平和垂直 pass：

```metal
/// 水平高斯模糊
kernel void blurHorizontal(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float weights[9]          [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 result = float4(0.0);
    
    for (int i = -4; i <= 4; i++) {
        int2 coord = int2(gid.x + i, gid.y);
        coord.x = clamp(coord.x, 0, int(source.get_width()) - 1);
        result += source.read(uint2(coord)) * weights[i + 4];
    }
    
    dest.write(result, gid);
}

/// 垂直高斯模糊（结构与水平相同，coord 偏移方向不同）
kernel void blurVertical(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float weights[9]          [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 result = float4(0.0);
    
    for (int i = -4; i <= 4; i++) {
        int2 coord = int2(gid.x, gid.y + i);
        coord.y = clamp(coord.y, 0, int(source.get_height()) - 1);
        result += source.read(uint2(coord)) * weights[i + 4];
    }
    
    dest.write(result, gid);
}
```

**模糊 pass 数量**：每个降采样级别 2 次（水平 + 垂直），3 个级别共 6 次。

### 2.5.5 最终合成

```metal
/// Bloom 合成：将模糊后的光晕叠加到原始图像
fragment float4 bloomComposite(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sceneTexture   [[texture(0)]],
    texture2d<float, access::sample> bloomHalf     [[texture(1)]],
    texture2d<float, access::sample> bloomQuarter  [[texture(2)]],
    texture2d<float, access::sample> bloomEighth   [[texture(3)]],
    constant float& bloomIntensity [[buffer(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float4 scene = sceneTexture.sample(linearSampler, in.uv);
    
    // 多级 bloom 叠加（不同强度）
    float4 halfBloom  = bloomHalf.sample(linearSampler, in.uv)  * 0.5;
    float4 quarterBloom = bloomQuarter.sample(linearSampler, in.uv) * 0.3;
    float4 eighthBloom = bloomEighth.sample(linearSampler, in.uv) * 0.2;
    
    float4 totalBloom = (halfBloom + quarterBloom + eighthBloom) * bloomIntensity;
    
    // Additive blend
    float4 result;
    result.rgb = scene.rgb + totalBloom.rgb;
    result.rgb = min(result.rgb, float3(1.5));  // 允许轻微过曝
    result.a = 1.0;
    
    return result;
}
```

**Bloom 强度随注意力变化**：

```swift
// 专注时 bloom 更强烈（萤火聚集，光芒交叠）
// 分心时 bloom 减弱（粒子散开，光芒稀疏）
let bloomIntensity: Float = 0.8 + attentionValue * 0.5  // [0.8, 1.3]
```

---

## 2.6 关卡特定渲染需求

### 2.6.1 总览表

| 关卡 | 核心视觉元素 | 渲染目标数 | SSVEP 目标 | SSVEP 干扰 | 特殊 Shader | 粒子总量 |
|------|-----------|----------|----------|----------|-----------|---------|
| 1 涟漪绽放 | 水面 quad + 荷花发光 + 背景星空 | 2 (scene + bloom) | 15Hz 荷花光晕 | 无 | 水面波纹 (vertex displacement), 荷花 glow | 1700 |
| 2 萤火引路 | 萤火虫群 + 雾气 + 石碑 + 背景星空 | 2 (scene + bloom) | 15Hz 萤火虫群 | 无 | 雾气 volume (ray marching), Perlin 噪声, 石碑 SDF | 5800 |
| 3 星图寻迹 | 星星群 + 星座连线 + 旋转目标星 | 2 (scene + bloom) | 15Hz 目标星 | 20Hz 背景星 | 连线 glow, 星星 burst, 旋转动画 | 5500 |
| 4 真假萤火 | 绿黄萤火 + 蓝色萤火 + 大树 + 落叶 | 2 (scene + bloom) | 15Hz 绿黄萤火 | 20Hz 蓝色萤火 | 树生长动画 (vertex animation), 叶片飘落 | 5700 |
| 5 飞燕破云 | 暴风云层 + 燕子 + 闪电 + 雨 | 3 (scene + rain + bloom) | 15Hz 燕子 | 20Hz 闪电 | 云层噪声, 雨滴 (instanced), 屏幕震动, 闪电 | 3100 |
| 6 流星试炼 | 极简天空 + 孤星 + 流星 + 极光 + 月亮裂纹 | 3 (scene + trail + bloom) | 15Hz 孤星 | 突发 40Hz | 流星拖尾, 极光 (noise-based), 月亮裂纹, 屏幕震动 | 9000 |

### 2.6.2 各关卡详细需求

#### 关卡 1：涟漪绽放

**渲染目标**：1 个场景纹理 + bloom 纹理链

**视觉元素**：
- 水面：全屏 quad，vertex shader 做 sine 波位移模拟水面
- 荷花发光点：500 个粒子，SSVEP 通道 = 0（目标频率），绿色
- 水滴涟漪：1000 个粒子，从上方落下，接触水面产生涟漪
- 背景星空：200 颗静态星星（缓存纹理）

**特殊 Shader**：水面波纹

```metal
/// 水面 Vertex Shader：顶点位移
vertex WaterVertexOut waterVertex(
    WaterVertexIn in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(1)]],
    constant SSVEPParams& ssvep [[buffer(2)]]
) {
    WaterVertexOut out;
    
    float2 pos = in.position;
    
    // 多层正弦波叠加
    float wave1 = sin(pos.x * 10.0 + uniforms.time * 1.5) * 0.01;
    float wave2 = sin(pos.y * 8.0 + uniforms.time * 2.0) * 0.008;
    float wave3 = sin((pos.x + pos.y) * 6.0 + uniforms.time * 1.0) * 0.005;
    
    pos.y += wave1 + wave2 + wave3;
    
    out.position = float4(pos, 0.0, 1.0);
    out.uv = in.uv;
    out.waveHeight = wave1 + wave2 + wave3;
    
    return out;
}
```

**无干扰频率**：这是入门关卡，仅有 15Hz 目标频率，玩家无需区分。

#### 关卡 2：萤火引路

**渲染目标**：1 个场景纹理 + bloom 纹理链

**视觉元素**：
- 萤火虫群：5000 个粒子，SSVEP 通道 = 0，绿色 (#cddc39)
- 雾气：500 个大型半透明粒子，无 SSVEP 通道，使用 ray marching
- 石碑：一个预烘焙的 mesh，SSVEP 纹理发光引导玩家视线
- 背景星空：300 颗星星

**特殊 Shader**：雾气 Ray Marching

```metal
/// 雾气 Fragment Shader（简化版 ray marching）
fragment float4 fogFragment(
    FogVertexOut in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(1)]],
    texture3d<float, access::sample> noiseVolume [[texture(0)]],
    sampler volumeSampler [[sampler(0)]]
) {
    float3 rayOrigin = in.rayOrigin;
    float3 rayDir = in.rayDirection;
    
    float density = 0.0;
    int steps = 32;  // 32 步 ray marching（性能与效果的平衡）
    
    for (int i = 0; i < steps; i++) {
        float t = float(i) / float(steps) * in.maxDistance;
        float3 pos = rayOrigin + rayDir * t;
        
        // 从 3D 噪声纹理采样
        float3 sampleCoord = (pos + float3(uniforms.time * 0.05)) * 0.5;
        float sample = noiseVolume.sample(volumeSampler, sampleCoord).r;
        
        // 密度累积
        density += sample * (1.0 / float(steps));
    }
    
    // 雾的颜色：淡蓝绿
    float3 fogColor = float3(0.6, 0.8, 0.7);
    float alpha = smoothstep(0.0, 0.3, density) * 0.3;
    
    return float4(fogColor, alpha);
}
```

**注意力反馈**：
- 专注 → 萤火虫向石碑聚集，形成明亮光路
- 分心 → 萤火虫散开，光路消失，雾气变浓

#### 关卡 3：星图寻迹

**渲染目标**：1 个场景纹理 + bloom 纹理链

**视觉元素**：
- 星星群：5000 个粒子
  - 目标星座星星：200 个，SSVEP 通道 = 0（15Hz），旋转动画
  - 干扰星星：4800 个，SSVEP 通道 = 1（20Hz），静态闪烁
- 星座连线：300 个连线节点，line geometry + glow
- 背景：纯深蓝

**特殊 Shader**：星座连线 Glow

```metal
/// 连线 Fragment Shader：发光线条
fragment float4 constellationLineFragment(
    LineVertexOut in [[stage_in]],
    constant SSVEPParams& ssvep [[buffer(2)]]
) {
    // 线条本身
    float lineWidth = 1.0;
    float edgeSoftness = smoothstep(lineWidth, 0.0, abs(in.distanceToLine));
    
    // 发光外圈
    float glowWidth = 5.0;
    float glow = exp(-in.distanceToLine * in.distanceToLine / (glowWidth * glowWidth));
    
    // SSVEP 调制：目标星座线条随 15Hz 闪烁
    float ssvepModulation = in.isTargetLine ? ssvep.targetOpacity : 1.0;
    
    float3 lineColor = in.isTargetLine ? float3(1.0, 0.95, 0.8) : float3(0.4, 0.5, 0.7);
    float alpha = (edgeSoftness * 0.8 + glow * 0.3) * ssvepModulation;
    
    return float4(lineColor, alpha);
}
```

**核心挑战**：玩家需要在闪烁的目标星和干扰星之间找到正确的星座。No-HUD 设计下，正确连接的星座会"亮起来"（目标星座的 bloom 更强），错误连接的会"淡下去"。

#### 关卡 4：真假萤火

**渲染目标**：1 个场景纹理 + bloom 纹理链

**视觉元素**：
- 绿黄萤火：3000 个，SSVEP 通道 = 0（15Hz），颜色 #cddc39
- 蓝色萤火：2000 个，SSVEP 通道 = 1（20Hz），颜色 #64b5f6
- 大树：一个 mesh，vertex animation 实现生长效果
- 落叶：500 个粒子，飘落动画

**特殊 Shader**：树生长动画

```metal
/// 树生长 Vertex Shader
vertex TreeVertexOut treeVertex(
    TreeVertexIn in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(1)]],
    constant float& growthProgress [[buffer(5)]]  // [0, 1]
) {
    TreeVertexOut out;
    
    float3 pos = in.position;
    
    // 生长动画：从底部向上展开
    float vertexHeight = (pos.y + 1.0) / 2.0;  // 归一化高度
    float growThreshold = growthProgress * 1.2;  // 略微超出以确保完全展开
    
    if (vertexHeight > growThreshold) {
        // 还没长到的部分：缩到种子点
        pos = float3(0.0, -1.0, 0.0) + pos * 0.01;
    } else {
        // 已经长到的部分：可能有轻微的展开动画
        float growFactor = smoothstep(growThreshold - 0.2, growThreshold, vertexHeight);
        pos.x *= growFactor;
        pos.z *= growFactor;
    }
    
    out.position = float4(pos, 1.0);
    out.uv = in.uv;
    out.growthFactor = growthProgress;
    
    return out;
}
```

**注意力反馈**：
- 专注 → 绿黄萤火（目标）聚集到树上，树生长加速
- 分心 → 蓝色萤火（干扰）聚集到树上，树生长停止甚至萎缩

#### 关卡 5：飞燕破云

**渲染目标**：2 个场景纹理（scene + rain layer）+ bloom 纹理链

**视觉元素**：
- 燕子：1 个 mesh，path animation，SSVEP 通道 = 0（15Hz），发光轮廓
- 暴风云层：全屏 noise shader，动态移动
- 闪电：20Hz 干扰频率触发，屏幕闪白 + 分叉闪电几何
- 雨：2000 个 instanced 线段粒子，从上到下

**特殊 Shader**：云层噪声

```metal
/// 云层 Fragment Shader
fragment float4 stormCloudFragment(
    CloudVertexOut in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(1)]],
    constant SSVEPParams& ssvep [[buffer(2)]],
    texture2d<float, access::sample> noiseTexture [[texture(0)]],
    sampler noiseSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float time = uniforms.time;
    
    // 多层 FBM 噪声
    float n1 = noiseTexture.sample(noiseSampler, uv * 3.0 + float2(time * 0.1, 0.0)).r;
    float n2 = noiseTexture.sample(noiseSampler, uv * 6.0 + float2(0.0, time * 0.15)).r * 0.5;
    float n3 = noiseTexture.sample(noiseSampler, uv * 12.0 + float2(time * 0.05, time * 0.08)).r * 0.25;
    
    float cloudDensity = (n1 + n2 + n3) / 1.75;
    
    // 云的颜色：深灰到暗紫
    float3 cloudColor = mix(
        float3(0.08, 0.06, 0.1),   // 暗部
        float3(0.25, 0.22, 0.3),    // 亮部
        cloudDensity
    );
    
    // 闪电照明（20Hz SSVEP 触发时云层闪亮）
    float lightningBrightness = 0.0;
    if (ssvep.distractorActive) {
        lightningBrightness = 0.5;
    }
    cloudColor += float3(lightningBrightness);
    
    float alpha = smoothstep(0.3, 0.7, cloudDensity) * 0.9;
    
    return float4(cloudColor, alpha);
}
```

**屏幕震动**：在闪电触发时应用相机抖动。

```swift
// 在 SceneUniforms 中添加震动偏移
if ssvepState.distractorActive && currentLevel == 5 {
    let shakeIntensity: Float = 0.003
    let shakeOffset = SIMD2<Float>(
        Float.random(in: -shakeIntensity...shakeIntensity),
        Float.random(in: -shakeIntensity...shakeIntensity)
    )
    uniforms.viewProjectionMatrix = uniforms.viewProjectionMatrix.translatedBy(x: shakeOffset.x, y: shakeOffset.y, z: 0)
}
```

#### 关卡 6：流星试炼

**渲染目标**：2 个场景纹理（scene + trail）+ bloom 纹理链

**视觉元素**：
- 孤星：1 个粒子，固定位置，SSVEP 通道 = 0（15Hz），高亮度
- 背景星空：8000 个静态粒子，无 SSVEP 通道
- 流星：200 个高速粒子，随机出现
- 极光：300 个粒子，noise-based 颜色变化
- 月亮裂纹：屏幕空间 shader 效果

**特殊 Shader**：月亮裂纹

```metal
/// 月亮裂纹 Fragment Shader
fragment float4 moonCrackFragment(
    CrackVertexOut in [[stage_in]],
    constant SceneUniforms& uniforms [[buffer(1)]],
    constant float& crackProgress [[buffer(5)]]  // [0, 1]
) {
    float2 uv = in.uv;
    float time = uniforms.time;
    
    // 月亮基础：圆形发光
    float moonDist = length(uv - float2(0.7, 0.8));
    float moon = smoothstep(0.15, 0.12, moonDist);
    float3 moonColor = float3(0.95, 0.93, 0.85) * moon;
    
    // 裂纹（Voronoi 噪声为基础）
    float2 crackUV = (uv - float2(0.7, 0.8)) * 5.0;
    float crack = noise2D(crackUV * 3.0 + float2(crackProgress * 10.0, 0.0));
    crack = smoothstep(0.48, 0.5, crack) * crackProgress;
    
    // 裂纹发光
    float3 crackColor = float3(1.0, 0.6, 0.2) * crack * 2.0;
    
    // 裂纹扩散的光晕
    float crackGlow = exp(-moonDist * 5.0) * crackProgress * 0.3;
    float3 glowColor = float3(1.0, 0.4, 0.1) * crackGlow;
    
    float3 finalColor = moonColor + crackColor + glowColor;
    float alpha = max(moon, crack * 0.8);
    
    return float4(finalColor, alpha);
}
```

**突发 40Hz（RIFT mode）**：当月亮裂纹达到阈值时，突发 40Hz 刺激。这是高级模式，利用接近 CFF 的频率创造一种"感觉到了但看不清"的视觉体验。

```swift
// RIFT mode 激活条件
if crackProgress > 0.8 && !ssvepController.advancedChannel.enabled {
    ssvepController.advancedChannel.enabled = true
    // 40Hz 持续 3 秒后关闭
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        ssvepController.advancedChannel.enabled = false
    }
}
```

### 2.6.3 关卡切换时的资源管理

```swift
/// 关卡切换
func transitionToLevel(_ level: Int) {
    // ① 重置 SSVEP 控制器
    ssvepController.configureForLevel(level)
    
    // ② 更新关卡配置 Buffer
    updateLevelConfig(level: level)
    
    // ③ 重新初始化粒子系统
    particleSystem.initializeForLevel(level)
    
    // ④ 重建背景缓存
    backgroundDirty = true
    
    // ⑤ 调整 bloom 强度（不同关卡的光照环境不同）
    switch level {
    case 1: bloomIntensity = 0.8   // 水面反射柔和
    case 2: bloomIntensity = 1.2   // 萤火虫强光
    case 3: bloomIntensity = 0.6   // 星空冷光
    case 4: bloomIntensity = 1.0   // 萤火双色中等
    case 5: bloomIntensity = 0.4   // 暴风云遮挡
    case 6: bloomIntensity = 1.5   // 流星和极光强光
    default: bloomIntensity = 1.0
    }
    
    // ⑥ 清空所有 pipeline state 缓存（如果关卡需要不同的 shader 变体）
    pipelineStateCache.flush()
}
```

---

## 2.7 Demo 模式仿真数据

### 2.7.1 仿真注意力数据

```swift
/// Demo 模式的注意力仿真器
/// 模拟真实 EEG BCI 的数据流特征
final class AttentionSimulator {
    
    enum SimPattern {
        case focused          // 持续高注意力
        case wavering         // 注意力波动
        case distracted       // 注意力下降
        case recovery         // 从分心恢复
        case rhythmTraining   // 节奏训练（与 SSVEP 同步）
    }
    
    private var pattern: SimPattern = .wavering
    private var baseValue: Float = 0.7
    private var noisePhase: Float = 0.0
    private var patternTimer: TimeInterval = 0.0
    
    /// 每帧调用，返回仿真注意力值 [0, 1]
    func update(deltaTime: TimeInterval) -> Float {
        patternTimer += deltaTime
        noisePhase += deltaTime * 2.0
        
        // 基础噪声
        let noise = sin(noisePhase * 3.7) * 0.05 + sin(noisePhase * 7.1) * 0.03
        
        switch pattern {
        case .focused:
            baseValue = min(baseValue + deltaTime * 0.1, 0.95)
            
        case .wavering:
            // 5 秒周期波动
            let wave = sin(patternTimer * 1.2566) * 0.25  // 2π/5
            baseValue = 0.65 + wave
            
        case .distracted:
            baseValue = max(baseValue - deltaTime * 0.15, 0.2)
            
        case .recovery:
            baseValue = min(baseValue + deltaTime * 0.08, 0.8)
            
        case .rhythmTraining:
            // 与 15Hz SSVEP 同步的节律
            let ssvepSync = sin(patternTimer * Float.pi * 2.0 * 0.5) * 0.1
            baseValue = 0.75 + ssvepSync
        }
        
        // 添加高频噪声（模拟真实 BCI 信号噪声）
        let highFreqNoise = sin(noisePhase * 23.0) * 0.02
        
        return clamp(baseValue + noise + highFreqNoise, 0.0, 1.0)
    }
    
    /// 自动切换仿真模式（Demo 演示用）
    func autoSwitchPattern(elapsed: TimeInterval) {
        let cycle = elapsed.truncatingRemainder(dividingBy: 40.0)  // 40 秒一个周期
        
        if cycle < 8.0 {
            pattern = .focused
        } else if cycle < 16.0 {
            pattern = .wavering
        } else if cycle < 22.0 {
            pattern = .distracted
        } else if cycle < 30.0 {
            pattern = .recovery
        } else {
            pattern = .rhythmTraining
        }
    }
}
```

### 2.7.2 仿真数据传递

```swift
/// 在每帧渲染前更新
func updateSimulation(deltaTime: TimeInterval) {
    let attentionValue = attentionSimulator.update(deltaTime: deltaTime)
    attentionSimulator.autoSwitchPattern(elapsed: totalElapsedTime)
    
    // 更新 SSVEP 控制器的仿真注意力
    ssvepController.simulatedAttention = attentionValue
    
    // 更新注意力状态机
    attentionStateMachine.update(attentionLevel: attentionValue)
    
    // 更新 GPU Buffer
    updateAttentionBuffer(
        level: attentionStateMachine.metalState.level,
        targetX: attentionStateMachine.metalState.targetPositonX,
        targetY: attentionStateMachine.metalState.targetPositionY,
        transition: attentionStateMachine.metalState.transitionSpeed
    )
}
```

---

## 2.8 性能预算

在 ProMotion 120Hz 下，每帧预算为 **8.33ms**。各 Pass 分配：

| Pass | 预算 | 10000 粒子开销 | 备注 |
|------|------|--------------|------|
| Background | 0.5ms | 0.1ms（缓存命中时） | 4 帧更新一次 |
| Particle Compute | 2.0ms | 1.5ms | 256 线程组，GPU 并行 |
| SSVEP Stimulus Render | 2.0ms | 1.8ms | Instanced drawing，10000 粒子 × 4 顶点 |
| Bloom Extract | 0.5ms | 0.3ms | 全屏 compute shader |
| Bloom Blur ×6 | 1.5ms | 1.2ms | 降采样后计算量小 |
| Bloom Composite | 0.5ms | 0.3ms | 全屏 quad |
| SSVEP Controller (CPU) | 0.1ms | <0.01ms | 查找表 sin，忽略不计 |
| Command Buffer 提交 | 0.3ms | 0.3ms | 固定开销 |
| **总计** | **7.4ms** | **~5.5ms** | **余量 0.9ms** |

**最坏情况**（关卡 6，9000 粒子 + 流星 + 极光）：约 6.5ms，仍在预算内。

---

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


---

# Section 4: 关卡详细规格 (Level Specifications)

> 本节为每个关卡提供可直接用于 Metal shader 编码、SwiftUI 绑定和音频合成的精确参数。所有 hex 值、粒子数量、时间常量均为实现规范，不得自行调整。

---

## 4.0 跨关卡参数总览 (Cross-Level Reference Tables)

### 4.0.1 频率分配表

| Level | 名称 | Realm | Target Freq | Distractor Freq | Advanced Freq | Target Wave | Distractor Wave |
|------:|------|-------|------------:|----------------:|--------------:|-------------|-----------------|
| 1 | 涟漪绽放 | 觉醒 | 15 Hz | 无 | 无 | sine | N/A |
| 2 | 萤火引路 | 觉醒 | 15 Hz | 无 | 无 | sine | N/A |
| 3 | 星图寻迹 | 共鸣 | 15 Hz | 20 Hz | 无 | sine | sine |
| 4 | 真假萤火 | 共鸣 | 15 Hz | 20 Hz | 无 | sine | sine |
| 5 | 飞燕破云 | 心流 | 15 Hz | 20 Hz | 无 | sine | sine |
| 6 | 流星试炼 | 心流 | 15 Hz | 20 Hz | 40 Hz (RIFT) | sine | sine + pulse |

**SSVEP 刺激闪烁实现规范：**

所有频率的闪烁必须通过 Metal shader 中的 `sin(uTime * freq * 2π)` 控制 opacity，而非修改渲染帧率。渲染帧率始终锁定 60 FPS（标准屏）或 120 FPS（ProMotion）。

```metal
// 通用 SSVEP opacity 计算
// 输入: uTime (秒), freq (Hz), minOpacity, maxOpacity
// 输出: 0.0-1.0 透明度
float ssvepOpacity(float uTime, float freq, float minOpacity, float maxOpacity) {
    float phase = sin(uTime * freq * 2.0 * M_PI_F);  // -1.0 到 1.0
    float normalized = phase * 0.5 + 0.5;             // 0.0 到 1.0
    return mix(minOpacity, maxOpacity, normalized);
}
```

**频率精度要求：** 在 120 FPS 下，15 Hz 对应每 8 帧完成一个完整周期，20 Hz 对应每 6 帧。实现时必须通过 `sin()` 函数而非帧计数器驱动，确保在任意帧率下频率精度偏差 <0.1%。

### 4.0.2 粒子数量表

| Level | 主粒子类型 | 主粒子数量 | 次粒子类型 | 次粒子数量 | 环境粒子 | 环境粒子数量 |
|------:|-----------|----------:|-----------|----------:|---------|------------:|
| 1 | 水波纹涟漪 | 8 (同屏) | 花瓣微粒 | 24 | 水面微光 | 60 |
| 2 | 萤火虫 | 40 (动态) | 光点尾迹 | 120 | 迷雾粒子 | 200 |
| 3 | 星辰 | 80 (静态) | 星座连线光点 | 0 | 暗星背景 | 300 |
| 4 | 黄绿萤火 (target) | 25 | 幽蓝萤火 (distractor) | 25 | 树叶粒子 | 80 |
| 5 | 灵燕光羽 | 30 (尾迹) | 雨滴 | 150 | 雷电碎片 | 40 |
| 6 | 流星尾焰 | 20 (突发) | 极光波纹 | 0 (shader) | 雪花 | 100 |

**粒子系统通用约束：**

- 每个粒子占用 <= 64 bytes GPU 内存（position: float2, velocity: float2, life: float, size: float, color: float4）
- 总粒子 buffer 上限：2048 个粒子 = 128 KB
- 粒子更新使用 compute shader，dispatch 线程数 = `ceil(particleCount / 256)`
- 粒子渲染使用 instanced draw call，单次 draw 即可渲染同类型全部粒子

### 4.0.3 色彩总表

| Level | Target 主色 | Target 辅色 | Distractor 主色 | Distractor 辅色 | 背景起始色 | 背景终止色 |
|------:|-----------|-----------|----------------|----------------|-----------|-----------|
| 1 | `#cddc39` | `#ffe9a6` | N/A | N/A | `#0a1628` | `#0d2137` |
| 2 | `#cddc39` | `#ffe9a6` | N/A | N/A | `#050a05` | `#0a1a0a` |
| 3 | `#cddc39` | `#ffe9a6` | `#8ab4f8` | `#4a148c` | `#05081a` | `#0a0e2a` |
| 4 | `#cddc39` | `#ffe9a6` | `#8ab4f8` | `#4a148c` | `#060d06` | `#0a1a12` |
| 5 | `#cddc39` | `#ffe9a6` | `#8ab4f8` | `#4a148c` | `#08080f` | `#10101a` |
| 6 | `#cddc39` | `#ffe9a6` | `#8ab4f8` | `#4a148c` | `#0a0a12` | `#12121e` |

**Metal shader 中的颜色常量定义：**

```metal
// Target 颜色 (15Hz)
constant float3 kTargetPrimary  = float3(0.804, 0.863, 0.224);  // #cddc39
constant float3 kTargetSecondary = float3(1.000, 0.914, 0.651);  // #ffe9a6

// Distractor 颜色 (20Hz)
constant float3 kDistPrimary    = float3(0.541, 0.706, 0.973);  // #8ab4f8
constant float3 kDistSecondary  = float3(0.290, 0.078, 0.549);  // #4a148c
```

### 4.0.4 Bloom 强度表

| Level | 基础 Bloom | 专注时 Bloom (attention=1.0) | 走神时 Bloom (attention=0.0) | Bloom 半径 (px) | Bloom 阈值 |
|------:|---------:|---------------------------:|---------------------------:|---------------:|----------:|
| 1 | 0.3 | 0.8 | 0.1 | 8.0 | 0.6 |
| 2 | 0.4 | 1.0 | 0.05 | 12.0 | 0.5 |
| 3 | 0.3 | 0.9 | 0.1 | 10.0 | 0.55 |
| 4 | 0.35 | 0.9 | 0.05 | 10.0 | 0.55 |
| 5 | 0.5 | 1.2 | 0.0 | 14.0 | 0.5 |
| 6 | 0.2 | 0.7 | 0.0 | 6.0 | 0.7 |

**Bloom 后处理使用两-pass Gaussian blur：**

```metal
// Pass 1: Horizontal blur (13-tap)
// Pass 2: Vertical blur (13-tap)
// 最后与原始场景做 additive blend

// Bloom 强度由 attention 驱动的插值公式：
// currentBloom = lerp(distractedBloom, focusedBloom, smoothstep(0.2, 0.8, attention))
```

### 4.0.5 音频环境总表

| Level | 环境音类型 | Binaural 基频 | Binaural Beat | 走神音效 | 专注奖励音效 |
|------:|----------|-------------:|-------------:|---------|------------|
| 1 | 水波 + 远处虫鸣 | 200 Hz | 15 Hz | 水面冻结静音 | 颂钵泛音 (528 Hz) |
| 2 | 森林风声 + 树叶沙沙 | 200 Hz | 15 Hz | 风声加大、回声 | 风铃 (852 Hz) |
| 3 | 深空寂静 + 微弱脉冲 | 210 Hz | 15 Hz | 静电噪点 | 星辰共鸣音 (C5-E5-G5 和弦) |
| 4 | 森林夜间 + 泉水 | 200 Hz | 15 Hz | 枯叶摩擦声 | 生命之树生长音 (A3 大三和弦) |
| 5 | 暴风雨 + 雷鸣 | 190 Hz | 15 Hz | 雷声轰鸣 + 混响 | 破云音效 (明亮扫频 400→1200 Hz) |
| 6 | 极高山风 + 冰雪 | 185 Hz | 15 Hz | 呼啸风声 | 满月显现音 (低沉颂钵 136.1 Hz + 高泛音) |

---

## 4.1 Level 1: 涟漪绽放 (Ripple Bloom)

**Realm**: 觉醒 · 壹
**神经科学映射**: 持续性注意力 (Sustained Attention)
**Session 时长**: 5 分钟 (Demo) / 10 分钟 (标准)

### 4.1.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 无 |
| Advanced 频率 | 无 |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Wave 类型 | sine |
| Opacity 范围 | 0.60 ~ 1.00 |
| 刺激面积 | 屏幕中心半径 40pt 圆形区域 |
| 刺激形状 | 径向渐变圆，中心最亮 |

**刺激渲染规范：** 睡莲花蕊是一个中心点光源，向外做径向高斯衰减。15 Hz 闪烁作用于整个花蕊区域。闪烁不是 on/off 硬切换，而是 opacity 在 0.60 和 1.00 之间做正弦波动。

```metal
// Level 1 花蕊 SSVEP 刺激
float lotusGlow(float2 pos, float2 center, float uTime) {
    float dist = distance(pos, center);
    float radius = 40.0;  // pt
    float glow = exp(-dist * dist / (2.0 * radius * radius));
    float flicker = ssvepOpacity(uTime, 15.0, 0.60, 1.00);
    return glow * flicker;
}
```

### 4.1.2 视觉主题

**背景：** 深蓝色湖面。垂直渐变，从上到下：

- 顶部：`#0a1628`
- 中部：`#0d2137`
- 底部：`#0f2a3d`

湖面有微弱的波纹效果，通过 vertex shader 做 sin 波位移实现。

**主视觉元素：**

- 睡莲：屏幕正中央。初始状态为闭合花苞。花苞由 3 层花瓣组成，每层 6 片，共 18 片。
- 花苞尺寸：直径 120pt（闭合时），280pt（完全绽放时）。
- 花瓣颜色：`#cddc39` 渐变至 `#ffe9a6`。
- 花瓣材质：半透明，边缘有微弱的发光边缘光 (rim light)。

**水波纹涟漪（主粒子）：** 从花苞中心向外扩散的同心圆波纹。

- 同屏最大数量：8 个同心圆
- 每个涟漪生命周期：3.0 秒
- 生成间隔：0.375 秒（8 个 × 0.375s = 3.0s 一个完整循环）
- 扩散速度：80 pt/s
- 颜色：`#cddc39`，opacity 从 0.4 衰减到 0.0
- 线宽：2pt

```metal
// 涟漪粒子属性
struct RippleParticle {
    float2 center;    // 花苞中心
    float birthTime;  // 出生时间
    float lifetime;   // 3.0 秒
    float maxRadius;  // 240 pt (80 pt/s × 3s)
    float baseWidth;  // 2.0 pt
};

// 涟漪渲染
float rippleAlpha(float2 pos, RippleParticle ripple, float currentTime) {
    float age = currentTime - ripple.birthTime;
    float progress = age / ripple.lifetime;
    if (progress < 0.0 || progress > 1.0) return 0.0;
    
    float currentRadius = ripple.maxRadius * progress;
    float dist = distance(pos, ripple.center);
    float ringDist = abs(dist - currentRadius);
    
    float ringAlpha = exp(-ringDist * ringDist / 4.0);  // 高斯环
    float fadeOut = 1.0 - progress;                       // 衰减
    return ringAlpha * fadeOut * 0.4;
}
```

**花瓣微粒（次粒子）：** 花瓣绽放时飘散的发光微粒。

- 数量：24 个
- 仅在 attention > 0.7 时激活
- 从花瓣边缘发射，做布朗运动
- 尺寸：1-3 pt
- 颜色：`#ffe9a6`
- 生命周期：2.0 秒

**水面微光（环境粒子）：** 模拟月光在水面的反射。

- 数量：60 个
- 均匀分布在湖面区域
- 做 slow random walk（速度 <5 pt/s）
- 尺寸：1-2 pt
- 颜色：`#8ab4f8`，opacity 0.1-0.3 随机
- 不受 attention 影响

### 4.1.3 专注度反馈行为

| 状态 | Attention 范围 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|
| 专注 | > 0.7 | 花瓣逐层绽放（18片全开约需 8 秒持续专注）。涟漪颜色饱和度提升 30%。花瓣微粒激活。Bloom 强度 0.8。 | 低频丰满，颂钵泛音出现。Binaural 清晰。 |
| 中性 | 0.3-0.7 | 花瓣保持当前状态不动（既不绽放也不闭合）。涟漪正常扩散。Bloom 强度 0.3-0.5。 | 环境音正常播放，无特殊音效。 |
| 走神 | < 0.3 | 花瓣从外层向内逐层闭合。涟漪扩散速度减半至 40 pt/s。Bloom 强度降至 0.1。水面微光变暗。 | Low-pass filter 开启，cutoff 降至 400 Hz。水声"冻结"。 |

**状态转换时序：**

- 专注 → 中性：立即停止绽放动画，花瓣保持当前位置。延迟 0ms。
- 中性 → 专注：延迟 500ms（防止噪声抖动触发绽放），然后开始绽放。
- 专注 → 走神：立即开始闭合。闭合速度 = 绽放速度的 1.5 倍（快速惩罚）。
- 走神 → 中性：闭合停止。延迟 300ms。
- 走神 → 专注：闭合立即停止，延迟 800ms 后开始绽放（更长的恢复等待）。

```swift
// Level 1 专注度状态机
enum LotusState {
    case closed       // 花苞闭合
    case opening      // 正在绽放
    case fullyOpen    // 完全绽放
    case closing      // 正在闭合
}

class Level1FeedbackController {
    var lotusState: LotusState = .closed
    var bloomProgress: Float = 0.0  // 0.0 = 闭合, 1.0 = 完全绽放
    var focusHoldTimer: Float = 0.0
    var recoveryDelayTimer: Float = 0.0
    let bloomSpeed: Float = 0.125    // 1.0 / 8.0 秒
    let closeSpeed: Float = 0.1875   // bloomSpeed × 1.5
    let focusThreshold: Float = 0.7
    let distractedThreshold: Float = 0.3
    
    func update(attention: Float, deltaTime: Float) {
        switch lotusState {
        case .closed:
            if attention > focusThreshold {
                recoveryDelayTimer += deltaTime
                if recoveryDelayTimer >= 0.8 {
                    lotusState = .opening
                    recoveryDelayTimer = 0.0
                }
            } else {
                recoveryDelayTimer = 0.0
            }
            
        case .opening:
            if attention > focusThreshold {
                bloomProgress = min(1.0, bloomProgress + bloomSpeed * deltaTime)
                if bloomProgress >= 1.0 { lotusState = .fullyOpen }
            } else if attention < distractedThreshold {
                lotusState = .closing
            } else {
                // 中性：暂停绽放
            }
            
        case .fullyOpen:
            if attention < distractedThreshold {
                lotusState = .closing
            }
            
        case .closing:
            bloomProgress = max(0.0, bloomProgress - closeSpeed * deltaTime)
            if bloomProgress <= 0.0 {
                lotusState = .closed
                bloomProgress = 0.0
            }
            if attention > focusThreshold {
                recoveryDelayTimer += deltaTime
                if recoveryDelayTimer >= 0.8 {
                    lotusState = .opening
                    recoveryDelayTimer = 0.0
                }
            } else {
                recoveryDelayTimer = 0.0
            }
        }
    }
}
```

### 4.1.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 水波声 (粉红噪声低通滤波 800Hz) + 远处虫鸣 (随机 2-4kHz 短脉冲) |
| Binaural 左耳 | 200 Hz |
| Binaural 右耳 | 215 Hz |
| Binaural Beat | 15 Hz (匹配 SSVEP 频率) |
| 走神音效 | 水面冻结：环境音 low-pass cutoff 从 2000Hz 滑降至 400Hz，过渡时间 0.5s |
| 专注奖励音效 | 颂钵泛音 528 Hz，正弦波衰减，持续时间 0.8s。触发条件：attention 持续 > 0.8 达 3 秒 |
| Isochronic Tone | 15 Hz 等时音，仅在专注状态播放，走神时静音。音量 = attention × 0.15 |

### 4.1.5 关卡特殊机制

**花瓣绽放进度作为"进度条"：** `bloomProgress` 隐含了训练进度。完全绽放 = attention 持续达标 8 秒。

**涟漪节奏同步：** 涟漪生成间隔在专注时缩短至 0.3s（更密集），走神时延长至 0.6s（更稀疏）。

```swift
let rippleInterval = attention > 0.7 ? 0.3 : (attention < 0.3 ? 0.6 : 0.375)
```

### 4.1.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽自动结束（无提前退出） |
| 核心指标 | 平均 attention > 0.5 即为"通过" |
| 进阶指标 | 完全绽放次数（bloomProgress 达到 1.0 的次数） |
| 评级基准 | >=3 次完全绽放 = ★★★，>=5 次 = ★★★★，>=8 次 = ★★★★★ |

---

## 4.2 Level 2: 萤火引路 (Firefly Guide)

**Realm**: 觉醒 · 贰
**神经科学映射**: 视觉耐力与疲劳阈值测试
**Session 时长**: 5 分钟 (Demo) / 10 分钟 (标准)

### 4.2.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 无 |
| Advanced 频率 | 无 |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Wave 类型 | sine |
| Opacity 范围 | 0.55 ~ 1.00 |
| 刺激面积 | 40 个萤火虫粒子，每个直径 6-10 pt |
| 刺激形状 | 高斯发光圆点 |

**萤火虫 SSVEP 刺激：** 每只萤火虫是一个独立的高斯发光点，所有萤火虫共享同一个 15 Hz 正弦闪烁相位（同频同相）。这意味着它们同时亮起、同时变暗，形成群体呼吸感。

```metal
// 单只萤火虫渲染
float fireflyGlow(float2 pos, float2 fireflyPos, float fireflySize, float uTime) {
    float dist = distance(pos, fireflyPos);
    float glow = exp(-dist * dist / (2.0 * fireflySize * fireflySize));
    float flicker = ssvepOpacity(uTime, 15.0, 0.55, 1.00);
    return glow * flicker;
}
```

### 4.2.2 视觉主题

**背景：** 黑森林。垂直渐变：

- 顶部：`#050a05`（近乎纯黑的深绿）
- 底部：`#0a1a0a`（微弱的森林绿）

背景有极暗的树干剪影，使用预渲染的 silhouette texture（无需实时计算）。

**主视觉元素：**

- 萤火虫群：40 只萤火虫，初始分布在屏幕中央偏上区域（可见范围的上 60%）。
- 萤火虫运动：Perlin noise 驱动的平滑随机游走，速度 15-30 pt/s。
- 萤火虫尺寸：6-10 pt（高斯分布，均值 8pt，标准差 1.5pt）。
- 萤火虫颜色：`#cddc39` 核心 + `#ffe9a6` 外晕。
- 光照半径：每只萤火虫照亮半径 60pt 的圆形区域（作为迷雾的"光源"）。

- 古老石碑：屏幕中下方。矩形，宽 80pt × 高 120pt。
- 石碑材质：深灰岩石色 `#2a2a2a`，表面有隐约的符文纹理。
- 符文在 attention 持续 > 0.7 时逐个点亮，颜色为 `#ffe9a6`。

**萤火虫光点尾迹（次粒子）：** 每只萤火虫拖拽 3 条尾迹。

- 总尾迹数：40 × 3 = 120 个粒子
- 尾迹生命周期：0.5 秒
- 尾迹跟随萤火虫历史位置
- 尺寸：从 4pt 衰减到 0pt
- 颜色：`#ffe9a6`，opacity 从 0.3 衰减到 0.0

**迷雾粒子（环境粒子）：** 全屏迷雾效果。

- 数量：200 个
- 大尺寸半透明粒子（30-80 pt）
- 颜色：`#0a1a0a`，opacity 0.3-0.6
- 运动：极慢水平漂移（2-5 pt/s）
- 受 attention 控制：attention 越高，迷雾 opacity 越低

```metal
// 迷雾浓度由 attention 驱动
float fogOpacity(float baseFog, float attention) {
    float clearFactor = smoothstep(0.2, 0.7, attention);
    return baseFog * (1.0 - clearFactor * 0.8);  // 最多清除 80% 迷雾
}
```

### 4.2.3 专注度反馈行为

| 状态 | Attention 范围 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|
| 专注 | > 0.7 | 萤火虫亮度增强（opacity 上限从 1.0 提升至 1.0 + bloom 叠加）。光照半径从 60pt 扩大到 100pt。迷雾被驱散（clearFactor=0.8）。石碑符文逐个点亮。 | 风铃声出现（852 Hz 正弦衰减）。森林环境音通透。 |
| 中性 | 0.3-0.7 | 萤火虫正常亮度。光照半径 60pt。迷雾部分存在。石碑符文保持当前状态。 | 森林风声正常。 |
| 走神 | < 0.3 | 萤火虫亮度下降（opacity 下限从 0.55 降至 0.30）。光照半径缩小至 30pt。迷雾重新合拢（clearFactor=0.0）。石碑符文逐个熄灭。视距缩短（画面四周出现暗角 vignette）。 | 风声加大，加入回声混响。Low-pass cutoff 降至 600 Hz。 |

**迷雾驱散效果的核心实现：**

迷雾不是简单的透明度变化。萤火虫的光照在迷雾中"开辟"一个圆形可见区域。使用一个离屏 render target：

1. 在离屏 texture 上渲染萤火虫光照图（每个萤火虫画一个径向渐变圆）
2. 对光照图做 blur
3. 在最终合成时，迷雾 texture 的 alpha 乘以 `(1.0 - lightMap)`

```metal
// 迷雾合成
float4 compositeFog(float4 fogColor, float4 lightMap, float4 sceneColor, float fogBaseAlpha) {
    float light = lightMap.r;  // 光照强度 0.0-1.0
    float fogAlpha = fogBaseAlpha * (1.0 - light * 0.85);
    return mix(sceneColor, fogColor, fogAlpha);
}
```

### 4.2.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 森林风声 (粉红噪声 200-800Hz 带通) + 树叶沙沙声 (白噪声高频分量 3-6kHz) |
| Binaural 左耳 | 200 Hz |
| Binaural 右耳 | 215 Hz |
| Binaural Beat | 15 Hz |
| 走神音效 | 风声加大 + 回声混响 (reverb wet/dry 从 0.2 增加到 0.8) |
| 专注奖励音效 | 风铃 852 Hz 正弦衰减 0.6s。触发：attention 持续 > 0.75 达 5 秒 |
| Isochronic Tone | 15 Hz，专注时播放 |

### 4.2.5 关卡特殊机制

**石碑解密进度：** 石碑上有 7 个符文。每个符文需要 attention 持续 > 0.7 达 3 秒才能点亮。7 个全部点亮 = 石碑完全解密。

```swift
// 石碑符文进度追踪
class SteleProgress {
    var litRunes: Int = 0
    var currentRuneTimer: Float = 0.0
    let runeRequirement: Float = 3.0  // 秒
    
    func update(attention: Float, deltaTime: Float) {
        if attention > 0.7 && litRunes < 7 {
            currentRuneTimer += deltaTime
            if currentRuneTimer >= runeRequirement {
                litRunes += 1
                currentRuneTimer = 0.0
                // 触发符文点亮音效
            }
        } else {
            currentRuneTimer = max(0, currentRuneTimer - deltaTime * 0.5)
        }
    }
}
```

**视觉耐力衰减：** 随着时间推移，萤火虫的 SSVEP opacity 下限逐渐降低（模拟视觉疲劳），从 0.55 降至 0.40。这条曲线在 session 的 70% 时间点达到最低，之后不再下降。

```swift
let fatigueFloor = 0.55 - 0.15 * smoothstep(0.0, 0.7, sessionProgress)
```

### 4.2.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽 |
| 核心指标 | 石碑解密进度（0-7 个符文） |
| 进阶指标 | 平均 attention > 0.5 |
| 评级基准 | >=3 符文 = ★★★，>=5 符文 = ★★★★，7 符文 = ★★★★★ |

---

## 4.3 Level 3: 星图寻迹 (Star Map)

**Realm**: 共鸣 · 壹
**神经科学映射**: 转移性注意力 (Alternating Attention)
**Session 时长**: 5 分钟 (Demo) / 12 分钟 (标准)

### 4.3.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 20 Hz |
| Advanced 频率 | 无 |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Distractor 颜色 | `#8ab4f8` (主), `#4a148c` (辅) |
| Target Wave | sine, opacity 0.55-1.00 |
| Distractor Wave | sine, opacity 0.40-0.85 |
| Target 形状 | 圆形高斯发光点，直径 10-14pt |
| Distractor 形状 | 较小圆形，直径 4-7pt |
| Target 数量 | 1（当前激活的主星） |
| Distractor 数量 | 70-80（背景繁星） |

**双频同时闪烁：** 这是首次引入 20 Hz 干扰的关卡。背景繁星以 20 Hz 闪烁（蓝色），当前目标主星以 15 Hz 闪烁（黄绿色）。用户必须在蓝色繁星的视觉干扰中锁定并注视黄绿色主星。

**目标主星轮换机制：** 星座由 5 个主星节点组成。完成一个节点后，自动切换到下一个。切换时有 1.5 秒的过渡动画。

```swift
// 主星切换状态
struct StarNode {
    let id: Int
    let position: CGPoint  // 屏幕坐标
    let connectedTo: Int?  // 下一个节点的 ID，nil 表示终点
}

// 预设的星座路径（5 个节点）
let constellationPath: [StarNode] = [
    StarNode(id: 0, position: CGPoint(x: 0.2, y: 0.3), connectedTo: 1),
    StarNode(id: 1, position: CGPoint(x: 0.35, y: 0.2), connectedTo: 2),
    StarNode(id: 2, position: CGPoint(x: 0.5, y: 0.35), connectedTo: 3),
    StarNode(id: 3, position: CGPoint(x: 0.65, y: 0.25), connectedTo: 4),
    StarNode(id: 4, position: CGPoint(x: 0.8, y: 0.4), connectedTo: nil),
]
// 坐标为屏幕比例值，渲染时乘以实际屏幕尺寸
```

### 4.3.2 视觉主题

**背景：** 深空星夜。径向渐变：

- 中心：`#0a0e2a`（深蓝紫）
- 边缘：`#05081a`（近乎纯黑）

**主视觉元素：**

- 背景繁星（distractor）：80 颗，均匀随机分布。
- 20 Hz 闪烁，颜色 `#8ab4f8`，直径 4-7pt。
- 微弱的随机闪烁（每颗星有独立的随机 phase offset，避免同步感）。

- 目标主星（target）：当前激活的 1 颗。
- 15 Hz 闪烁，颜色 `#cddc39`，直径 12pt。
- 比 distractor 大 2-3 倍，颜色明显不同。
- 激活时有脉动光环效果（半径 20pt，频率 2 Hz）。

- 星座连线：已完成的节点之间有发光连线。
- 线宽 2pt，颜色 `#ffe9a6`，opacity 0.6。
- 连线有"流动"效果（沿线移动的光点，速度 100 pt/s）。

**暗星背景（环境粒子）：** 极暗的静态小点，增加星空深度感。

- 数量：300 个
- 直径 1-2pt
- 颜色：`#ffffff`，opacity 0.05-0.15
- 完全静态，不做任何运动

### 4.3.3 专注度反馈行为

| 状态 | Attention 范围 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|
| 专注 | > 0.7 | 当前主星光芒增强，连线进度推进。连线到下一节点时，当前节点爆出强光（`#ffe9a6` 全屏 flash 0.3s）。已连线部分发光增强。 | 星辰共鸣音（C5-E5-G5 和弦，持续 0.5s）。深空环境音通透。 |
| 中性 | 0.3-0.7 | 主星正常闪烁。连线进度不变（既不推进也不回退）。 | 深空寂静。 |
| 走神 | < 0.3 | 主星光芒减弱。**连线断裂风险**：走神超过 5 秒，最新一段连线开始闪烁（红色 overlay），走神超过 8 秒，连线断裂（需要重新注视当前节点重建）。 | 静电噪点出现（白噪声 burst，0.2s）。Binaural 音量降低。 |

**连线进度机制：**

```swift
class ConstellationProgress {
    var currentNode: Int = 0           // 当前需要注视的节点 (0-4)
    var completedNodes: Set<Int> = []  // 已完成的节点
    var connectionStrength: Float = 0.0 // 当前连线的能量 0.0-1.0
    var distractionTimer: Float = 0.0  // 走神计时器
    
    let connectionRate: Float = 0.2    // 每秒积累 0.2，5 秒完成一条连线
    let breakThreshold: Float = 8.0    // 走神 8 秒断线
    let warningThreshold: Float = 5.0  // 走神 5 秒预警
    
    func update(attention: Float, deltaTime: Float) -> StarMapEvent? {
        var event: StarMapEvent?
        
        if attention > 0.7 {
            distractionTimer = 0.0
            connectionStrength = min(1.0, connectionStrength + connectionRate * deltaTime)
            
            if connectionStrength >= 1.0 {
                // 连线完成，切换到下一节点
                completedNodes.insert(currentNode)
                if let next = constellationPath[currentNode].connectedTo {
                    currentNode = next
                    connectionStrength = 0.0
                    event = .connectionComplete
                } else {
                    event = .constellationComplete  // 全部完成
                }
            }
        } else {
            connectionStrength = max(0.0, connectionStrength - deltaTime * 0.1)
            
            if attention < 0.3 {
                distractionTimer += deltaTime
                if distractionTimer >= breakThreshold && !completedNodes.isEmpty {
                    // 断线！回退到上一个未完成的节点
                    event = .connectionBroken
                    // 重新计算当前节点
                    for i in stride(from: currentNode, through: 0, by: -1) {
                        if !completedNodes.contains(i) || i == 0 {
                            currentNode = i
                            break
                        }
                    }
                    connectionStrength = 0.0
                    distractionTimer = 0.0
                } else if distractionTimer >= warningThreshold {
                    event = .connectionWarning  // 连线闪烁预警
                }
            } else {
                distractionTimer = max(0.0, distractionTimer - deltaTime * 2.0)
            }
        }
        
        return event
    }
}

enum StarMapEvent {
    case connectionComplete   // 一条连线完成
    case connectionBroken     // 连线断裂
    case connectionWarning    // 连线即将断裂（红色闪烁）
    case constellationComplete // 星座全部完成
}
```

### 4.3.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 深空寂静 (极低音量粉红噪声 100-300Hz) + 微弱脉冲 (每 4 秒一次的低频 thump, 60Hz, 0.2s) |
| Binaural 左耳 | 210 Hz |
| Binaural 右耳 | 225 Hz |
| Binaural Beat | 15 Hz |
| 走神音效 | 静电噪点 (白噪声 burst, 0.2s, 每 3 秒一次) |
| 专注奖励音效 | 星辰共鸣音：C5(523Hz) + E5(659Hz) + G5(784Hz) 大三和弦正弦波叠加，衰减 0.5s |
| 连线断裂音效 | 低沉不和谐音 (C2 + Db2, 0.3s) |
| Isochronic Tone | 15 Hz，专注时播放 |

### 4.3.5 关卡特殊机制

**星座完成后灵兽出现：** 5 条连线全部完成后，星座区域发出强光，然后"光之灵兽"从星座中跃出。灵兽是一个由粒子组成的半透明形态（约 200 个粒子组成轮廓），在屏幕中央做缓慢旋转运动 5 秒后消散。这段动画期间 attention 不再被追踪。

**注意力转移难度：** 每完成一个节点，下一个节点的位置距离上一个更远，且周围的 distractor 繁星密度增加。

### 4.3.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽 |
| 核心指标 | 星座完成进度（0-5 个节点） |
| 进阶指标 | 断线次数 |
| 评级基准 | >=3 节点 = ★★★，>=4 节点 = ★★★★，5 节点 0 断线 = ★★★★★ |

---

## 4.4 Level 4: 真假萤火 (True/False Fireflies)

**Realm**: 共鸣 · 贰
**神经科学映射**: 选择性注意与冲动抑制 (Active Inhibition)
**Session 时长**: 5 分钟 (Demo) / 12 分钟 (标准)

### 4.4.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 20 Hz |
| Advanced 频率 | 无 |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Distractor 颜色 | `#8ab4f8` (主), `#4a148c` (辅) |
| Target Wave | sine, opacity 0.55-1.00 |
| Distractor Wave | sine, opacity 0.45-0.90 |
| Target 数量 | 25 (黄绿萤火) |
| Distractor 数量 | 25 (幽蓝萤火) |

**关键区别：** 两类萤火虫同时在场，混合飞行。用户必须注视黄绿萤火（15Hz），同时抑制对幽蓝萤火（20Hz）的注视冲动。

**色盲安全设计：** 除了颜色差异外，两类萤火虫还有以下区分维度：

| 维度 | Target (黄绿) | Distractor (幽蓝) |
|------|:------------:|:-----------------:|
| 颜色 | `#cddc39` | `#8ab4f8` |
| 形状 | 圆形 | 菱形（45° 旋转的正方形） |
| 尺寸 | 8-12 pt | 5-8 pt |
| 运动模式 | 缓慢漂浮 (15-25 pt/s) | 快速闪烁抖动 (30-50 pt/s) |
| 闪烁频率 | 15 Hz (慢) | 20 Hz (快) |

```metal
// 渲染菱形 distractor 萤火虫
float diamondFirefly(float2 pos, float2 center, float size, float uTime) {
    // 旋转 45° 的正方形 SDF
    float2 d = abs(pos - center);
    float2 rotated = float2(d.x + d.y, d.x - d.y) * 0.707;
    float box = max(rotated.x - size, rotated.y - size);
    float shape = 1.0 - smoothstep(-1.0, 1.0, box);
    
    float glow = exp(-box * box / (2.0 * size * size));
    float flicker = ssvepOpacity(uTime, 20.0, 0.45, 0.90);
    return (shape * 0.5 + glow * 0.5) * flicker;
}
```

### 4.4.2 视觉主题

**背景：** 夜间森林，比 Level 2 更暗。

- 顶部：`#060d06`
- 底部：`#0a1a12`

有暗色树干剪影和极暗的树叶纹理（pre-rendered）。

**主视觉元素：**

- 黄绿萤火（target）：25 只，Perlin noise 驱动，缓慢漂浮。
- 幽蓝萤火（distractor）：25 只，更快的随机运动，偶尔会"飞向"黄绿萤火（模拟干扰行为）。

- 生命之树：屏幕中央下方。初始状态为枯树干。
- 树干尺寸：宽 30pt × 高 200pt。
- 树枝有 5 个分支点，每个分支点对应一棵"叶子簇"。
- 枯萎状态颜色：`#3a2a1a`（枯褐色）。
- 生长状态颜色：`#4CAF50`（生机绿）渐变至 `#cddc39`（荧光绿）。
- 树的生长高度随"竞争指数"从 0 增长到 100%。

**树叶粒子（环境粒子）：** 从树冠飘落的叶子。

- 数量：80 个
- 做慢速下落 + 水平摆动（正弦波叠加）
- 尺寸：3-6pt
- 颜色：枯叶 `#5a3a1a` / 生叶 `#4CAF50`，比例取决于树的生命力

### 4.4.3 专注度反馈行为

本关卡的反馈机制不同于前几关。核心概念是**竞争指数 (Competition Index)**，衡量用户注视 target 的程度相对于被 distractor 吸引的程度。

```swift
// 竞争指数计算
// 这不是简单的 attention 值，而是 target SSVEP 能量 / (target + distractor 总能量)
// 在模拟器中，我们用一个近似公式：
var competitionIndex: Float {
    // attention 高 = 竞争指数高（说明成功抑制了干扰）
    // 注意力噪声中有"被干扰"的分量
    return smoothstep(0.2, 0.8, currentAttention)
}
```

| 状态 | Attention 范围 | 竞争指数 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|---------|
| 专注 | > 0.7 | > 0.6 | 树木生长：枝叶展开，叶子变绿。黄绿萤火聚集到树冠。幽蓝萤火被"排斥"到画面边缘。 | 生命之树生长音（A3 大三和弦 220Hz + 277Hz + 330Hz）。森林环境音丰富。 |
| 中性 | 0.3-0.7 | 0.3-0.6 | 树木保持当前状态。两类萤火均匀分布。 | 环境音正常。 |
| 走神 | < 0.3 | < 0.3 | **树木枯萎**：绿色褪去变为枯褐色。幽蓝萤火聚集到树周围（"侵蚀"效果）。黄绿萤火散开。画面整体变冷色调（color temperature shift）。 | 枯叶摩擦声。Low-pass cutoff 降至 500Hz。不和谐音。 |

**枯萎/生长状态转换：**

树木的生命力值 (`treeVitality`) 从 0.0（枯死）到 1.0（完全生长）。这个值驱动树木的视觉表现。

```swift
class TreeVitalityController {
    var vitality: Float = 0.0  // 0.0 = 枯死, 1.0 = 完全生长
    
    func update(attention: Float, deltaTime: Float) {
        let competition = smoothstep(0.2, 0.8, attention)
        
        if competition > 0.6 {
            // 专注：树生长
            let growRate = (competition - 0.6) * 0.5  // 最快 0.2/s
            vitality = min(1.0, vitality + growRate * deltaTime)
        } else if competition < 0.3 {
            // 走神：树枯萎
            let witherRate = (0.3 - competition) * 0.8  // 最快 0.24/s
            vitality = max(0.0, vitality - witherRate * deltaTime)
        }
        // 中性区域：不生长也不枯萎
    }
}
```

**颜色温度偏移：** 走神时整个画面色温向冷色偏移。

```metal
// 色温偏移 shader
float3 colorTemperatureShift(float3 color, float coldFactor) {
    // coldFactor: 0.0 = 正常, 1.0 = 最冷
    float3 coldTint = float3(0.7, 0.8, 1.0);
    float3 warmTint = float3(1.0, 0.95, 0.85);
    float3 tint = mix(warmTint, coldTint, coldFactor);
    return color * tint;
}

// coldFactor 由 attention 驱动
// attention < 0.3 → coldFactor = smoothstep(0.3, 0.1, attention)
```

### 4.4.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 森林夜间 (风声 + 泉水 + 远处猫头鹰) |
| Binaural 左耳 | 200 Hz |
| Binaural 右耳 | 215 Hz |
| Binaural Beat | 15 Hz |
| 走神音效 | 枯叶摩擦声 (噪声 burst, 2-4kHz, 0.3s) + 不和谐音 |
| 专注奖励音效 | A3 大三和弦 (220+277+330Hz)，正弦波叠加，衰减 0.6s。触发：vitality 从 <0.5 增长到 >0.5 |
| Isochronic Tone | 15 Hz，专注时播放 |

### 4.4.5 关卡特殊机制

**幽蓝萤火主动干扰：** 每 10-20 秒，1-3 只幽蓝萤火会主动飞向画面中央（树的位置），模拟"干扰注意力"的行为。这个运动在 attention 下降时更频繁。

```swift
// distractor 萤火的主动干扰行为
func shouldDistractorAttack(attention: Float, timeSinceLastAttack: Float) -> Bool {
    let baseInterval: Float = attention < 0.3 ? 10.0 : 20.0
    return timeSinceLastAttack >= baseInterval
}
```

**生命力可视化：** `treeVitality` 映射到树的视觉表现：

| vitality 范围 | 树的状态 | 叶子颜色 | 分支可见度 |
|-------------|---------|---------|----------|
| 0.0-0.2 | 枯桩 | 无叶子 | 仅主干 |
| 0.2-0.4 | 萌芽 | `#5a3a1a` 枯叶 | 1-2 个分支 |
| 0.4-0.6 | 生长中 | `#5a3a1a` → `#4CAF50` 渐变 | 3-4 个分支 |
| 0.6-0.8 | 茂盛 | `#4CAF50` 生叶 | 全部 5 个分支 |
| 0.8-1.0 | 繁花 | `#4CAF50` + `#cddc39` 花朵 | 全部分支 + 花朵粒子 |

### 4.4.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽 |
| 核心指标 | 最终 vitality 值 |
| 进阶指标 | vitality > 0.8 的累计时长 |
| 评级基准 | vitality >= 0.4 = ★★★，>= 0.6 = ★★★★，>= 0.8 = ★★★★★ |

---

## 4.5 Level 5: 飞燕破云 (Swallow Breaks Clouds)

**Realm**: 心流 · 壹
**神经科学映射**: 平滑追踪眼动 (Smooth Pursuit)
**Session 时长**: 5 分钟 (Demo) / 15 分钟 (标准)

### 4.5.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 20 Hz |
| Advanced 频率 | 无 |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Distractor 颜色 | `#8ab4f8` (主), `#4a148c` (辅) |
| Target Wave | sine, opacity 0.50-1.00 |
| Distractor Wave | sine + pulse (20Hz 正弦叠加 3Hz 脉冲), opacity 0.40-0.90 |
| Target 形状 | 灵燕（由 30 个光羽粒子组成的鸟形轮廓） |
| Distractor 形状 | 雷云团（大面积低 opacity 闪烁区域） |

**动态目标追踪：** 灵燕在屏幕上做平滑的飞行运动，用户需要持续追踪灵燕的位置。这是第一个要求"追踪运动目标"的关卡。

**灵燕运动轨迹：** 使用多频率正弦波叠加产生李萨如 (Lissajous) 曲线：

```swift
// 灵燕运动轨迹（归一化坐标 0.0-1.0）
func swallowPosition(time: Float) -> CGPoint {
    let x = 0.5 + 0.25 * sin(time * 0.3) + 0.1 * sin(time * 0.7)
    let y = 0.5 + 0.2 * cos(time * 0.4) + 0.08 * cos(time * 0.9)
    return CGPoint(x: CGFloat(x), y: CGFloat(y))
}
```

灵燕运动速度约 40-80 pt/s，不会突然变速（加速度平滑）。

### 4.5.2 视觉主题

**背景：** 暴风雨夜空。

- 顶部：`#08080f`（几乎纯黑）
- 底部：`#10101a`（微弱的深蓝灰）

背景有流动的雨幕效果。

**主视觉元素：**

- 灵燕：由 30 个光羽粒子组成的鸟形轮廓。
- 整体尺寸约 40pt × 20pt（展翅）。
- 光羽粒子沿翅膀边缘分布，形成翅膀轮廓。
- 核心发光点：`#cddc39`，外晕 `#ffe9a6`。
- 15 Hz 闪烁作用于整个灵燕。
- 飞行方向有尾迹拖拽效果。

- 雷云（distractor）：3-5 个雷云团分布在灵燕飞行路径的周围。
- 每个雷云团直径 80-150pt。
- 20 Hz 闪烁 + 3Hz 脉冲（模拟雷电）。
- 颜色：`#8ab4f8` 边缘 + `#4a148c` 核心。
- 低 opacity（0.15-0.35），不会遮挡灵燕，但视觉上足够"抢眼"。

**灵燕光羽尾迹（次粒子）：** 30 个粒子组成尾迹。

- 每个粒子从灵燕当前位置释放
- 生命周期：0.8 秒
- 做减速 + 向下飘落运动
- 尺寸：从 4pt 衰减到 1pt
- 颜色：`#ffe9a6`，opacity 从 0.6 衰减到 0.0

**雨滴（环境粒子）：** 倾斜的雨幕。

- 数量：150 个
- 从屏幕顶部生成，做斜向下运动（角度约 15° 偏垂直）
- 速度：300-400 pt/s
- 长度：8-15pt（运动模糊效果的线条）
- 颜色：`#8ab4f8`，opacity 0.1-0.2
- 不受 attention 影响（始终存在，营造暴风雨氛围）

**雷电碎片（环境粒子）：** 雷云放电时产生的碎片。

- 数量：40 个（仅在雷电脉冲时激活）
- 从雷云中心爆发
- 速度：100-200 pt/s，径向发射
- 生命周期：0.3 秒
- 颜色：`#ffffff`，opacity 0.8 → 0.0

### 4.5.3 专注度反馈行为

| 状态 | Attention 范围 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|
| 专注 | > 0.7 | 视角平稳飞行，灵燕光芒增强。雷云自动散开（远离灵燕飞行路径）。雨幕变稀疏。Bloom 强度 1.2。 | 破云音效（扫频 400→1200Hz）。雷声减弱。 |
| 中性 | 0.3-0.7 | 正常飞行。雷云保持距离。雨幕正常密度。 | 暴风雨环境音正常。 |
| 走神 | < 0.3 | **剧烈颠簸**：视角抖动（±20pt 随机偏移，频率 5Hz）。画面模糊（径向模糊 shader，强度 2-4px）。雷云逼近灵燕。雨幕加密。 | 雷声轰鸣。Low-pass cutoff 降至 300Hz。画面震动音效。 |

**视角抖动实现：**

走神时不是简单地移动整个场景，而是通过 vertex shader 对所有顶点施加高频随机偏移：

```metal
// 走神时的视角抖动
// uniform float uShakeIntensity; // 0.0 = 无抖动, 1.0 = 最大抖动

vertex VertexOutput vertexShake(VertexInput in [[stage_in]],
                                constant VertexUniforms &uniforms [[buffer(0)]]) {
    VertexOutput out;
    float2 shakeOffset = float2(0.0);
    
    if (uniforms.uShakeIntensity > 0.01) {
        // 5Hz 正弦 + 随机噪声
        float shakeX = sin(uniforms.uTime * 31.4) * 15.0 * uniforms.uShakeIntensity;
        float shakeY = cos(uniforms.uTime * 28.3) * 10.0 * uniforms.uShakeIntensity;
        shakeOffset = float2(shakeX, shakeY);
    }
    
    out.position = float4(in.position.xy + shakeOffset, in.position.zw);
    // ... 其他 vertex 变换
    return out;
}
```

**径向模糊实现：** 走神时对最终画面施加径向模糊（从屏幕中心向外辐射的 motion blur）：

```metal
// 径向模糊 fragment shader
// uniform float uBlurStrength; // 0.0-4.0 px

float4 radialBlurFragment(VertexOutput in [[stage_in]],
                           texture2d<float> sceneTexture [[texture(0)]],
                           constant FragmentUniforms &uniforms [[buffer(0)]]) {
    float2 center = float2(uniforms.screenWidth, uniforms.screenHeight) * 0.5;
    float2 dir = in.position.xy - center;
    float dist = length(dir);
    dir = normalize(dir);
    
    float4 color = float4(0.0);
    int samples = 8;
    for (int i = 0; i < samples; i++) {
        float t = float(i) / float(samples - 1);
        float2 offset = dir * t * uniforms.uBlurStrength;
        color += sceneTexture.sample(sceneSampler, (in.position.xy + offset) / uniforms.screenSize);
    }
    return color / float(samples);
}
```

**抖动强度和模糊强度的 attention 映射：**

```swift
let shakeIntensity = attention < 0.3 ? smoothstep(0.3, 0.0, attention) : 0.0
let blurStrength = attention < 0.3 ? smoothstep(0.3, 0.1, attention) * 4.0 : 0.0
```

### 4.5.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 暴风雨 (雨声 + 远雷 + 风) |
| Binaural 左耳 | 190 Hz |
| Binaural 右耳 | 205 Hz |
| Binaural Beat | 15 Hz |
| 走神音效 | 雷声轰鸣 (低频 50-100Hz noise burst, 0.5s) + 画面震动音效 |
| 专注奖励音效 | 破云音效：从 400Hz 扫频到 1200Hz 的正弦波，持续 0.8s，带 reverb |
| Isochronic Tone | 15 Hz，专注时播放。走神时音量降至 0。 |

### 4.5.5 关卡特殊机制

**动态难度调整：** 灵燕飞行速度随 session 进度递增。

```swift
// 灵燕速度随时间增加
let speedMultiplier = 1.0 + sessionProgress * 0.5  // 1.0x → 1.5x
```

**雷云逼近行为：** 走神时雷云会缓慢向灵燕位置移动（模拟"被雷云追上"的紧迫感）。恢复专注后雷云退回原位。

```swift
// 雷云位置插值
let targetCloudOffset = attention < 0.3 ? 
    float2(30.0, 20.0) * (1.0 - attention / 0.3) :  // 靠近灵燕
    float2(0.0)                                      // 退回原位
    
currentCloudOffset = lerp(currentCloudOffset, targetCloudOffset, deltaTime * 0.5)
```

### 4.5.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽 |
| 核心指标 | 平均 attention > 0.4 |
| 进阶指标 | 最长连续专注时长 (seconds) |
| 评级基准 | avg > 0.4 = ★★★，avg > 0.5 且无 > 5s 走神 = ★★★★，avg > 0.6 且无 > 3s 走神 = ★★★★★ |

---

## 4.6 Level 6: 流星试炼 (Meteor Trial)

**Realm**: 心流 · 贰
**神经科学映射**: 顶级的执行控制 (Executive Control)
**Session 时长**: 5 分钟 (Demo) / 15 分钟 (标准)

### 4.6.1 SSVEP 配置

| 参数 | 值 |
|------|---|
| Target 频率 | 15 Hz |
| Distractor 频率 | 20 Hz |
| Advanced 频率 | 40 Hz (RIFT mode) |
| Target 颜色 | `#cddc39` (主), `#ffe9a6` (辅) |
| Distractor 颜色 | `#8ab4f8` (主), `#4a148c` (辅) |
| Target Wave | sine, opacity 0.50-1.00 |
| Distractor Wave | sine, opacity 0.40-0.85 |
| Advanced Wave | 高频微脉动 (40Hz), opacity 变化幅度仅 0.08 (0.46-0.54) |
| Target 位置 | 屏幕正上方 1/3 处，固定不动 |
| Distractor 位置 | 随机突发出现（流星、极光、飞鸟） |

**三频同时刺激：** 这是全应用唯一使用三个频率的关卡。40 Hz RIFT 频率的 opacity 变化极小（仅 8% 振幅），人眼几乎不可感知，但 EEG 算法可以检测到。这个频率编码在"极光"效果中。

**40 Hz RIFT 刺激规范：** RIFT (Reduced-Intensity Flicker Training) 模式下，40 Hz 闪烁的振幅极低，用户不会感觉到明显的频闪。这是"第三境：明心"解锁后的高级体验。

```metal
// RIFT mode 40Hz 刺激 — 人眼几乎不可见
float riftOpacity(float uTime) {
    // 40Hz 正弦波，振幅仅 ±0.04（从 0.46 到 0.54）
    float phase = sin(uTime * 40.0 * 2.0 * M_PI_F);
    return 0.50 + phase * 0.04;
}
```

### 4.6.2 视觉主题

**背景：** 极简雪山夜空。极致的极简主义，减少一切视觉噪音。

- 顶部 2/3：`#0a0a12`（近黑色，带微弱蓝调）
- 底部 1/3：`#12121e`（稍亮的深灰蓝，代表雪山）

雪山剪影在底部 1/3 区域，使用 pre-rendered silhouette。只有山的轮廓线，无细节。

**主视觉元素：**

- 主星（target）：屏幕上方 1/3 居中位置。固定不动。
- 初始状态：直径 8pt 的小星。
- 随着持续专注，逐渐变大为满月（最大直径 80pt）。
- 15 Hz 闪烁，颜色 `#cddc39` 核心 + `#ffe9a6` 光晕。
- 光晕半径 = 当前直径 × 2。

- 极光 (RIFT 载体)：屏幕上方 1/2 区域的缓慢波动光带。
- 40 Hz RIFT 编码在极光的 opacity 微脉动中。
- 极光颜色：`#8ab4f8` → `#4a148c` 渐变。
- 极光不是 distractor，而是 RIFT 频率的载体。但在视觉上它足够美，可能分散用户注意力。

**流星尾焰（突发 distractor）：** 随机从屏幕边缘划过的流星。

- 触发条件：每 8-15 秒随机出现一颗
- 运动轨迹：从随机边缘位置以 45° 角划过
- 速度：500-800 pt/s
- 尾焰长度：100-200pt（运动模糊）
- 颜色：`#8ab4f8` 核心 + `#ffffff` 亮头
- 持续时间：0.3-0.5 秒
- 20 Hz 闪烁编码在流星的头部

```swift
// 流星生成逻辑
struct Meteor {
    let startPosition: CGPoint
    let direction: CGFloat      // 角度，45° ± 15°
    let speed: CGFloat           // 500-800 pt/s
    let lifetime: TimeInterval  // 0.3-0.5 秒
    let birthTime: TimeInterval
}

func generateMeteor(screenSize: CGSize) -> Meteor {
    // 从屏幕四边随机选一边
    let edge = Int.random(in: 0..<4)
    var start: CGPoint
    var angle: CGFloat
    
    switch edge {
    case 0: // 顶部
        start = CGPoint(x: CGFloat.random(in: 0...screenSize.width), y: 0)
        angle = .pi / 4 + CGFloat.random(in: -0.26...0.26)
    case 1: // 右侧
        start = CGPoint(x: screenSize.width, y: CGFloat.random(in: 0...screenSize.height * 0.5))
        angle = .pi * 3/4 + CGFloat.random(in: -0.26...0.26)
    case 2: // 底部（很少用）
        start = CGPoint(x: CGFloat.random(in: 0...screenSize.width), y: screenSize.height * 0.3)
        angle = -.pi / 4 + CGFloat.random(in: -0.26...0.26)
    default: // 左侧
        start = CGPoint(x: 0, y: CGFloat.random(in: 0...screenSize.height * 0.5))
        angle = -.pi / 4 + CGFloat.random(in: -0.26...0.26)
    }
    
    return Meteor(
        startPosition: start,
        direction: angle,
        speed: CGFloat.random(in: 500...800),
        lifetime: TimeInterval(Double.random(in: 0.3...0.5)),
        birthTime: Date().timeIntervalSince1970
    )
}
```

**极光波纹（环境效果，非粒子）：** 使用 fragment shader 直接计算，不消耗粒子 budget。

```metal
// 极光 fragment shader（直接在背景 pass 中计算）
float aurora(float2 uv, float uTime) {
    float y = uv.y;
    if (y > 0.6) return 0.0;  // 仅在上方 60% 区域
    
    // 多层正弦波叠加产生流动效果
    float wave1 = sin(uv.x * 3.0 + uTime * 0.5) * 0.5 + 0.5;
    float wave2 = sin(uv.x * 5.0 - uTime * 0.3 + 1.0) * 0.5 + 0.5;
    float wave3 = sin(uv.x * 7.0 + uTime * 0.7 + 2.0) * 0.5 + 0.5;
    
    float auroraShape = wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2;
    
    // 垂直方向的渐变（上亮下暗）
    float verticalFade = smoothstep(0.3, 0.6, y);
    
    // RIFT: 40Hz 微脉动叠加
    float rift = riftOpacity(uTime);
    
    return auroraShape * verticalFade * rift * 0.15;  // 很低的 opacity
}
```

**雪花（环境粒子）：** 极高山的飘雪。

- 数量：100 个
- 从上方生成，缓慢下落（20-40 pt/s）
- 有水平飘动（正弦波，振幅 10-20pt，频率 0.5-1 Hz）
- 尺寸：1-3pt
- 颜色：`#ffffff`，opacity 0.1-0.25
- 不受 attention 影响

### 4.6.3 专注度反馈行为

| 状态 | Attention 范围 | 视觉反馈 | 音频反馈 |
|------|--------------|---------|---------|
| 专注 | > 0.7 | 主星逐渐变大（直径从当前值向 80pt 增长，速度 2pt/s）。满月出现时发出柔和金光。极光变柔和。流星出现频率降低。 | 低沉颂钵声 136.1 Hz 持续播放。环境音安静。 |
| 中性 | 0.3-0.7 | 主星保持当前大小。极光正常流动。 | 高山风声。 |
| 走神 | < 0.3 | **满月裂痕/乌云遮蔽**：如果主星已成长为满月（直径 > 60pt），走神会导致满月出现裂痕（裂纹 shader 效果）或被乌云从侧面飘来遮蔽。流星出现频率增加。画面整体变暗。 | 呼啸风声加大。低频轰鸣。 |

**满月裂痕效果：** 走神时在满月表面叠加裂纹纹理。

```metal
// 裂痕效果
float moonCracks(float2 pos, float2 moonCenter, float moonRadius, float crackIntensity) {
    float dist = distance(pos, moonCenter);
    if (dist > moonRadius) return 0.0;
    
    // 裂纹使用程序化生成的线段
    float angle = atan2(pos.y - moonCenter.y, pos.x - moonCenter.x);
    float normalizedDist = dist / moonRadius;
    
    // 3 条主裂纹 + 分支
    float crack1 = abs(sin(angle * 3.0 + normalizedDist * 10.0));
    float crack2 = abs(sin(angle * 5.0 - normalizedDist * 8.0 + 1.0));
    float crack3 = abs(sin(angle * 7.0 + normalizedDist * 12.0 + 2.0));
    
    float cracks = min(crack1, min(crack2, crack3));
    float crackMask = smoothstep(0.05, 0.0, cracks);
    
    return crackMask * crackIntensity;  // crackIntensity: 0.0-1.0
}
```

**主星成长系统：**

```swift
class MoonGrowthController {
    var currentRadius: Float = 8.0   // 初始 8pt
    let maxRadius: Float = 80.0      // 满月 80pt
    let growthRate: Float = 2.0      // pt/s (专注时)
    let shrinkRate: Float = 5.0      // pt/s (走神时，快速缩小)
    var crackIntensity: Float = 0.0  // 0.0-1.0
    
    func update(attention: Float, deltaTime: Float) {
        if attention > 0.7 {
            currentRadius = min(maxRadius, currentRadius + growthRate * deltaTime)
            crackIntensity = max(0.0, crackIntensity - deltaTime * 0.3)  // 裂痕缓慢修复
        } else if attention < 0.3 {
            currentRadius = max(8.0, currentRadius - shrinkRate * deltaTime)
            
            // 只有在满月状态下走神才产生裂痕
            if currentRadius > 60.0 {
                crackIntensity = min(1.0, crackIntensity + deltaTime * 0.5)
            }
        }
        // 中性：不生长也不缩小
    }
    
    var isFullMoon: Bool { currentRadius >= maxRadius * 0.9 }
    var moonProgress: Float { (currentRadius - 8.0) / (maxRadius - 8.0) }
}
```

### 4.6.4 音频配置

| 参数 | 值 |
|------|---|
| 环境音 | 极高山风 (极低音量粉红噪声 100-500Hz) + 冰雪环境音 (高频晶体感噪声 6-10kHz, 极低音量) |
| Binaural 左耳 | 185 Hz |
| Binaural 右耳 | 200 Hz |
| Binaural Beat | 15 Hz |
| 走神音效 | 呼啸风声 (风声加大 + 混响) + 低频轰鸣 (60Hz, 0.3s) |
| 专注奖励音效 | 满月显现音：低沉颂钵 136.1 Hz 正弦波 + 高泛音 544.4 Hz (136.1 × 4)，持续 1.5s |
| 流星划过音效 | 快速扫频 whoosh (1000→200Hz, 0.2s)，从左到右的立体声平移 |
| Isochronic Tone | 15 Hz + 40 Hz 双频等时音（RIFT 模式专属），专注时同时播放 |

### 4.6.5 关卡特殊机制

**"八风吹不动"考验：** 这是全应用最高难度的设计。流星是极具视觉诱惑力的突发刺激。SSVEP 算法检测用户是否发生了眼跳（saccade）：

- 如果 attention 在流星出现后的 0.5 秒内骤降（降幅 > 0.3），判定为"被流星吸引"
- 每次被吸引会导致满月缩小 10pt（相当于 5 秒的专注成果白费）
- 抵御住流星（流星出现后 0.5 秒内 attention 保持 > 0.6）不触发任何惩罚

```swift
class MeteorResilienceTracker {
    var meteorActive: Bool = false
    var meteorAppearTime: TimeInterval = 0
    var attentionBeforeMeteor: Float = 0.0
    var resistedCount: Int = 0
    var succumbedCount: Int = 0
    
    func meteorAppeared(attention: Float, currentTime: TimeInterval) {
        meteorActive = true
        meteorAppearTime = currentTime
        attentionBeforeMeteor = attention
    }
    
    func checkResilience(attention: Float, currentTime: TimeInterval) -> MeteorResult? {
        guard meteorActive else { return nil }
        
        let elapsed = currentTime - meteorAppearTime
        
        if elapsed > 0.5 {
            meteorActive = false
            
            // 检查是否被吸引
            if attention < attentionBeforeMeteor - 0.3 {
                succumbedCount += 1
                return .succumbed
            } else {
                resistedCount += 1
                return .resisted
            }
        }
        
        return nil
    }
}

enum MeteorResult {
    case resisted    // 成功抵御
    case succumbed   // 被流星吸引
}
```

**动态流星频率：** 随着满月变大，流星出现频率增加。

```swift
// 流星间隔随 moonProgress 缩短
let meteorInterval = lerp(15.0, 6.0, moonProgress)  // 15秒 → 6秒
```

**RIFT 模式指示：** 当 40 Hz RIFT 频率激活时，极光会微微"呼吸"（肉眼几乎不可见的 40Hz 脉动）。这个效果纯粹是为了 EEG 算法提供额外的频率通道，用户不需要意识到它的存在。

### 4.6.6 完成条件

| 条件 | 值 |
|------|---|
| 完成方式 | Session 时长耗尽 |
| 核心指标 | 最终 moonProgress（主星成长进度 0.0-1.0） |
| 进阶指标 | 抵御流星次数 vs 被吸引次数 |
| 评级基准 | progress >= 0.3 = ★★★，>= 0.5 = ★★★★，>= 0.7 且抵御率 > 70% = ★★★★★ |

---

## 4.7 关卡数据模型 (Level Data Model)

所有关卡共享的数据结构定义：

```swift
// MARK: - Level Configuration
struct LevelConfiguration {
    let id: Int
    let name: String
    let realm: Realm
    let realmTag: String
    let icon: String            // SF Symbol name
    
    // SSVEP
    let targetFrequency: Float  // Hz
    let distractorFrequency: Float?  // Hz, nil = 无干扰
    let advancedFrequency: Float?    // Hz, nil = 无 RIFT
    let targetColor: SIMD3<Float>
    let targetSecondaryColor: SIMD3<Float>
    let distractorColor: SIMD3<Float>?
    let distractorSecondaryColor: SIMD3<Float>?
    let targetOpacityRange: ClosedRange<Float>
    let distractorOpacityRange: ClosedRange<Float>?
    
    // Visual
    let backgroundGradient: (SIMD3<Float>, SIMD3<Float>)
    let particleConfig: ParticleConfig
    let bloomConfig: BloomConfig
    
    // Audio
    let ambientType: AmbientType
    let binauralBase: Float      // Hz
    let binauralBeat: Float      // Hz
    
    // Difficulty
    let sessionDuration: TimeInterval  // 秒
    let attentionProfile: AttentionProfile
}

// MARK: - Realm
enum Realm: Int, CaseIterable {
    case awakening = 0  // 觉醒
    case resonance  = 1  // 共鸣
    case flow       = 2  // 心流
    
    var accentColor: Color {
        switch self {
        case .awakening: return Color(hex: 0x4CAF50)
        case .resonance:  return Color(hex: 0xFFA726)
        case .flow:       return Color(hex: 0xEF5350)
        }
    }
    
    var name: String {
        switch self {
        case .awakening: return "觉醒"
        case .resonance:  return "共鸣"
        case .flow:       return "心流"
        }
    }
}

// MARK: - Particle Config
struct ParticleConfig {
    let primaryType: ParticleType
    let primaryCount: Int
    let secondaryType: ParticleType?
    let secondaryCount: Int
    let ambientType: ParticleType
    let ambientCount: Int
}

enum ParticleType: String {
    case ripple      // 水波纹
    case petal       // 花瓣微粒
    case waterGlow   // 水面微光
    case firefly     // 萤火虫
    case trail       // 尾迹
    case fog         // 迷雾
    case star        // 星辰
    case leaf        // 树叶
    case feather     // 光羽
    case raindrop    // 雨滴
    case lightning   // 雷电碎片
    case meteorTail  // 流星尾焰
    case snowflake   // 雪花
}

// MARK: - Bloom Config
struct BloomConfig {
    let baseStrength: Float
    let focusedStrength: Float
    let distractedStrength: Float
    let radius: Float      // px
    let threshold: Float
}

// MARK: - Ambient Type
enum AmbientType: String {
    case waterInsects     // 水波 + 虫鸣
    case forestWind       // 森林风声
    case deepSpace        // 深空寂静
    case forestNight      // 森林夜间
    case storm            // 暴风雨
    case alpineWind       // 极高山风
}
```

---

## 4.8 Level 工厂方法 (Level Factory)

```swift
extension LevelConfiguration {
    static let allLevels: [LevelConfiguration] = [
        .level1, .level2, .level3, .level4, .level5, .level6
    ]
    
    static var level1: LevelConfiguration {
        LevelConfiguration(
            id: 1, name: "涟漪绽放", realm: .awakening, realmTag: "觉醒·壹", icon: "drop.circle",
            targetFrequency: 15.0, distractorFrequency: nil, advancedFrequency: nil,
            targetColor: SIMD3<Float>(0.804, 0.863, 0.224),
            targetSecondaryColor: SIMD3<Float>(1.000, 0.914, 0.651),
            distractorColor: nil, distractorSecondaryColor: nil,
            targetOpacityRange: 0.60...1.00, distractorOpacityRange: nil,
            backgroundGradient: (SIMD3<Float>(0.039, 0.086, 0.157), SIMD3<Float>(0.051, 0.129, 0.216)),
            particleConfig: ParticleConfig(
                primaryType: .ripple, primaryCount: 8,
                secondaryType: .petal, secondaryCount: 24,
                ambientType: .waterGlow, ambientCount: 60
            ),
            bloomConfig: BloomConfig(baseStrength: 0.3, focusedStrength: 0.8, distractedStrength: 0.1, radius: 8.0, threshold: 0.6),
            ambientType: .waterInsects,
            binauralBase: 200.0, binauralBeat: 15.0,
            sessionDuration: 300,
            attentionProfile: AttentionProfile(baseline: 0.50, focusTrend: 0.08, distractibility: 0.15, recoveryRate: 0.80, noiseAmplitude: 0.02)
        )
    }
    
    // level2, level3, level4, level5, level6 按相同模式定义
    // 完整实现见 LevelConfigurations.swift
}
```

---

## 4.9 关卡解锁逻辑

```swift
class LevelUnlockManager {
    // 解锁条件基于历史 session 数据
    func isUnlocked(levelId: Int, history: [SessionRecord]) -> Bool {
        switch levelId {
        case 1: return true  // 始终解锁
        case 2: return history.contains(where: { $0.levelId == 1 && $0.rating >= 3 })
        case 3: return history.contains(where: { $0.levelId == 2 && $0.rating >= 3 })
        case 4: return history.contains(where: { $0.levelId == 3 && $0.rating >= 3 })
        case 5: return history.contains(where: { $0.levelId == 4 && $0.rating >= 3 })
        case 6: return history.contains(where: { $0.levelId == 5 && $0.rating >= 3 })
        default: return false
        }
    }
    
    // 简化版（Demo 用）：连续完成前一关即可解锁
    func isUnlockedDemo(levelId: Int, completedLevels: Set<Int>) -> Bool {
        levelId == 1 || completedLevels.contains(levelId - 1)
    }
}
```


---

# Section 5-7: 模拟系统 · UX流程 · HIG对齐

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
