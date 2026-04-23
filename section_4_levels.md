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
