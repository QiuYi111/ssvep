# 星空与萤火 Web Prototype 实施计划书

版本：v1.0  
目标读者：负责实现 Web prototype 的工程 agent / 前端工程师 / 视觉交互工程师  
范围：仅用于快速验证视觉、关卡体验、SSVEP 目标伪装方式和 UI/UX，不替代最终 native clinical implementation。

---

## 1. 背景与决策

当前 macOS SwiftUI + Metal 版本暴露出一个核心问题：手写 Metal 图形的迭代成本过高，视觉效果需要频繁 build、运行、截图、反馈，导致美术方向验证速度过慢。另一方面，3D 资产生产链路复杂，涉及 2D concept、3D 生成、拓扑清理、rig、材质、SceneKit 接入，短期内不适合继续推进。

因此，本阶段切换为 **Web prototype**：

- 使用浏览器快速预览视觉效果。
- 用 Canvas 2D / WebGL 手写图形验证关卡美术方向。
- 用调试面板快速调整 attention、frequency、bloom、motion、palette。
- 确定每关视觉语言后，再迁移成熟方案到 native Metal / SceneKit。

Web prototype 是 **visual and interaction sandbox**，不是最终 SSVEP 时序实现。最终严肃训练仍需回到 native 渲染，保证刷新率、帧同步和低延迟控制。

---

## 2. 项目目标

### 2.1 产品目标

构建一个可在浏览器中运行的 6 关卡视觉训练原型，用于快速验证：

- 每个关卡是否符合 `Designs/design.md` 的设计意图。
- No-HUD 训练是否成立。
- SSVEP 目标是否能自然伪装成环境光源。
- 干扰项是否可被识别但不廉价。
- 注意力反馈是否通过自然场景变化传达，而不是数值 UI。
- 视觉是否达到“高级独立游戏 / Apple Mindfulness-like wellness app”的方向。

### 2.2 工程目标

实现一个独立目录：

```text
web-prototype/
├── index.html
├── package.json
├── src/
│   ├── main.ts
│   ├── styles.css
│   ├── core/
│   │   ├── App.ts
│   │   ├── Renderer.ts
│   │   ├── Controls.ts
│   │   ├── Timing.ts
│   │   └── types.ts
│   ├── levels/
│   │   ├── LevelRenderer.ts
│   │   ├── LotusLake.ts
│   │   ├── FireflyForest.ts
│   │   ├── ConstellationTrace.ts
│   │   ├── DualFireflies.ts
│   │   ├── StormSwallow.ts
│   │   └── MeteorTrial.ts
│   └── utils/
│       ├── color.ts
│       ├── noise.ts
│       ├── easing.ts
│       └── drawing.ts
└── README.md
```

推荐技术栈：

- Vite
- TypeScript
- HTML Canvas 2D first
- 可选：后续引入 WebGL / regl / Three.js，但首版不强依赖

---

## 3. 非目标

本阶段不做：

- 不做真实 EEG 接入。
- 不做临床级 SSVEP 精准时序保证。
- 不做登录、云同步、用户系统。
- 不做完整产品 landing page。
- 不做 3D asset pipeline。
- 不做复杂 React 组件体系。
- 不做大量装饰性 UI。

所有精力集中在：**关卡视觉、交互反馈、调参效率、预览体验**。

---

## 4. 视觉与 HIG 方向

### 4.1 总体视觉原则

参考 `Designs/design.md` 和 `Designs/IMPLEMENTATION_PLAN.md` 的 HIG 部分：

- UI 接近 Apple Mindfulness + Apple Weather：安静、有深度、留白充足。
- 训练画面全屏、沉浸、No-HUD。
- Debug controls 是开发工具，不是产品 UI。
- 视觉反馈必须环境化：
  - 专注：光更稳定、雾散开、植物生长、星线连接、水面有序。
  - 分心：雾回流、树枯萎、月面裂纹、暴风增强、连线断裂。
- 禁止游戏化 UI：
  - 无分数
  - 无血条
  - 无进度条
  - 无排行榜
  - 无成就徽章
  - 无准星/射击游戏 HUD

### 4.2 色彩原则

主目标：

- 暖烛光 `#ffe9a6`
- 生物荧光绿 `#cddc39`

干扰项：

- 幽冷星蓝 `#8ab4f8`
- 暗紫雷云 `#4a148c`

背景：

- 深蓝黑
- 森林黑绿
- 月光银灰
- 雾灰

禁止：

- 过曝纯白大光球
- 彩虹渐变
- 赛博霓虹
- 廉价手游高饱和色
- 过粗描边
- 大面积硬闪

### 4.3 无障碍原则

目标和干扰项不能只靠颜色区分，还需要：

- 形状：目标偏圆润有机；干扰偏锐利、菱形、碎片状。
- 大小：目标略大且稳定；干扰略小且更短暂。
- 运动：目标慢速漂浮/聚集；干扰快速、外围、突发。
- 纹理：目标柔和生命光；干扰冷硬晶体感。

Reduce Motion 模式：

- 关闭高速粒子运动。
- 用缓慢呼吸亮度替代复杂运动。
- 用状态切换替代连续动画。
- 禁用或降低 bloom。

---

## 5. 应用结构

### 5.1 布局

页面应是一个真正的工具界面，不是 landing page。

```text
┌─────────────────────────────────────────────────────────────┐
│ Full-screen Canvas                                           │
│                                                             │
│  ┌───────────────┐                         ┌──────────────┐ │
│  │ Level Rail    │                         │ Inspector    │ │
│  │ 1 Lotus       │                         │ Attention    │ │
│  │ 2 Forest      │                         │ Frequency    │ │
│  │ ...           │                         │ Bloom        │ │
│  └───────────────┘                         └──────────────┘ │
│                                                             │
│  bottom-left: current level title / short state              │
└─────────────────────────────────────────────────────────────┘
```

UI 要求：

- Canvas 全屏。
- 控件浮在上层，但保持半透明、低干扰。
- 默认显示调试面板；按 `H` 可隐藏。
- 关卡切换应即时生效，并有 300ms 左右 fade transition。
- 不使用复杂卡片网格。

### 5.2 Debug Controls

必须提供：

- Level selector：1-6
- Attention slider：0-1
- Target frequency：默认 15Hz
- Distractor frequency：默认 20Hz
- Bloom strength
- Particle density
- Reduce Motion toggle
- Pause / Resume
- Reset level
- Show target mask toggle：开发用，显示 SSVEP 目标覆盖面积，默认关闭
- Screenshot button：导出当前 canvas PNG

可选：

- Time scale
- Theme preset
- Background brightness
- Target size
- Distractor intensity

---

## 6. 渲染架构

### 6.1 Core Loop

使用 `requestAnimationFrame`：

```ts
function frame(now: number) {
  const dt = Math.min((now - lastNow) / 1000, 0.033);
  state.time += dt;
  activeLevel.update(dt, state);
  renderer.clear();
  activeLevel.draw(ctx, state);
  requestAnimationFrame(frame);
}
```

注意：

- Web 版只用于视觉验证，不保证浏览器精确频率。
- 仍然要用真实 `sin(2πft)` 计算 target/distractor opacity，方便观察刺激伪装。
- 所有闪烁必须限制在小面积局部光源。

### 6.2 SSVEP Opacity Function

建议：

```ts
function ssvepOpacity(time: number, frequency: number, min = 0.60, max = 1.0) {
  const phase = Math.sin(time * Math.PI * 2 * frequency) * 0.5 + 0.5;
  return min + (max - min) * phase;
}
```

禁止：

- 0%-100% 方波硬闪。
- 全屏闪烁。
- 大面积背景参与频闪。

### 6.3 Renderer Utilities

需要实现：

- `drawGlow()`
- `drawSoftCircle()`
- `drawNoiseFog()`
- `drawStarField()`
- `drawWaterReflection()`
- `drawPetal()`
- `drawFirefly()`
- `drawLightning()`
- `drawAurora()`
- `drawVignette()`

---

## 7. 关卡规格

### 7.1 Level 1: 涟漪绽放 / Lotus Lake

目的：持续性注意基础训练。

场景：

- 月夜湖面。
- 中央低调睡莲。
- 远处山线。
- 微弱星光倒影。
- 水面不能出现廉价大同心圆。

目标：

- 花蕊暖金光，15Hz。
- 目标面积小于 5%。
- 花瓣可随 attention 打开。

反馈：

- Attention 高：花瓣打开、水波变规则、花蕊更稳定。
- Attention 低：花瓣合拢、水面平静、光变弱。

实现要点：

- 睡莲用 Canvas path 绘制 12-18 个花瓣。
- 花瓣角度由 `attention` 控制。
- 涟漪细线低透明度，不超过 3-4 层。
- Bloom 必须克制。

验收：

- 不得出现大白光。
- 不得出现粗大同心圆。
- 不得像 UI 图标。
- 第一眼应读作“安静夜湖 + 睡莲”。

### 7.2 Level 2: 萤火引路 / Firefly Forest

目的：视觉耐力和疲劳阈值。

场景：

- 黑森林。
- 多层树干形成深度。
- 迷雾笼罩。
- 远处石碑。

目标：

- 中央萤火虫群，15Hz。
- 每只萤火虫小，群体形成焦点。

反馈：

- Attention 高：萤火虫聚集、光照半径扩大、雾退、石碑符文亮起。
- Attention 低：雾回流、符文变暗、视距缩短。

实现要点：

- 用粒子点绘制萤火虫。
- 中央目标群运动稳定。
- 雾用多层半透明 noise / blurred blobs。
- 石碑要有 silhouette，不要大量文字。

验收：

- 能看出森林空间层次。
- 萤火不是一个单独大光球。
- 雾变化明显但不遮死画面。

### 7.3 Level 3: 星图寻迹 / Constellation Trace

目的：转移性注意。

场景：

- 深空星图。
- 主星节点序列。
- 冷色底噪星。
- 连接线逐步形成。

目标：

- 当前主星暖金 15Hz。
- 背景星弱冷蓝 20Hz，作为底噪干扰。

反馈：

- Attention 高：当前节点爆出小光晕，连线推进。
- Attention 低：连线变暗或断裂。
- 完成后出现光之灵兽轮廓。

实现要点：

- 使用固定节点数组。
- `activeNodeIndex` 随时间或 attention 完成度推进。
- 连接线使用细线，不使用激光。
- 灵兽轮廓可先用点线 silhouette。

验收：

- 主星明显但不刺眼。
- 干扰星存在但不抢主目标。
- 星座完成有奖励感。

### 7.4 Level 4: 真假萤火 / Dual Fireflies

目的：选择性注意和冲动抑制。

场景：

- 森林空地。
- 黄绿萤火与幽蓝萤火同时出现。
- 中央生命树。

目标：

- 黄绿萤火 15Hz。
- 幽蓝萤火 20Hz。

反馈：

- Attention 高：黄绿萤火聚集，生命树生长。
- Attention 被干扰：蓝光更活跃，树枯萎或灰化。

实现要点：

- 目标萤火运动慢且有聚集趋势。
- 干扰萤火更外围、更锐利、更不稳定。
- 生命树用分形/路径绘制，随 attention 生长。

验收：

- 色盲情况下仍能通过运动和形状区分目标/干扰。
- 生命树成长反馈可读。
- 不像简单红蓝测试。

### 7.5 Level 5: 飞燕破云 / Storm Swallow

目的：动态追踪和平滑眼动。

场景：

- 暴风雨夜航。
- 云层运动。
- 远处闪电。
- 灵燕作为移动目标。

目标：

- 灵燕胸口或尾羽暖金光 15Hz。
- 雷电冷紫/蓝 20Hz 干扰。

反馈：

- Attention 高：飞行路径稳定，云隙打开。
- Attention 低：画面轻微颠簸，雨线增强，雷云变亮。

实现要点：

- 灵燕用 Canvas path 绘制，不要画成飞机或图标。
- 翅膀用 sine flap。
- 摄像机/背景 parallax 产生飞行感。
- 闪电必须局部、短暂，禁止全屏白闪。

验收：

- 目标是“可追踪的灵燕”，不是亮点。
- 动态强但不眩晕。
- Reduce Motion 下能静态替代。

### 7.6 Level 6: 流星试炼 / Meteor Trial

目的：高级执行控制，抵抗突发干扰。

场景：

- 极简雪山夜空。
- 大面积负空间。
- 山巅孤星。
- 极光/流星作为外围干扰。

目标：

- 孤星 15Hz，逐渐变成月亮。

干扰：

- 流星、极光、飞鸟/云影。

反馈：

- Attention 高：孤星变满月，雪山被月光照亮。
- Attention 低：月面裂纹、云遮月、流星更诱人。

实现要点：

- 保持极简。
- 不要过多粒子。
- 流星短暂出现，移动快，亮度克制。
- 月亮不能变成 UI 白圆。

验收：

- 画面有“空”和“定”的感觉。
- 目标清楚但不廉价。
- 干扰突发但不破坏整体审美。

---

## 8. UI / UX 细节

### 8.1 Level Rail

关卡选择栏：

- 左侧竖排。
- 使用数字 + 简短中文名。
- 当前关卡高亮。
- 不使用大卡片。
- 不使用彩色游戏 icon。

### 8.2 Inspector

右侧调试面板：

- 半透明深色背景。
- 使用原生表单式布局。
- label 小，control 清晰。
- 控件必须不遮挡主目标。

### 8.3 On-Canvas Caption

底部左侧显示：

- 当前关卡名。
- 当前训练状态一句话。

示例：

```text
涟漪绽放
花蕊稳定，湖面出现细微涟漪
```

这只是 prototype 辅助，不代表最终训练 HUD。

---

## 9. 任务拆分建议

适合 delegate 给多个 agent：

### Agent A: Project Scaffold

负责：

- 创建 `web-prototype/`
- 配置 Vite + TypeScript
- 实现 canvas resize / DPR scaling
- 实现 app state
- 实现 level switching
- 实现 debug controls

交付：

- 可运行 dev server
- 空白 canvas + controls
- README

### Agent B: Core Rendering Utilities

负责：

- drawing helpers
- noise helpers
- glow helpers
- SSVEP opacity
- palette system
- screenshot export

交付：

- `src/utils/*`
- `src/core/Timing.ts`
- demo utility render

### Agent C: Levels 1-2

负责：

- `LotusLake.ts`
- `FireflyForest.ts`

验收重点：

- 首关不廉价、不爆光。
- 第二关雾和萤火反馈可读。

### Agent D: Levels 3-4

负责：

- `ConstellationTrace.ts`
- `DualFireflies.ts`

验收重点：

- 目标/干扰不只靠颜色区分。
- 星图连接和生命树成长有状态变化。

### Agent E: Levels 5-6

负责：

- `StormSwallow.ts`
- `MeteorTrial.ts`

验收重点：

- 动态追踪不眩晕。
- 雪山关保持极简和高级感。

### Agent F: Visual QA / HIG Review

负责：

- 检查 UI 是否过度游戏化。
- 检查是否出现过曝、廉价光效、大面积闪烁。
- 检查 Reduce Motion。
- 检查移动端/桌面尺寸。
- 检查调试面板可用性。

---

## 10. 验收标准

### 10.1 功能验收

- `npm install` 后可运行。
- `npm run dev` 启动本地预览。
- 浏览器打开后默认进入 Level 1。
- 可切换 6 个关卡。
- Attention slider 对每关有明显反馈。
- Target frequency 和 distractor frequency 对局部光源产生可见影响。
- Reduce Motion 生效。
- Screenshot button 可导出 PNG。

### 10.2 视觉验收

每关截图必须满足：

- 关卡主题一眼可读。
- 没有廉价 demo 感的大白光、大圆圈、大色块。
- 没有 UI 元素遮挡主目标。
- 目标光源局部、自然、可凝视。
- 反馈变化是环境叙事，不是数值 UI。
- 整体风格安静、高级、克制。

### 10.3 性能验收

- 1440x900 下稳定 60 FPS。
- DPR=2 时仍可运行。
- Canvas resize 无拉伸模糊。
- 粒子数量可调，低端机器可降级。

### 10.4 代码验收

- 每个 level 独立文件。
- 公共绘图逻辑不复制粘贴。
- 无大型全局状态混乱。
- TypeScript 类型清晰。
- README 说明运行和快捷键。

---

## 11. 风险与应对

### 风险 1：Canvas 2D 视觉仍显廉价

应对：

- 降低特效堆叠。
- 多用层次、雾、遮挡、细节纹理。
- 少用纯几何图形。
- 对关键物体用 Path2D 精细手绘。

### 风险 2：SSVEP 闪烁在浏览器不稳定

应对：

- 明确 Web 只做视觉伪装验证。
- 标记 prototype timing warning。
- 后续 native 实现重新做帧同步。

### 风险 3：调试 UI 破坏美感

应对：

- `H` 一键隐藏。
- 默认半透明低对比。
- 截图时自动隐藏 debug UI。

### 风险 4：多 agent 风格不一致

应对：

- 所有关卡使用同一 palette。
- 所有 level 继承统一 `LevelRenderer` 接口。
- 统一 drawing helpers。
- 每个 PR/patch 附关卡截图。

---

## 12. 后续迁移路线

Web prototype 视觉定稿后：

1. 提取每关的视觉参数：
   - palette
   - object positions
   - particle counts
   - attention mapping
   - target/distractor area
2. 迁移到 native：
   - Canvas drawing → Metal shader / SceneKit nodes
   - JS timing → frame-count based SSVEP controller
   - Debug panel → internal developer menu
3. 对 SSVEP 做 native 验证：
   - 60/120Hz display sync
   - dropped frame detection
   - target area measurement
   - luminance modulation range

---

## 13. Definition of Done

本阶段完成的定义：

- 一个可运行的 Web prototype。
- 六个关卡均可切换和预览。
- 每关都有 attention-driven feedback。
- 每关都有局部 SSVEP target 和必要的 distractor。
- UI 符合 Apple HIG 方向：克制、系统感、无游戏化噪音。
- 用户可以在浏览器中快速反馈视觉问题。
- 文档和 README 足够让后续 agent 继续迭代。
