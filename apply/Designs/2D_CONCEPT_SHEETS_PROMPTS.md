# 星空与萤火 2D Concept Sheets Prompt Bible

用途：为 AI 生图和后续 2D-to-3D 工具（Rodin / Meshy / Tripo / Blender workflow）准备统一的概念图提示词。本文不是最终游戏文案，而是资产生产规格。

核心原则：

- 先生成“可转 3D 的单体资产图”，再生成“场景气氛图”。
- 单体资产图必须干净、居中、无复杂背景、轮廓清晰、材质明确。
- 可动资产优先拆件，例如莲花拆成单片花瓣、花蕊、莲叶；生命树拆成树干、枝条、叶簇；飞燕拆成身体、翅膀、尾羽。
- SSVEP 目标不是大面积白光，而是自然物体上的局部 emissive 区域：花蕊、萤火虫腹部、主星核心、飞燕胸口光点。
- 生成图尽量使用 orthographic concept sheet、front view、side view、top view、turnaround，而不是电影海报。

## Global Style

**Art Direction**

High-end contemplative fantasy, premium indie game art, elegant East Asian meditation aesthetics, restrained magical realism, natural light sources only, quiet cinematic atmosphere, painterly realism with clean asset readability, PBR-friendly materials, sophisticated silhouettes, no cartoon UI, no neon sci-fi, no medical interface.

**Color Language**

- Primary target light: warm candle gold `#ffe9a6`, bioluminescent yellow green `#cddc39`.
- Distractor light: cold star blue `#8ab4f8`, deep violet storm `#4a148c`.
- Background: deep blue black, forest green black, moonlit silver, mist grey.
- Avoid: pure white overexposure, saturated cyberpunk glow, rainbow gradients, plastic toy colors.

**Universal Negative Prompt**

low quality, blurry, noisy, pixelated, low poly look, childish cartoon, cheap mobile game, overexposed white bloom, giant glowing orb, UI elements, text, labels, watermark, logo, frame, border, flat icon, stickers, hard black outlines, plastic material, toy-like, cyberpunk neon, sci-fi panels, medical dashboard, progress bar, score display, symmetrical mandala background for asset sheets, human characters, hands, weapons, gore, horror.

**Preferred Prompt Suffix For 3D Conversion**

orthographic concept sheet, centered object, clean white background, front view, side view, top view, three-quarter view, consistent design across views, full object visible, sharp silhouette, clear material separation, PBR texture details, no dramatic perspective, no cast shadow hiding details, no background environment.

**Preferred Output**

- Asset sheets: 4096 x 4096, white or transparent background.
- Scene key art: 16:9, 3840 x 2160.
- Material references: square 2048 x 2048.

## Apple HIG / UI-UX Art Constraints

本项目的 UI 方向必须融合 Apple Human Interface Guidelines。界面应接近 Apple Mindfulness 与 Apple Weather 的交叉：安静、有深度、留白充足、系统感强、没有游戏化噪音。训练体验可以像高级游戏场景，但 UI 本身必须像一个克制、可信、系统原生的 macOS 健康工具。

### HIG Principles For Concept Generation

**Aesthetic Integrity**

All UI-adjacent concept art must feel calm, coherent, native to macOS, dark-mode first, glass-like but not decorative. Metal / SceneKit scenes and SwiftUI surfaces should visually merge through shared atmosphere: deep night, soft translucency, muted material, no hard cards floating like mobile game menus.

Prompt add-on:

macOS native premium wellness application aesthetic, Apple Mindfulness and Apple Weather inspired calm interface, deep dark mode, subtle translucent glass, generous spacing, quiet hierarchy, no gamification, no leaderboard, no score UI, no achievement badge, refined system feel.

**Consistency**

Use system-like typography and SF Symbol-compatible iconography. Concept images for UI screens should leave space for SwiftUI text rather than baking text into the image. Do not generate custom fantasy fonts, decorative labels, or unreadable symbols for UI controls.

Prompt add-on:

system-native layout, SF Pro compatible spacing, no custom lettering, no baked text, no fantasy UI font, icon-friendly visual hierarchy, rounded but restrained controls, standard macOS settings form language.

**Direct Manipulation**

User control should feel immediate: click a level card, enter calibration, gaze affects the scene directly. Concept art should show objects that can be manipulated naturally: rings rotate, petals open, fog clears, fireflies gather, star lines connect.

Prompt add-on:

objects designed for direct manipulation and animation, clear controllable parts, readable state changes, no abstract progress bars, feedback expressed through natural environmental changes.

**Feedback As Environment**

Feedback must be environmental, not numerical. Do not generate health bars, score panels, progress meters, target reticles, warning popups, or graph overlays for training. Feedback states should appear as light, fog, growth, motion, sound-implied atmosphere, cracks, withering, cloud cover.

Prompt add-on:

attention feedback represented by natural scene changes, brighter bioluminescence, clearing mist, growing plant forms, connecting stars, calmer water, no numbers, no chart, no HUD.

**Metaphors**

Keep metaphor consistency:

- 星空 = 意识空间
- 萤火虫 = 注意力粒子
- 迷雾 = 分心 / 杂念
- 莲花绽放 = 进入心流
- 星象仪 = 校准 / 与频率共鸣
- 曼陀罗 / 星轨 = 训练后的心念图谱

### Accessibility Constraints For Assets

**Reduce Motion**

Every animated concept should have a still-state equivalent:

- Firefly swarm: static cluster plus slow breathing glow.
- Lotus opening: three discrete poses: bud, half-open, open.
- Astrolabe calibration: static astrolabe plus illuminated ring states.
- Fog clearing: separate dense, medium, clear fog sheets.
- Star connection: unconnected, partial connection, complete constellation.

When generating assets, prefer pose/state sheets over one dramatic motion image.

**Color Blindness**

Never rely on color alone to distinguish target and distractor. Every target/distractor pair should differ by:

- Shape: round organic warm target vs sharper diamond/needle/cold distractor.
- Size: target slightly larger or more stable.
- Motion: target slow floating/gathering, distractor jittery/peripheral/transient.
- Texture: target soft organic glow, distractor icy crystalline edge.

Prompt add-on for target assets:

round organic silhouette, stable slow motion identity, warm emissive core, readable even without color.

Prompt add-on for distractor assets:

sharper angular silhouette, smaller colder light, jittery peripheral identity, readable even without color.

**Dynamic Type / Text Safety**

Do not bake important text into AI-generated concept images. UI art should provide dark quiet space where SwiftUI can place scalable system text. Any decorative markings must be non-readable, symbolic, and not required for comprehension.

**VoiceOver / Semantic State**

Because SceneKit/Metal content is visually rich but semantically opaque, each scene should have clearly nameable states for accessibility announcements:

- Level 1: bud closed, petals opening, lotus open, water calm, ripples active.
- Level 2: fog dense, fog thinning, monument visible, runes lit.
- Level 3: node waiting, node focused, line connected, constellation complete.
- Level 4: target swarm active, distractor swarm active, tree growing, tree withering.
- Level 5: flight stable, storm intensified, swallow visible, lightning distraction.
- Level 6: solitary star, crescent, full moon, cracked moon, clouded moon.

### HIG-Compatible UI Concept Prompts

These are for UI background/key art, not 3D conversion.

#### UI-A: Home Screen Background

Prompt:

Dark calm starfield background for a macOS wellness application, inspired by Apple Mindfulness and Apple Weather, subtle depth, soft distant stars, gentle atmospheric gradient, no UI text, no bright center object, enough negative space for translucent SwiftUI level cards, premium native Apple feeling, quiet and meditative, 16:9.

Negative:

game menu, fantasy logo, leaderboard, buttons, text, neon sci-fi cockpit, busy galaxy, colorful nebula, high contrast poster.

#### UI-B: Realm Banner Background

Prompt:

Subtle translucent glass banner background concept, dark starry meditation atmosphere, soft green-gold accent glow at one edge, macOS native wellness app style, generous padding, quiet premium material, no text, no icons baked in, suitable for SwiftUI overlay, 16:9 crop.

Negative:

badge, achievement banner, game reward panel, thick border, ornate fantasy frame, text, numbers, progress bar.

#### UI-C: Level Card Visual Language

Prompt:

Set of six minimal premium level card background thumbnails for a macOS meditation training app, each card has subtle scene motif only: moonlit lotus lake, fog forest fireflies, constellation sky, dual firefly forest, storm swallow flight, snow mountain star; no text, no UI controls, no numbers, consistent dark-mode glass aesthetic, restrained accent colors, enough empty area for SwiftUI labels and SF Symbol icons.

Negative:

mobile game cards, gacha rarity frame, big lock icon, text, badges, stars rating, fantasy ornate border, saturated colors.

#### UI-D: Debrief Background / 心念图谱 Stage

Prompt:

Quiet dark debrief screen background for a macOS mindfulness app, star trail mandala space in the center, subtle glass depth, warm gold and muted green accent particles, no chart, no numbers, no labels, no progress rings, premium Apple-like wellness visualization, screenshot-worthy but calm, 16:9.

Negative:

dashboard, analytics chart, score panel, progress bar, game result screen, trophy, achievement, text, neon.

#### UI-E: Settings Background Accent

Prompt:

Minimal dark macOS settings background accent for a wellness app, subtle blurred starfield and soft translucent material, quiet system-native feeling, no controls baked in, no text, no icons, designed to sit behind SwiftUI Form sections.

Negative:

custom fantasy panel, sci-fi terminal, sliders drawn into image, labels, ornate border, high contrast pattern.

## Level 1: 涟漪绽放

### Level Design Description

首关是“觉醒”阶段的基础持续性注意训练。场景是一片极静的暗色湖面，玩家面对一朵含苞待放的睡莲。目标频率隐藏在花蕊的暖金波光中，用户凝视花蕊时，莲花缓慢打开，湖面出现规则、细腻、低对比的同心涟漪；走神时花瓣收合，水面恢复沉寂。视觉重点必须安静、克制、亲近自然，不能像舞台灯或爆炸特效。画面中心目标面积小于屏幕 5%，让 SSVEP 闪烁自然伪装成花蕊微光。

### Scene Key Art Prompt

Moonlit dark lake at night, a single elegant water lily floating in the center foreground, subtle warm golden glow inside the flower core, calm black-blue water with thin gentle ripples, distant low mountain silhouettes, sparse stars reflected on the lake, refined East Asian meditation mood, premium indie game environment art, restrained magical realism, cinematic but quiet, natural moonlight and candle-like bioluminescence, no UI, no characters, no overexposed bloom, 16:9 wide composition, high detail, painterly realistic, atmospheric depth.

### Asset L1-A: Lotus Flower Bud

Prompt:

Closed water lily bud for a premium meditation fantasy game, elegant layered petals, pale pink outer petals with warm cream inner edges, small hidden golden luminous core barely visible through the petals, round organic silhouette readable without color, organic botanical accuracy, delicate veins, smooth waxy petal material, asset concept sheet, orthographic front view side view top view and three-quarter view, centered on clean white background, full object visible, PBR-friendly texture details, designed for later 3D modeling and petal opening animation, no baked text, HIG-compatible calm wellness aesthetic.

Negative:

overexposed flower, giant light bulb, rose, tulip, cartoon flower, plastic toy, thick black outline, busy lake background, text, watermark, human hand, vase.

3D/Animation Notes:

Generate as a closed bud reference. For animation, do not rely on one generated mesh opening magically. Use this with `lotus_petal_single` and `lotus_core` to build a rigged flower where petals rotate outward around their base.

### Asset L1-B: Lotus Flower Open

Prompt:

Fully opened sacred water lily, graceful radial layered petals, warm candle-gold luminous stamen at the center, pale pink and ivory petals, subtle bioluminescent edge highlights, round stable target identity readable without color, realistic botanical structure, premium fantasy meditation game asset, calm and elegant, orthographic concept sheet, front view side view top view three-quarter view, clean white background, centered object, full silhouette visible, sharp petal separation, PBR material reference, suitable for 3D conversion, no baked text, HIG-compatible calm wellness aesthetic.

Negative:

pure white glow, blown out bloom, lotus made of light only, cheap sticker style, flat icon, symmetrical mandala, busy background, text, watermark.

3D/Animation Notes:

This is the fully focused state. Use as target pose. The SceneKit animation should interpolate from bud to open by rotating individual petal nodes, while emissive intensity of the stamen runs the SSVEP modulation.

### Asset L1-C: Single Lotus Petal

Prompt:

Single water lily petal isolated, elongated teardrop shape, slightly curved surface, pale pink base fading to ivory tip, subtle warm translucent edge, delicate vein pattern, realistic waxy botanical material, orthographic asset sheet with front view side view top view, clean white background, centered, full petal visible, clear root/base hinge area for animation, PBR-friendly, high detail.

Negative:

multiple petals, flower cluster, rose petal, torn petal, cartoon, plastic, overbright glow, background water.

3D/Animation Notes:

Critical rig asset. Each petal should become an individual mesh node. Pivot should be placed at the petal base. Animation range: closed `-55 deg` to open `15-35 deg`, staggered by layer.

### Asset L1-D: Lotus Core / Stamen Target

Prompt:

Small lotus flower stamen core, warm candle-gold bioluminescent pollen filaments, natural organic structure, not a sphere, not a lamp, subtle emissive center suitable for gaze target, detailed botanical macro asset, isolated on clean white background, front view side view top view, centered, high detail PBR material, premium fantasy realism.

Negative:

white sun, glowing ball, LED bulb, sci-fi reactor, overexposed bloom, icon, flat circle, text.

3D/Animation Notes:

This is the actual 15Hz SSVEP target. In SceneKit, assign emissive material to filament tips only. Modulate `emission.intensity` or material color brightness between 60%-100%, never 0%-100%.

### Asset L1-E: Lily Pad Set

Prompt:

Set of three floating water lily pads, dark green waxy leaves, subtle water droplets, natural notched circular shape, different sizes, slightly curled edges, muted moonlit colors, premium realistic botanical game asset, orthographic top view and side view concept sheet, clean white background, clear silhouettes, PBR-friendly leaf veins and roughness.

Negative:

cartoon leaf, neon green, huge flower, frog, insect, pond background, text, watermark.

3D/Animation Notes:

Static or gently bobbing SceneKit nodes. Use slight vertical sine movement and rotation, not SSVEP modulation.

### Asset L1-F: Ripple Material Reference

Prompt:

Subtle moonlit lake water ripple material reference, dark blue black water, fine low-contrast wave lines, soft reflections, no large concentric rings, no bright neon, premium realistic water shader reference, tileable texture study, PBR water normal map inspiration, calm meditation mood, square image, no objects, no text.

Negative:

giant rings, bright green circles, overexposed highlights, storm waves, ocean surf, cartoon waves.

3D/Animation Notes:

Do not convert to 3D. Use as water material reference: animated normal map, reflection, subtle procedural ripple around lotus.

## Level 2: 萤火引路

### Level Design Description

第二关延续“觉醒”，训练视觉耐力。玩家身处迷雾笼罩的黑森林，中央是一群黄绿色萤火虫，远处有一座古老石碑。凝视萤火虫群时，萤火光照半径扩大，雾逐渐退开，石碑符文被照亮并解密；走神时雾回流，树影吞没视野。这里的目标不是一个大光球，而是多个微小生命光点形成的自然焦点。

### Scene Key Art Prompt

Foggy ancient black forest at night, layered dark tree trunks, soft volumetric mist, a small cluster of warm yellow green fireflies floating in the center path, distant moss-covered stone monument with faint runes, cinematic depth, quiet meditative atmosphere, natural bioluminescent light, premium indie fantasy game environment, East Asian spiritual mood, no UI, no characters, restrained contrast, 16:9 wide composition.

### Asset L2-A: Firefly Body

Prompt:

Realistic stylized firefly insect for premium fantasy game, tiny elegant body, translucent wings, dark bronze thorax, glowing yellow green abdomen, round organic target silhouette readable without color, stable calm identity, not scary, not cartoon, asset concept sheet, macro front view side view top view and three-quarter view, clean white background, full body visible, PBR-friendly details, separated glowing abdomen area for emissive material, no baked text, HIG-compatible calm wellness aesthetic.

Negative:

monster bug, mosquito, bee, cartoon, cute emoji, giant glowing ball, cyberpunk neon, background forest, text, watermark.

3D/Animation Notes:

Needs simple wing flutter animation. If generated 3D has no rig, create two wing nodes and animate rotation. Abdomen emissive is the 15Hz SSVEP target for Level 2/4.

### Asset L2-B: Firefly Glow Sprite

Prompt:

Soft bioluminescent firefly glow sprite, warm yellow green light, small circular center with feathered falloff, natural organic glow, transparent background, game VFX texture, no hard edge, no lens flare, no star shape, no text, subtle and elegant.

Negative:

white explosion, neon orb, UI button, lens flare streaks, hard circle, cartoon sparkle.

3D/Animation Notes:

Use as particle texture, not 3D mesh. Each firefly particle gets this sprite with emissive modulation.

### Asset L2-C: Ancient Stone Monument With Runes

Prompt:

Ancient moss-covered stone monument, vertical weathered slab, subtle carved runes, East Asian fantasy archaeology, rough granite, cracks, moss, water stains, mysterious but calm, orthographic concept sheet front side back three-quarter view, clean white background, centered, full object visible, high detail PBR stone material, runes designed as shallow carvings with optional warm emissive insets.

Negative:

grave text, modern tombstone, readable real language, skulls, horror, bright neon symbols, UI glyphs, background forest, watermark.

3D/Animation Notes:

Runes should be separate emissive material slots. Focus state increases rune emission gradually; distracted state dims runes and increases fog.

### Asset L2-D: Black Forest Tree Trunk Set

Prompt:

Set of ancient black forest tree trunks, tall vertical silhouettes, twisted roots, moss, damp bark, subtle blue moonlight edge, premium fantasy environment asset sheet, three trunk variations, clean white background, front and side views, full height visible, realistic bark texture, PBR-friendly.

Negative:

cartoon tree, autumn orange leaves, bright daylight, haunted horror face, house, UI, text.

3D/Animation Notes:

Static environment kit. Use repeated instances with different scale and rotation. Avoid SSVEP modulation.

### Asset L2-E: Fog Layer Reference

Prompt:

Volumetric forest fog reference, soft grey green mist layers, transparent drifting sheets, dark forest atmosphere, no hard shapes, no objects, elegant meditation mood, VFX texture sheet, subtle density variations, suitable for particle planes.

Negative:

smoke explosion, fire, toxic gas, bright clouds, storm, text.

3D/Animation Notes:

Use as alpha planes or SceneKit particle system. Attention controls fog opacity and distance, not geometry.

## Level 3: 星图寻迹

### Level Design Description

第三关进入“共鸣”，训练转移性注意。玩家面对深空星图，主星按序点亮，用户需要依次锁定当前主星。每次锁定成功，星点爆出柔和光晕并自动连线到下一节点；全部完成后，星座轮廓化为光之灵兽跃出。背景繁星可以有弱 20Hz 底噪干扰，但必须非常小、分散、冷色，不能抢夺主星注意。

### Scene Key Art Prompt

Deep night sky star chart, elegant constellation lines forming a mythic celestial creature silhouette, one warm golden main star glowing brighter than the rest, many small cold blue background stars, subtle nebula dust, premium contemplative fantasy game art, refined astronomical instrument aesthetic, no UI, no text, 16:9 wide composition, high detail, calm and majestic.

### Asset L3-A: Main Star Node

Prompt:

Single magical main star node asset, warm candle-gold core with delicate halo, small precise gaze target, natural star light not UI icon, transparent background, VFX sprite sheet reference, centered, several brightness states from dim to focused glow, elegant premium fantasy style.

Negative:

giant sun, white explosion, cartoon star shape, five-point sticker, lens flare overload, UI icon, text.

3D/Animation Notes:

Use as billboard or small emissive sphere. The active node gets 15Hz emissive modulation. Size must remain small.

### Asset L3-B: Cold Background Star / Distractor

Prompt:

Tiny cold blue background star sprite, subtle icy blue glow, smaller sharper angular distractor silhouette readable without color, low brightness, minimal halo, transparent background, VFX texture, not attention grabbing, premium night sky style.

Negative:

large starburst, bright white, yellow target color, UI sparkle, text.

3D/Animation Notes:

Use many instances. Optional weak 20Hz distractor modulation at low opacity.

### Asset L3-C: Constellation Line Segment

Prompt:

Elegant constellation line VFX reference, thin golden-blue luminous thread connecting stars, soft particles along the line, subtle hand-drawn celestial chart feeling, transparent background, no text, no symbols, refined and minimal.

Negative:

thick laser beam, neon tube, UI connector, circuit line, overbright glow.

3D/Animation Notes:

Use SceneKit cylinders, curves, or shader line mesh. Animate line draw progress after focus success.

### Asset L3-D: Celestial Spirit Creature

Prompt:

Mythic celestial spirit creature made of stars and translucent light, elegant deer-dragon hybrid silhouette inspired by East Asian constellations, no aggression, graceful flowing body, star points embedded along spine and antlers, semi-transparent blue gold nebula material, premium fantasy game asset concept sheet, front side three-quarter view, clean dark neutral background or white background version, full body visible, suitable for 3D modeling.

Negative:

monster, dragon horror, muscular creature, cartoon mascot, overly complex armor, human rider, weapons, text, watermark.

3D/Animation Notes:

Can be static reveal first. Later animate with slow floating spline motion and opacity fade-in. Not the SSVEP target; it is reward feedback after sequence completion.

### Asset L3-E: Star Map Plane

Prompt:

Ancient celestial map surface, faint circular astronomy markings, subtle parchment-gold lines mixed with deep blue night sky, no readable text, elegant sacred geometry, understated, high-end fantasy UI-free background material, square texture reference.

Negative:

visible UI, labels, zodiac text, compass letters, bright white diagram, cluttered symbols.

3D/Animation Notes:

Use as optional distant background plane or debrief motif, not as training HUD.

## Level 4: 真假萤火

### Level Design Description

第四关训练选择性注意与冲动抑制。森林中同时存在黄绿主萤火和幽蓝干扰萤火。用户需要追随黄绿萤火，抑制被蓝光吸引的冲动。专注成功时，中央生命之树由树苗逐渐长成，叶片出现暖绿光脉；若干扰能量超过目标，树干干裂、叶片灰化并散成沙粒。场景要有明确的“生命 vs 冷诱惑”对比，但不能做成红绿灯测试。

### Scene Key Art Prompt

Moonlit forest clearing, two types of fireflies flying through the air, warm yellow green fireflies forming the intended path, cold blue fireflies drifting temptingly at the edges, a small life tree seedling in the center beginning to glow, dark mossy ground, deep forest background, premium fantasy meditation game environment, no UI, no characters, elegant selective attention mood, 16:9.

### Asset L4-A: Green Target Firefly Variant

Prompt:

Bioluminescent yellow green firefly variant, graceful small insect, warm abdomen glow, translucent wings, friendly natural silhouette, premium fantasy realism, orthographic asset sheet front side top three-quarter view, clean white background, clear emissive abdomen material.

Negative:

cartoon bug, scary insect, giant orb, neon cyberpunk, blue glow, text, forest background.

3D/Animation Notes:

Same rig as Level 2 firefly. Abdomen emissive carries 15Hz target modulation.

### Asset L4-B: Blue Distractor Firefly Variant

Prompt:

Cold blue bioluminescent firefly variant, tiny elegant insect, icy blue abdomen glow, translucent wings, slightly sharper and more angular silhouette than the green firefly, smaller colder distractor identity readable without color, premium fantasy realism, orthographic asset sheet front side top three-quarter view, clean white background, clear emissive abdomen material, no baked text.

Negative:

yellow green target color, monster, cartoon, huge light ball, aggressive insect, text.

3D/Animation Notes:

Carries 20Hz distractor modulation. Keep brightness lower than target unless user is failing.

### Asset L4-C: Life Tree Seedling

Prompt:

Small life tree seedling, delicate trunk, two or three young leaves, warm green-gold veins, mossy roots, sacred but natural, premium fantasy meditation asset, orthographic concept sheet front side top view, clean white background, centered, full object visible, PBR bark and leaf material, designed to grow into larger tree.

Negative:

bonsai pot, cartoon sapling, plastic toy, neon tree, UI icon, text.

3D/Animation Notes:

Initial growth stage. Use as SceneKit node with blendshape or scale animation into later stages.

### Asset L4-D: Life Tree Mature Form

Prompt:

Elegant mature life tree, slender trunk, branching canopy with luminous green-gold leaf veins, roots gently spreading into moss, sacred natural form, not giant fantasy world tree, premium indie fantasy game asset, orthographic front side back three-quarter view, clean white background, full tree visible, material separation for bark leaves emissive veins.

Negative:

cartoon tree, Christmas tree, neon cyberpunk, huge glowing ball canopy, faces in bark, horror.

3D/Animation Notes:

Use as final focus state. Could use morph stages: seedling, young tree, mature tree. Leaf vein emissive responds to attention but should not flicker as main SSVEP target.

### Asset L4-E: Withered Tree Variant

Prompt:

Withered version of the same life tree, dry cracked bark, sparse grey leaves, sand-like fragments breaking from lower branches, sorrowful but not horror, premium fantasy asset sheet, front side view, clean white background, full object visible, same silhouette family as mature life tree.

Negative:

horror monster tree, skulls, blood, fire, cartoon, text.

3D/Animation Notes:

Distracted state. Use particle sand fragments and material fade, not instant swap only.

### Asset L4-F: Firefly Path Curve Reference

Prompt:

Elegant curved trail of tiny yellow green firefly lights through a dark forest clearing, subtle dotted path, natural swarm motion reference, no UI arrows, no text, restrained glow, cinematic fantasy meditation mood.

Negative:

arrow path, dotted UI line, neon tube, racing game trail, text.

3D/Animation Notes:

Use spline paths for target firefly swarm. Distractor swarm should move with less predictable edge-biased paths.

## Level 5: 飞燕破云

### Level Design Description

第五关进入动态追踪。玩家在暴风雨夜航中追随一只“引路灵燕”。灵燕是移动主目标，胸口或尾羽有暖金 15Hz 光点；雷云和闪电是 20Hz 干扰。专注时视角稳定，灵燕带玩家穿过云隙；走神时画面轻微颠簸、雨线增强、远处雷光吸引注意。视觉要像电影级夜航，不要像飞机 UI 或射击游戏。

### Scene Key Art Prompt

Stormy night sky flight through dark clouds, a luminous spirit swallow flying ahead as a guide, warm golden light at its chest and tail feathers, cold violet thunderclouds around the path, rain streaks, distant lightning, cinematic motion, premium fantasy game environment, no cockpit UI, no aircraft dashboard, no weapons, 16:9, dramatic but meditative.

### Asset L5-A: Spirit Swallow Body

Prompt:

Elegant spirit swallow bird for premium fantasy meditation game, streamlined body, long forked tail, graceful wings, dark blue-black feathers with subtle gold edges, small warm luminous chest core, orthographic concept sheet front side top three-quarter view, clean white background, full wings visible, clear body wing tail separation, suitable for rigging and flight animation.

Negative:

cartoon bird, robin, eagle, phoenix fire, mechanical drone, aircraft, huge glowing orb, text, background sky.

3D/Animation Notes:

Needs rig: body, left wing, right wing, tail feathers. The chest core or tail tip is the 15Hz SSVEP target. Use flight path spline and wing flap animation.

### Asset L5-B: Spirit Swallow Wing

Prompt:

Single spirit swallow wing isolated, elegant feather layering, dark blue-black feathers, subtle warm gold rim light, long tapered silhouette, orthographic top and side view, clean white background, full wing visible, clear hinge root, PBR feather details, suitable for 3D rigging.

Negative:

angel wing, giant fantasy phoenix flame, cartoon, white dove wing, text, sky background.

3D/Animation Notes:

Use as modeling reference for rigged wings. Hinge at shoulder, flap range subtle and fluid.

### Asset L5-C: Thundercloud Cluster

Prompt:

Dark violet thundercloud cluster, layered storm clouds with cold blue-violet internal lightning glow, sharper peripheral distractor identity, realistic volumetric form, no hard edges, premium cinematic fantasy weather asset reference, isolated on dark neutral background, several cloud shape variations, no text.

Negative:

cartoon cloud icon, bright daylight cloud, tornado, fire explosion, UI symbol.

3D/Animation Notes:

Use volumetric planes, particle billboards, or SceneKit transparent cloud meshes. Lightning emissive areas can carry 20Hz distractor modulation at low area coverage.

### Asset L5-D: Lightning Branch VFX

Prompt:

Cold blue violet lightning branch VFX texture, thin irregular natural lightning forks, transparent background, high contrast but not overexposed, several variations, game VFX sprite sheet, no text, no frame.

Negative:

thick neon laser, UI icon, white screen flash, cartoon zigzag.

3D/Animation Notes:

Use as brief distractor. Never full-screen flash. Keep local area under 5% where possible.

### Asset L5-E: Rain Streak Texture

Prompt:

Fine diagonal rain streak texture sheet, dark storm night, subtle silver blue streaks, transparent background, motion blur reference, high-end cinematic rain VFX, no objects, no text.

Negative:

heavy white lines, snow, waterfall, UI overlay, text.

3D/Animation Notes:

Particle system or alpha planes. Increase density during distraction feedback.

### Asset L5-F: Cloud Gap / Safe Path Reference

Prompt:

Narrow opening through storm clouds, soft moonlit path between dark violet cloud walls, subtle golden swallow trail leading forward, cinematic depth, no UI arrows, no aircraft, premium fantasy night flight mood, 16:9 concept art.

Negative:

road, tunnel, sci-fi portal, neon arrow, cockpit HUD, text.

3D/Animation Notes:

Guides camera composition and spline path for the swallow.

## Level 6: 流星试炼

### Level Design Description

第六关是执行控制与抗干扰训练。场景极简：雪山夜空，山巅孤星。用户需要稳住凝视，不被流星、极光、飞鸟等突发干扰吸引。专注时孤星逐渐化为满月，月光照亮雪峰；走神时月面出现裂痕或被云遮蔽。视觉必须克制、空旷、庄严，目标清晰但不刺眼。

### Scene Key Art Prompt

Minimal snowy mountain peak under vast dark night sky, one warm golden solitary star above the summit, faint aurora at far edges, sparse shooting stars, cold moonlit snow, serene and austere meditation atmosphere, premium indie fantasy game environment, large negative space, no UI, no characters, 16:9 cinematic composition.

### Asset L6-A: Solitary Star / Moon Core

Prompt:

Single solitary star transforming into a moon concept asset, warm gold star core and pale silver moon disk variants, subtle natural glow, not overexposed, transparent background, VFX sprite sheet with stages from small star to crescent to full moon, elegant premium fantasy style.

Negative:

giant sun, cartoon star, emoji moon, face on moon, white explosion, UI icon, text.

3D/Animation Notes:

Main 15Hz target. Use emissive sphere or billboard. Focus state grows star into moon through scale, material blend, and opacity.

### Asset L6-B: Snow Peak Hero Rock

Prompt:

Minimal snow-covered mountain peak hero asset, sharp elegant summit, dark granite exposed under snow, cold blue moonlight, clean iconic silhouette, orthographic front side three-quarter view, clean white background, full object visible, PBR snow and rock material, premium realistic fantasy environment asset.

Negative:

cartoon mountain, volcano, forest hill, buildings, flags, climbers, text.

3D/Animation Notes:

Static central environment anchor. Keep silhouette simple so the star target remains primary.

### Asset L6-C: Aurora Ribbon

Prompt:

Subtle aurora ribbon VFX reference, pale green and blue translucent light curtains, soft flowing bands, dark transparent background, elegant restrained polar night effect, no intense neon, no text, wide horizontal texture.

Negative:

rainbow neon, laser beams, thick smoke, UI gradient, overbright background.

3D/Animation Notes:

Use as slow animated background plane at screen edges. It is a distractor only in later difficulty, not primary target.

### Asset L6-D: Shooting Star Distractor

Prompt:

Small shooting star VFX sprite sheet, cold blue-white meteor streak with warm tiny head, thin elegant trail, sharp transient distractor silhouette readable without color, several angled variations, transparent background, high quality game VFX, not too bright, no screen-filling flare.

Negative:

huge comet, fireball explosion, cartoon star, lens flare burst, text.

3D/Animation Notes:

Transient distractor. Animate across periphery with low duration. Avoid sustained flicker unless testing advanced control.

### Asset L6-E: Moon Crack Overlay

Prompt:

Subtle cracked moon surface overlay, fine dark fracture lines on pale silver disk, elegant not horror, transparent background or isolated moon disk, high detail, restrained, premium fantasy meditation mood.

Negative:

horror blood moon, face, skull, shattered planet explosion, red cracks, text.

3D/Animation Notes:

Distracted feedback. Blend crack texture into moon material based on attention drop.

### Asset L6-F: Dark Cloud Veil

Prompt:

Thin dark cloud veil passing in front of moon, soft smoky blue grey translucent shape, elegant night sky VFX texture, transparent background, several wispy variations, no storm, no text.

Negative:

thick black smoke, explosion, cartoon cloud, daylight cloud, UI.

3D/Animation Notes:

Use as alpha plane crossing the star/moon during distraction feedback.

## Shared UX Assets

### Asset UX-A: Ancient Astrolabe Calibration Device

Prompt:

Ancient celestial astrolabe for meditation calibration, brass and dark jade materials, concentric rings, tiny star engravings, warm candle-gold center light, elegant East Asian astronomical instrument, premium fantasy medical-free interface object, orthographic front side top three-quarter view, clean white background, full object visible, high detail PBR metal material, no readable text.

Negative:

modern UI, digital screen, sci-fi hologram, compass letters, medical device, cyberpunk neon, text, watermark.

3D/Animation Notes:

Calibration phase object. Rings can rotate slowly. Center light can perform sweep-frequency calibration.

### Asset UX-B: Mandala / Star Trail Debrief Motif

Prompt:

Elegant data mandala made of star trails and soft botanical geometry, warm gold and muted green on deep night background, no numbers, no charts, no UI panels, premium contemplative visualization, symmetrical but organic, screenshot-worthy, high-end meditation app reward artwork, 16:9 and square variants.

Negative:

dashboard, bar chart, score, progress ring UI, text labels, cheap app icon, overbright neon.

3D/Animation Notes:

Can remain 2D SwiftUI/Canvas or become background texture. It is not for 3D conversion unless needed.

## Prompt Templates

### Template: Static 3D Asset Sheet

`[asset description], premium contemplative fantasy game asset, natural materials, PBR-friendly, orthographic concept sheet, front view, side view, top view, three-quarter view, centered on clean white background, full object visible, clear silhouette, consistent design across views, high detail, no text, no watermark.`

### Template: Rigged / Animatable Asset Sheet

`[asset description], designed for rigging and animation, separated functional parts, clear hinge/pivot areas, readable joints, front view, side view, top view, three-quarter view, clean white background, full object visible, PBR-friendly material separation, premium fantasy realism, no text, no watermark.`

### Template: VFX Texture

`[effect description], transparent background, game VFX texture sheet, subtle natural glow, restrained brightness, several variations, soft edges, high quality, no UI, no text, no watermark.`

### Template: Scene Key Art

`[level scene description], premium indie fantasy game environment art, contemplative East Asian meditation mood, natural light sources only, no UI, no characters, cinematic 16:9 composition, restrained magical realism, high detail, atmospheric depth, not overexposed.`

## Asset Priority

Build order for a vertical slice:

1. L1 single lotus petal
2. L1 lotus core / stamen target
3. L1 open lotus
4. L1 bud lotus
5. L1 lily pad set
6. L2/L4 firefly body
7. L2 stone monument
8. UX astrolabe
9. L5 spirit swallow body
10. L6 star/moon core

Reason: Level 1 proves the asset-driven pipeline. Fireflies prove particle + emissive SSVEP. Swallow proves rigged moving target. Star/moon proves static executive-control target.

## HIG State Sheet Checklist

Generate these state sheets in addition to hero assets. They support Reduce Motion, VoiceOver semantic announcements, and smooth SceneKit state transitions.

### Level 1 State Sheet

Prompt:

Water lily attention state sheet for a premium macOS mindfulness game, four poses of the same lotus: closed bud, half-open, fully open, gently closing, consistent design, clean white background, orthographic front and top views, warm stamen emissive area visible but not overexposed, calm HIG-compatible wellness aesthetic, no text.

Required semantic states:

- `lotus_closed`
- `lotus_half_open`
- `lotus_open`
- `water_ripples_active`
- `water_calm`

### Level 2 State Sheet

Prompt:

Fog forest attention state sheet, same ancient forest path and stone monument shown in four states: dense fog, medium fog, clear monument silhouette, runes illuminated by fireflies, dark-mode Apple wellness aesthetic, no UI text, no characters, calm premium fantasy realism.

Required semantic states:

- `fog_dense`
- `fog_thinning`
- `monument_visible`
- `runes_lit`

### Level 3 State Sheet

Prompt:

Constellation attention state sheet, same star pattern in four states: unconnected stars, active warm target star, partial constellation line connected, complete celestial creature constellation, dark starfield, restrained golden-blue light, no UI, no text, premium macOS mindfulness aesthetic.

Required semantic states:

- `node_waiting`
- `node_focused`
- `line_connected`
- `constellation_complete`

### Level 4 State Sheet

Prompt:

Selective attention forest state sheet, same clearing in four states: warm green target fireflies gathered, cold blue distractor fireflies at periphery, life tree growing, life tree withering into dust, target and distractor distinguishable by shape and motion identity not only color, no UI, premium calm fantasy realism.

Required semantic states:

- `target_swarm_active`
- `distractor_swarm_active`
- `tree_growing`
- `tree_withering`

### Level 5 State Sheet

Prompt:

Storm flight attention state sheet, same spirit swallow flight scene in four states: swallow clearly visible, stable flight path through clouds, storm intensified with peripheral lightning, swallow obscured by rain, warm target core and cold angular distractors clearly separated, no cockpit UI, no text.

Required semantic states:

- `swallow_visible`
- `flight_stable`
- `storm_intensified`
- `lightning_distraction`

### Level 6 State Sheet

Prompt:

Snow mountain executive control state sheet, same mountain peak and sky in five states: solitary star, crescent moon, full moon, cracked moon, clouded moon, austere dark-mode meditation aesthetic, large negative space, no UI text, no characters, premium Apple-like wellness calm.

Required semantic states:

- `solitary_star`
- `crescent_moon`
- `full_moon`
- `cracked_moon`
- `clouded_moon`

## SceneKit Implementation Intent

Each 3D asset should expose one of these control surfaces:

- `emissiveTarget`: material slot modulated at 15Hz.
- `emissiveDistractor`: material slot modulated at 20Hz.
- `attentionOpenAmount`: 0-1 value for flower/tree/moon growth.
- `attentionFogAmount`: 0-1 value for fog density.
- `pathProgress`: 0-1 value for moving target along spline.
- `failureAmount`: 0-1 value for cracks, withering, cloud cover, jitter.

Do not bake core interactions into the 3D model. Keep them controllable in SceneKit.
