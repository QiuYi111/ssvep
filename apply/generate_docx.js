const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, Header, Footer, AlignmentType, LevelFormat,
  HeadingLevel, BorderStyle, WidthType, ShadingType,
  PageNumber, PageBreak, TabStopType, TabStopPosition,
} = require("docx");

const PAGE_W = 11906;
const PAGE_H = 16838;
const MARGIN_TOP = 1440;
const MARGIN_BOT = 1440;
const MARGIN_LEFT = 1800;
const MARGIN_RIGHT = 1800;
const CONTENT_W = PAGE_W - MARGIN_LEFT - MARGIN_RIGHT;

const FONT_SONG = "宋体";
const FONT_HEI = "黑体";
const FONT_KAI = "楷体";

const archImg = fs.readFileSync("/Users/qiujingyi.7/ssvep/apply/arch_diagram.png");
const techImg = fs.readFileSync("/Users/qiujingyi.7/ssvep/apply/techflow_diagram.png");
const hwImg = fs.readFileSync("/Users/qiujingyi.7/ssvep/apply/hardware_photo.png");

const ARCH_W = 580;
const ARCH_H = Math.round(580 * 2282 / 2368);
const TECH_W = 580;
const TECH_H = Math.round(580 * 170 / 2768);
const HW_W = 450;
const HW_H = Math.round(450 * 2339 / 1654);

function bodyPara(runs, opts = {}) {
  return new Paragraph({
    spacing: { before: 60, after: 60, line: 360 },
    indent: opts.noIndent ? undefined : { firstLine: 420 },
    alignment: opts.alignment,
    children: Array.isArray(runs) ? runs : [runs],
    ...opts.extra,
  });
}

function bodyText(text, opts = {}) {
  return new TextRun({
    text,
    font: FONT_SONG,
    size: 21,
    bold: opts.bold,
    italics: opts.italics,
    ...opts,
  });
}

function heading1(text) {
  return new Paragraph({
    spacing: { before: 360, after: 200, line: 360 },
    children: [new TextRun({ text, font: FONT_HEI, size: 28, bold: true })],
  });
}

function heading2(text) {
  return new Paragraph({
    spacing: { before: 240, after: 120, line: 360 },
    children: [new TextRun({ text, font: FONT_HEI, size: 24, bold: true })],
  });
}

function heading3(text) {
  return new Paragraph({
    spacing: { before: 200, after: 100, line: 360 },
    children: [new TextRun({ text, font: FONT_HEI, size: 22, bold: true })],
  });
}

function figureCaption(text) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 120, after: 200 },
    children: [new TextRun({ text, font: FONT_KAI, size: 18, italics: true })],
  });
}

const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: "999999" };
const cellBorders = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };
const cellMargins = { top: 60, bottom: 60, left: 100, right: 100 };

function headerCell(text, width) {
  return new TableCell({
    borders: cellBorders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: "D5E8F0", type: ShadingType.CLEAR },
    margins: cellMargins,
    verticalAlign: "center",
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text, font: FONT_SONG, size: 18, bold: true })],
    })],
  });
}

function dataCell(text, width, opts = {}) {
  return new TableCell({
    borders: cellBorders,
    width: { size: width, type: WidthType.DXA },
    margins: cellMargins,
    verticalAlign: "center",
    children: [new Paragraph({
      alignment: opts.align || AlignmentType.CENTER,
      children: [new TextRun({ text, font: FONT_SONG, size: 18 })],
    })],
  });
}

function makeTable(headers, rows, colWidths) {
  const tableWidth = colWidths.reduce((a, b) => a + b, 0);
  return new Table({
    width: { size: tableWidth, type: WidthType.DXA },
    columnWidths: colWidths,
    rows: [
      new TableRow({ children: headers.map((h, i) => headerCell(h, colWidths[i])) }),
      ...rows.map(row => new TableRow({
        children: row.map((cell, i) => dataCell(cell, colWidths[i])),
      })),
    ],
  });
}

function refPara(text) {
  return new Paragraph({
    spacing: { before: 40, after: 40, line: 300 },
    indent: { left: 420, hanging: 420 },
    children: [new TextRun({ text, font: FONT_SONG, size: 18 })],
  });
}

function imagePara(imgData, w, h, altTitle) {
  return new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 200, after: 0 },
    children: [new ImageRun({
      type: "png",
      data: imgData,
      transformation: { width: w, height: h },
      altText: { title: altTitle || "Diagram", description: altTitle || "System diagram", name: altTitle || "diagram" },
    })],
  });
}

function bulletItem(text) {
  return new Paragraph({
    numbering: { reference: "bullets", level: 0 },
    spacing: { before: 40, after: 40, line: 360 },
    children: [bodyText(text)],
  });
}

function numberedItem(text) {
  return new Paragraph({
    numbering: { reference: "numbers", level: 0 },
    spacing: { before: 40, after: 40, line: 360 },
    children: [bodyText(text)],
  });
}

function boldLead(lead, rest) {
  return bodyPara([
    new TextRun({ text: lead, font: FONT_SONG, size: 21, bold: true }),
    bodyText(rest),
  ]);
}

function sup(text) {
  return bodyText(text, { superScript: true });
}

const b = (t) => new TextRun({ text: t, font: FONT_SONG, size: 21, bold: true });

var HW_H_FINAL = HW_H;
try {
  const sizeOf = require("image-size");
  const dim = sizeOf("/Users/qiujingyi.7/ssvep/apply/hardware_photo.png");
  HW_H_FINAL = Math.round(HW_W * dim.height / dim.width);
} catch (e) {
  HW_H_FINAL = HW_H;
}

const doc = new Document({
  styles: {
    default: {
      document: { run: { font: FONT_SONG, size: 21 } },
    },
    paragraphStyles: [
      {
        id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: FONT_HEI },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 },
      },
      {
        id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, font: FONT_HEI },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 },
      },
    ],
  },
  numbering: {
    config: [
      {
        reference: "bullets",
        levels: [{
          level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 840, hanging: 420 } } },
        }],
      },
      {
        reference: "numbers",
        levels: [{
          level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 840, hanging: 420 } } },
        }],
      },
    ],
  },
  sections: [{
    properties: {
      page: {
        size: { width: PAGE_W, height: PAGE_H },
        margin: { top: MARGIN_TOP, bottom: MARGIN_BOT, left: MARGIN_LEFT, right: MARGIN_RIGHT },
      },
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ children: [PageNumber.CURRENT], font: FONT_SONG, size: 18 })],
        })],
      }),
    },
    children: [
      // ===== Title =====
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 600, after: 400, line: 480 },
        children: [new TextRun({
          text: `星空与萤火：基于SSVEP空间注意力调制的沉浸式注意力训练系统`,
          font: FONT_HEI, size: 44, bold: true,
        })],
      }),

      // ===================================================================
      // 一、背景与引入
      // ===================================================================
      heading1(`一、背景与引入`),

      bodyPara([
        bodyText(`注意力缺陷已成为影响公共健康的重大挑战。全球约5\u20137%的儿童和2.5\u20134%的成年人受注意力缺陷多动障碍（ADHD）困扰`),
        sup(`[1]`),
        bodyText(`，而更为广泛的亚临床注意力涣散问题在信息过载时代日益普遍。传统注意力训练手段包括药物治疗（如哌甲酯）和行为认知疗法（CBT），但前者存在副作用和依赖风险，后者疗程长、依从性差。基于脑电（EEG）的神经反馈技术为注意力训练提供了一条非药物的闭环干预路径——通过实时反馈脑电信号，引导用户自主调节大脑活动模式`),
        sup(`[2]`),
        bodyText(`。`),
      ]),

      bodyPara([
        bodyText(`现有EEG注意力训练产品在三个层面存在瓶颈。信号范式方面，主流方案以额叶（PFC）\u03B2波（13\u201330 Hz）功率作为注意力指标`),
        sup(`[3]`),
        bodyText(`，但该信号易受肌电（EMG）和眼动伪迹干扰，且PFC电极需精确定位，佩戴体验差。反馈形式方面，现有产品普遍采用进度条、数值仪表盘等\u201C游戏化\u201DHUD元素，将医疗训练伪装为低龄游戏，既缺乏审美品质，也难以维持成年用户的长期使用动机`),
        sup(`[4]`),
        bodyText(`。近年来的系统综述表明，基于BCI的注意力训练游戏确实能有效降低ADHD症状`),
        sup(`[9]`),
        bodyText(`，但现有系统的反馈形式仍以传统2D界面为主`),
        sup(`[16]`),
        bodyText(`。使用场景方面，多数系统仍局限于医疗机构，缺乏面向家庭场景的便携化、日常化设计。`),
      ]),

      bodyPara([
        bodyText(`稳态视觉诱发电位（Steady-State Visual Evoked Potential, SSVEP）为突破上述瓶颈提供了新的技术路径。当用户凝视以特定频率闪烁的视觉刺激时，其枕叶视皮层会产生同频率的稳态脑电响应`),
        sup(`[5]`),
        bodyText(`。与传统PFC \u03B2波范式相比，SSVEP信号集中在特定频率成分，可通过频谱分析精确提取`),
        sup(`[6]`),
        bodyText(`，信噪比显著更高；枕叶信号受肌电干扰远小于额叶`),
        sup(`[7]`),
        bodyText(`；更重要的是，SSVEP幅值直接反映用户对特定空间位置的注意聚焦程度`),
        sup(`[8]`),
        bodyText(`，这与\u201C注意力训练\u201D的目标天然契合——我们不再监测大脑整体激活状态，而是精确评估注意力的空间聚焦位置。`),
      ]),

      bodyPara(bodyText(`基于上述分析，本项目提出\u201C星空与萤火\u201D——一套基于SSVEP空间注意力调制的沉浸式注意力训练系统。该系统将东方正念冥想的修心哲学与独立游戏的视觉美学结合，通过\u201C无HUD\u201D（No-HUD）设计范式，将神经反馈信号伪装为自然场景中的光影变化，实现\u201C训练即体验\u201D的无感化干预。用户在体验过程中不会看到进度条、得分面板或能量柱。所有脑电反馈全部通过自然界的光影、天气、植物生长和环境音效来呈现。`)),

      // ===================================================================
      // 二、系统整体设计思路
      // ===================================================================
      heading1(`二、系统整体设计思路`),

      heading2(`2.1 设计理念`),

      bodyPara([
        bodyText(`本系统的核心设计哲学是`),
        b(`\u201C无HUD注意力训练\u201D`),
        bodyText(`。训练过程中绝对禁止出现传统医疗软件的进度条、得分、能量柱或任何UI面板。所有SSVEP闪烁源必须伪装为自然场景中合理的发光元素——萤火虫、星光、水面波光、篝火、极光。注意力反馈则转化为环境叙事变化：莲花绽放，树木生长，雾气消散，星辰连结。用户不会意识到自己正在\u201C训练\u201D，而是沉浸在一个宁静而美丽的世界中。`),
      ]),

      bodyPara(bodyText(`这一理念从三个维度展开。`)),

      bodyPara([
        bodyText(`视觉语义掩蔽（Semantic Masking）是设计的第一层约束。SSVEP范式在物理上要求特定频率的闪烁刺激，但如果用户看到的是屏幕上的方块在闪，体验就失败了。我们的做法是：将所有闪烁源嵌入自然叙事逻辑中。花蕊散发的暖金光晕（15 Hz）、萤火虫腹部规律的生物荧光（15 Hz）、星辰柔和的脉动（15 Hz）——这些闪烁在自然界中本就存在，用户不会将其感知为\u201C刺激\u201D，而是\u201C光\u201D。色彩层面同样有严格的语义约束：目标刺激统一使用温暖或治愈的生命色（生物荧光绿 #cddc39、暖烛光 #ffe9a6），干扰刺激则使用冰冷或深邃的背景色（幽冷星蓝 #8ab4f8、暗紫雷云 #4a148c）。颜色本身就是叙事——暖色是你要追随的，冷色是你要忽略的，用户不需要读任何说明就能直觉理解。在防疲劳渲染上，系统采用局部高光闪烁（目标区域占屏幕面积不到5%）配合透明度正弦波形变（60%\u2013100%平滑波动），绝不使用大面积0\u2013100%的方波硬闪。这意味着，即便用户盯着目标看二十分钟，也不会感到视觉疲劳。`),
      ]),

      bodyPara(bodyText(`视觉之外，跨模态听觉诱导构成第二层反馈。视觉反馈的延迟必须与听觉同步（<100ms），形成双脑回路的闭环。当用户进入专注状态（SSVEP达标），声景中引入丰满的低频——大提琴长音、颂钵共鸣声、清脆的风铃声——同时加入等时音（Isochronic Tones）辅助脑波同步。当用户走神（SSVEP掉零），音乐瞬间失去低频（Low-pass filter开启），只留下干涩的风声和枯叶摩擦声。声音的变化与视觉光影的变化在时间上严格同步，用户甚至不需要\u201C看到\u201D反馈就能\u201C听到\u201D自己走神了。`)),

      bodyPara(bodyText(`保持用户处于认知最优区间则需要动态难度调节。系统不会让用户一直停留在同一个难度上。如果算法检测到用户连续3分钟保持高专注状态，会自动降低主目标的对比度——花蕊的光变淡，萤火虫的亮光收缩——迫使注意力系统付出更多努力来维持锁定。反过来，如果用户持续受挫（SSVEP持续低下），主目标会发出引导性的脉冲光，干扰项自动变暗，相当于\u201C扶着用户走一段\u201D。这种机制确保训练始终处于认知负荷的最优区间，既不过于轻松，也不令人绝望。`)),

      heading2(`2.2 系统总体架构`),

      imagePara(archImg, ARCH_W, ARCH_H, "系统总体架构图"),
      figureCaption(`图1：系统总体架构图。系统采用\u201C采集\u2014处理\u2014渲染\u2014反馈\u201D四层闭环架构：EEG信号经蓝牙采集后送入信号处理层进行CCA频谱分析，计算出的注意力指数AI驱动场景渲染层产生视觉反馈，形成闭环。`),

      bodyPara(bodyText(`如图1所示，系统采用\u201C采集\u2014处理\u2014渲染\u2014反馈\u201D的四层闭环架构：`)),

      numberedItem(`信号采集层：通过华南脑控五通道脑电头环（电极位置：O1、O2、C3、C4及前额参考电极）采集用户枕叶区SSVEP信号，经蓝牙5.0传输至上位机；`),
      numberedItem(`信号处理层：在HybridBCI平台上执行带通滤波（5\u201350 Hz）\u2192 独立成分分析（ICA）去伪迹 \u2192 快速傅里叶变换（FFT）频谱分析 \u2192 SSVEP目标频率功率提取，计算实时注意力指数（Attention Index, AI）；`),
      numberedItem(`场景渲染层：基于AI值驱动Canvas 2D/WebGL渲染引擎，以场景叙事方式呈现注意力反馈。AI > 0.7触发正向反馈（花开、雾散、星空明亮），AI < 0.3触发柔和引导（暖光增亮、场景微动）；`),
      numberedItem(`用户交互层：提供关卡选择、标定流程、训练计时等交互功能，同时保持视觉界面的简洁与沉浸感。`),

      heading2(`2.3 六级渐进式训练体系`),

      bodyPara(bodyText(`系统设计了六个训练关卡，遵循\u201C觉察\u2192聚焦\u2192辨别\u2192抗干扰\u2192沉浸\u2192高峰\u201D的渐进认知负荷递增原则。`)),

      heading3(`境界一：觉醒（Awakening）—— 持续性注意力构建`),

      bodyPara(bodyText(`前两关不设置干扰刺激，目标是激活顶枕叶视觉皮层，建立基础的SSVEP共振回路。`)),

      makeTable(
        [`关卡`, `名称`, `训练目标`, `SSVEP目标`, `干扰刺激`],
        [
          [`1`, `涟漪绽放`, `呼吸觉察与基础注视`, `花蕊暖金色，15 Hz`, `无`],
          [`2`, `萤火引路`, `稳定追踪与注意力维持`, `萤火虫群，15 Hz`, `无`],
        ],
        [900, 1200, 2200, 2200, 1806],
      ),

      bodyPara([
        b(`关卡1：涟漪绽放。`),
        bodyText(`暗色湖面，中央含苞睡莲。注意力聚焦时花蕊散发暖金波光，水面荡起涟漪，花瓣层层绽放；走神时花瓣缓缓闭合，水面归于静止。核心隐喻：注意力即生命力。`),
      ]),

      bodyPara([
        b(`关卡2：萤火引路。`),
        bodyText(`迷雾黑森林，萤火虫群缓缓飞舞。注意力维持时萤光增强、驱散迷雾，远处石碑上的古老符文逐一亮起；走神时迷雾从四面合拢。用户想看清石碑上写了什么——这个好奇心本身就是维持注意力的天然锚点。`),
      ]),

      heading3(`境界二：共鸣（Resonance）—— 转移性与选择性注意力`),

      bodyPara(bodyText(`从关卡3开始，系统引入诱惑性干扰刺激。训练大脑在多个目标间精准转移注意力，或主动抑制对错误目标的冲动响应。这一阶段的临床意义尤为突出——ADHD患者最核心的缺陷之一正是在干扰存在时维持目标注意的能力。`)),

      makeTable(
        [`关卡`, `名称`, `训练目标`, `SSVEP目标`, `干扰刺激`],
        [
          [`3`, `星图寻迹`, `空间搜索与选择性注意`, `金色星图，15 Hz`, `蓝色星图，20 Hz`],
          [`4`, `真假萤火`, `目标辨别与抗干扰`, `黄绿萤火虫，15 Hz`, `蓝色萤火虫，20 Hz`],
        ],
        [900, 1200, 2200, 2200, 1806],
      ),

      bodyPara([
        b(`关卡3：星图寻迹。`),
        bodyText(`繁星夜空，金色主星（15 Hz）与冷蓝背景星（20 Hz）。锁定主星后星座连线完成，化为光之灵兽跃出星图；被蓝光吸引则连线断裂。训练转移性注意——星空中有那么多光，你只追随特定的那一颗。`),
      ]),

      bodyPara([
        b(`关卡4：真假萤火。`),
        bodyText(`森林中黄绿（15 Hz）与蓝色（20 Hz）萤火虫混飞，数量相当。追踪目标萤火时生命之树从地面长出；蓝色SSVEP反超则树木枯萎化为沙砾。训练选择性注意与冲动抑制——在充满诱惑的环境中维持目标锁定，直接迁移到现实中的\u201C嘈杂环境专注\u201D。`),
      ]),

      heading3(`境界三：心流（Flow State）—— 动态追踪与高级执行控制`),

      bodyPara(bodyText(`最后两关模拟真实世界的复杂挑战（如驾驶、激烈运动中的注意力分配）。目标开始移动，同时引入突发性瞬态干扰。`)),

      makeTable(
        [`关卡`, `名称`, `训练目标`, `SSVEP目标`, `干扰刺激`],
        [
          [`5`, `飞燕破云`, `持续抗扰与情绪调节`, `飞燕胸光，15 Hz`, `闪电，20 Hz`],
          [`6`, `流星试炼`, `高负荷注意力分配与峰值体验`, `星\u2192月，15 Hz`, `流星+极光，20 Hz`],
        ],
        [900, 1200, 2200, 2200, 1806],
      ),

      bodyPara([
        b(`关卡5：飞燕破云。`),
        bodyText(`暴风雨夜空，引路灵燕动态飞舞（15 Hz），闪电为干扰（20 Hz）。追踪灵燕则平稳穿梭于云层；被闪电吸引则画面剧烈颠簸。灵燕运动轨迹基于历史注意力数据自适应调节——追踪好则飞更高更远，频繁失误则放慢靠近。训练平滑追踪眼动与强干扰下动态目标锁定。`),
      ]),

      bodyPara([
        b(`关卡6：流星试炼。`),
        bodyText(`雪山夜空孤星（15 Hz），干扰为极光、流星、飞鸟群——精心设计触发人类本能的运动捕捉和新奇刺激导向反射。持续锁定则孤星膨胀化为满月，清辉洒满雪山顶；眼跳则满月裂痕或被乌云遮蔽。最终挑战——\u201C八风吹不动\u201D，整个训练中最接近巅峰体验的时刻。`),
      ]),

      heading2(`2.4 主要创新点`),

      boldLead(`创新点一：基于SSVEP空间注意力调制的注意力闭环训练范式`, ``),
      bodyPara([
        bodyText(`传统EEG注意力训练依赖PFC \u03B2波信号`),
        sup(`[3]`),
        bodyText(`，易受干扰，信噪比低。本项目改用SSVEP空间调制范式：SSVEP直接反映用户对特定空间位置的注意聚焦程度`),
        sup(`[8]`),
        bodyText(`，频域特征集中，枕叶采集受肌电和眼动干扰小。这意味着注意力训练从\u201C监测大脑整体激活状态的粗粒度估计\u201D推进到\u201C精确评估空间注意力聚焦位置的细粒度测量\u201D。在实践中，系统能够区分用户是在注视15 Hz的暖色目标还是20 Hz的冷色干扰——这种区分能力是\u03B2波范式做不到的。`),
      ]),

      boldLead(`创新点二：\u201C无HUD\u201D医疗级神经反馈伪装为自然场景叙事`, ``),
      bodyPara([
        bodyText(`现有神经反馈产品普遍使用进度条、仪表盘等游戏化HUD元素`),
        sup(`[4]`),
        bodyText(`，审美疲劳快，成年用户依从性差。本项目提出的\u201C无HUD\u201D设计范式，将SSVEP视觉刺激伪装为自然场景中的发光元素（花蕊、萤火虫、星辰），注意力反馈转化为环境叙事变化（莲花绽放、树木生长、雾气消散），同时通过跨模态听觉诱导（专注时低频丰厚的颂钵声\u2192走神时干涩的风声）和动态难度调节（连续专注3分钟自动降低对比度\u2192持续受挫时干扰自动变暗）构建沉浸感。视觉语义掩蔽策略确保所有闪烁在物理上满足SSVEP范式要求，在感知上却被用户理解为\u201C自然光影\u201D。据我们所知，这一设计尚无在临床神经反馈系统中完全消除数字界面元素的先例，尝试将医疗设备的交互品质提升至消费级产品的美学水平。`),
      ]),

      boldLead(`创新点三：东方正念哲学与SSVEP神经科学的跨学科融合`, ``),
      bodyPara(bodyText(`现有注意力训练系统缺乏文化适应性和长期使用动机。本项目将东方正念冥想的修心哲学——\u201C不追随、不抗拒\u201D的觉察态度——与SSVEP神经科学原理结合。每个关卡对应一个正念修习阶段（觉察\u2192聚焦\u2192辨别\u2192坚定\u2192超越），训练引导语采用冥想引导而非游戏指令。关卡4的\u201C生命之树\u201D隐喻正念中\u201C善念如树、恶念如沙\u201D的意象；关卡6的\u201C八风吹不动\u201D直接来自禅宗公案。这种融合将注意力的\u201C认知训练\u201D重新定义为\u201C正念修习\u201D，通过叙事和美学设计赋予训练过程以意义感和仪式感，从而激发用户的内在动机。`)),

      // ===================================================================
      // 三、系统实现路径
      // ===================================================================
      heading1(`三、系统实现路径`),

      heading2(`3.1 技术路线概述`),

      imagePara(techImg, TECH_W, TECH_H, "技术路线图"),
      figureCaption(`图2：系统实现三阶段技术路线。阶段一（已完成）：基于Web技术栈的六关卡视觉原型验证；阶段二（进行中）：接入华南脑控EEG头环，实现CCA闭环集成；阶段三（规划中）：迁移至macOS原生平台，实现临床级SSVEP刺激精度。`),

      bodyPara(bodyText(`如图2所示，系统实现分为三个阶段：视觉原型验证（已完成）\u2192 SSVEP闭环集成（进行中）\u2192 原生平台迁移（规划中）。`)),

      heading2(`3.2 阶段一：视觉原型验证（已完成）`),

      bodyPara(bodyText(`基于Web技术栈构建了完整的六关卡视觉原型，用于验证SSVEP目标伪装策略和注意力驱动反馈的视觉可行性。`)),

      boldLead(`技术选型`, `：Vite + TypeScript + Canvas 2D，零运行时依赖，保证渲染帧率稳定在60 FPS。采用Canvas 2D而非WebGL的原因是：SSVEP视觉刺激的核心需求是精确的亮度调制（55\u2013100%正弦波）而非复杂3D渲染，Canvas 2D的globalAlpha属性可直接实现亚像素级透明度控制。`),

      boldLead(`核心模块实现`, `：`),
      bulletItem(`SSVEP时序引擎（Timing.ts）：实现ssvepOpacity(time, frequency, min, max)函数，通过正弦波sin(time \u00D7 2\u03C0 \u00D7 frequency)生成精确的亮度调制曲线，频率精度由requestAnimationFrame时间戳保证；`),
      bulletItem(`场景渲染框架（LevelRenderer抽象基类）：定义六关卡统一接口draw(ctx, state)，每个关卡继承并实现独立的粒子系统、噪声场和注意力驱动逻辑；`),
      bulletItem(`注意力模拟器（Controls.ts）：Debug面板提供0\u20131连续注意力值滑块，支持实时调节目标频率（5\u201330 Hz）、干扰频率、粒子密度等参数，用于离线验证视觉反馈效果。`),

      boldLead(`验证成果`, `：六关卡视觉原型已在1440\u00D7900分辨率、DPR=2条件下稳定运行，SSVEP目标区域占屏幕面积<5%，亮度调制范围严格控制在55\u2013100%，确认了\u201C将SSVEP刺激伪装为自然发光元素\u201D这一核心策略的视觉可行性。`),

      heading2(`3.3 阶段二：SSVEP闭环集成（进行中）`),

      bodyPara(bodyText(`本阶段核心任务是将视觉原型与真实EEG信号源对接，构建\u201CEEG采集\u2192SSVEP解析\u2192注意力计算\u2192场景反馈\u201D的完整闭环。`)),

      boldLead(`EEG信号接入`, `：通过Web Bluetooth API连接华南脑控五通道脑电头环，获取O1/O2枕叶区原始EEG数据。信号采样率250 Hz，经蓝牙5.0传输至浏览器端。`),

      bodyPara([
        b(`SSVEP信号处理`),
        bodyText(`：采用CCA（典型相关分析）算法进行SSVEP频率检测`),
        sup(`[10]`),
        bodyText(`。具体流程为：（1）5\u201350 Hz带通滤波去除直流偏移和高频噪声；（2）ICA去除眼电和肌电伪迹；（3）对1秒滑动窗口数据进行CCA分析，以目标频率及其谐波生成参考信号，计算相关系数作为SSVEP检测置信度；（4）对目标频率（15 Hz）和干扰频率（20 Hz）的SSVEP响应功率比值计算注意力指数AI = P_target / (P_target + P_distractor)。`),
      ]),

      bodyPara(bodyText(`注意力驱动反馈：AI值经0.5秒滑动平均平滑后映射为场景参数。正向反馈（AI > 0.7）对应目标元素增亮、粒子密度增加、场景细节丰富化（花瓣绽放、雾气消散）。中性状态（0.3 < AI < 0.7）维持场景当前状态，仅有微幅呼吸感动画。引导反馈（AI < 0.3）下目标区域暖光柔和增亮、引导粒子缓慢向目标汇聚——系统不会惩罚走神的用户，而是温和地把注意力\u201C牵\u201D回来。`)),

      heading2(`3.4 阶段三：原生平台迁移（规划中）`),

      bodyPara(bodyText(`Web原型的requestAnimationFrame无法保证SSVEP所需的亚毫秒级时间精度。为实现临床级SSVEP刺激，计划迁移至macOS原生平台：`)),

      bulletItem(`渲染引擎：Metal API + CADisplayLink，确保帧精确到VSync（16.67ms@60Hz）；`),
      bulletItem(`SSVEP刺激控制：通过MTLRenderPassDescriptor的colorAttachments直接控制像素亮度，实现硬件级精确频率调制；`),
      bulletItem(`信号处理：BrainFlow C++ SDK，支持实时EEG流处理、滤波和特征提取；`),
      bulletItem(`UI框架：SwiftUI构建关卡选择和系统设置界面；`),
      bulletItem(`音频引擎：Tone.js + Howler.js实现跨模态听觉诱导，低频双声拍（binaural beats）辅助注意力聚焦。`),

      // Duplicate section number 3.4 — 可行性论证 (matches the markdown)
      heading2(`3.4 可行性论证`),

      bodyPara([
        bodyText(`本项目的技术可行性基于三个已验证的基础。硬件层面，华南脑控IHNNK五通道脑电头环由项目资助方直接提供，其O1/O2枕叶电极布局专为采集视觉皮层SSVEP信号设计，250 Hz采样率的奈奎斯特频率（125 Hz）远高于本项目所需检测的最高频率成分（20 Hz基频 + 2次谐波40 Hz），信号采集能力有充分裕量。算法层面，CCA算法是SSVEP频率检测的经典方法`),
        sup(`[10]`),
        bodyText(`，近年来进一步发展出eTRCA`),
        sup(`[12]`),
        bodyText(`、CCA-USSR`),
        sup(`[13]`),
        bodyText(`等增强方案，在少通道条件下仍能保持较高识别率。本项目仅需区分两个固定频率（15 Hz vs 20 Hz），远低于常规SSVEP-BCI拼写器所需的40+频率识别量，算法难度显著降低。已有研究表明，基于游戏的BCI注意力训练在ADHD儿童中可行`),
        sup(`[14]`),
        bodyText(`，且神经反馈组的改善显著优于纯游戏对照组`),
        sup(`[15]`),
        bodyText(`。原型层面，阶段一已完成六关卡视觉原型的完整实现与验证（详见3.2节），确认了SSVEP视觉伪装策略和注意力驱动反馈的可行性。`),
      ]),

      // ===================================================================
      // 四、系统预期应用价值和场景
      // ===================================================================
      heading1(`四、系统预期应用价值和场景`),

      heading2(`4.1 核心应用场景`),

      boldLead(`场景一：ADHD辅助干预`, ``),
      bodyPara(bodyText(`面向确诊ADHD的儿童和青少年，作为药物治疗的非药物补充方案。系统通过渐进式训练关卡，从基础注视（关卡1\u20132）逐步过渡到抗干扰训练（关卡4\u20136），帮助ADHD患者提升持续性注意力和选择性注意力。关卡4\u201C真假萤火\u201D中\u201C在大量同质干扰中锁定特定目标\u201D的训练逻辑，直接对应ADHD患者在课堂上\u201C在嘈杂教室中专注于老师说话\u201D的核心困难。预计单次训练时长15\u201320分钟，建议频率每日1\u20132次，持续8\u201312周为一个训练周期。`)),

      boldLead(`场景二：大众注意力健康维护`, ``),
      bodyPara(bodyText(`面向注意力涣散的亚健康人群（如高压职场人士、考研学生），提供日常化注意力维护工具。\u201C无HUD\u201D设计使系统同时具备冥想引导和注意力训练的双重功能，用户无需承担\u201C接受治疗\u201D的心理负担。关卡1\u201C涟漪绽放\u201D和关卡2\u201C萤火引路\u201D的体验与冥想引导几乎无法区分——坐在工位上，戴上头环，看着湖面睡莲缓缓绽放十分钟，回到工作时的专注状态会有明显改善。预计单次体验10\u201315分钟，适合工作间隙或睡前使用。`)),

      boldLead(`场景三：正念冥想辅助`, ``),
      bodyPara(bodyText(`面向正念冥想练习者，提供基于生理信号的冥想深度反馈。传统的冥想练习缺乏客观反馈，用户难以判断自己是否\u201C入定\u201D。本系统通过SSVEP信号量化冥想中的注意力聚焦程度，并以自然场景变化给予实时引导——当用户真正进入深度专注时，满天的星辰会亮起来，或一棵光之树在面前长成；当走神时，场景会安静地\u201C睡去\u201D。这种反馈比任何冥想老师的口头指导都更直观。`)),

      heading2(`4.2 预期技术指标`),

      makeTable(
        [`指标`, `预期目标`],
        [
          [`SSVEP检测准确率`, `\u2265 85%（CCA算法，5次平均）`],
          [`注意力反馈延迟`, `\u2264 500 ms（采集\u2192解析\u2192渲染全链路）`],
          [`系统帧率`, `\u2265 60 FPS（稳定，无掉帧）`],
          [`单次训练时长`, `10\u201330 分钟（可配置）`],
          [`用户依从性（8周留存率）`, `\u2265 60%（目标值，待临床验证）`],
        ],
        [4000, 4306],
      ),

      heading2(`4.3 可扩展性`),

      bodyPara([
        bodyText(`本系统的技术框架支持多维度扩展。频段层面，SSVEP目标频率可从当前8\u201330 Hz扩展至40 Hz以上的高频SSVEP区域`),
        sup(`[11]`),
        bodyText(`，当用户达到\u201C明心\u201D境界后解锁不可见频率模式，闪烁完全融入自然光变，视觉体验更为舒适。范式层面，可在SSVEP基础上叠加P300或运动想象范式，实现多模态脑机接口。场景层面，六关卡框架支持快速开发新主题（海洋、竹林、雪山），适配不同用户的审美偏好和临床需求。`),
      ]),

      // ===================================================================
      // 五、应用系统的软硬件说明
      // ===================================================================
      heading1(`五、应用系统的软硬件说明`),

      heading2(`5.1 硬件配置`),

      imagePara(hwImg, HW_W, HW_H_FINAL, "硬件照片"),
      figureCaption(`图3：华南脑控IHNNK五通道脑电头环构件示意图。头环配备O1、O2枕叶区AgCl电极、C3/C4中央区电极及前额水凝胶参考电极，通过拨动键和双压按键可拆卸清洗头带。`),

      makeTable(
        [`设备`, `型号/规格`, `来源`, `用途`],
        [
          [`EEG采集设备`, `华南脑控IHNNK五通道脑电头环`, `项目资助方提供`, `采集O1、O2、C3、C4及前额参考电极的EEG信号`],
          [`EEG处理平台`, `HybridBCI开发板`, `项目资助方提供`, `EEG信号预处理、蓝牙传输控制`],
          [`用户终端`, `个人计算机（macOS 14+ / Windows 10+）`, `用户自备`, `运行训练软件，渲染视觉场景`],
          [`显示器`, `60 Hz以上刷新率显示器（推荐144 Hz）`, `用户自备`, `显示SSVEP视觉刺激`],
        ],
        [1500, 2400, 1200, 3206],
      ),

      bodyPara(bodyText(`华南脑控IHNNK五通道脑电头环由项目资助方提供，无需额外采购。该头环采用AgCl湿电极（O1、O2、C3、C4位置配合电极膏渗透头发确保头皮接触）和水凝胶电极（前额位置），通过蓝牙5.0与上位机通信，采样率250 Hz，奈奎斯特频率125 Hz，远高于本项目20 Hz目标频率的检测需求。HybridBCI开发板同样由资助方提供，负责EEG信号预处理和蓝牙传输控制。`)),

      heading2(`5.2 软件配置`),

      makeTable(
        [`软件/框架`, `版本`, `来源`, `用途`],
        [
          [`TypeScript`, `5.x`, `开源`, `核心开发语言，严格类型安全`],
          [`Vite`, `6.x`, `开源`, `构建工具，开发服务器`],
          [`Canvas 2D / WebGL`, `浏览器原生`, `内置`, `场景渲染和SSVEP亮度调制`],
          [`Web Bluetooth API`, `浏览器原生`, `内置`, `EEG头环蓝牙连接和数据传输`],
          [`BrainFlow (WASM)`, `最新版`, `开源`, `EEG信号处理（滤波、ICA、CCA）`],
          [`Simplex Noise`, `自实现`, `自研`, `场景噪声场和粒子系统`],
          [`Metal API`, `\u2014`, `Apple原生`, `原生版本SSVEP渲染（阶段三）`],
          [`SwiftUI`, `\u2014`, `Apple原生`, `原生版本UI框架（阶段三）`],
        ],
        [1800, 1200, 1200, 4106],
      ),

      bodyPara(bodyText(`全部软件依赖均为开源或平台原生组件，无商业许可成本。`)),

      // ===================================================================
      // 参考文献
      // ===================================================================
      heading1(`参考文献`),

      refPara(`[1] Polanczyk G V, Willcutt E G, Salum G A, et al. ADHD prevalence estimates across three decades: an updated systematic review and meta-regression analysis. International Journal of Epidemiology, 2014, 43(2): 434\u2013442.`),
      refPara(`[2] Gruzelier J H. EEG-neurofeedback for optimising performance. III: A review of methodological and theoretical considerations. Neuroscience & Biobehavioral Reviews, 2014, 44: 159\u2013182.`),
      refPara(`[3] Loo S K, Barkley R A. Clinical utility of EEG in attention deficit hyperactivity disorder. Applied Neuropsychology, 2005, 12(2): 64\u201376.`),
      refPara(`[4] Enriquez-Geppert S, Huster R J, Herrmann C S. EEG-neurofeedback as a tool to modulate cognition and behavior: A review tutorial. Frontiers in Human Neuroscience, 2017, 11: 51.`),
      refPara(`[5] Norcia A M, Appelbaum L G, Ales J M, et al. The steady-state visual evoked potential in vision research: A review. Journal of Vision, 2015, 15(6): 4.`),
      refPara(`[6] Vialatte F B, Maurice M, Dauwels J, et al. Steady-state visually evoked potentials: Focus on essential paradigms and future perspectives. Progress in Neurobiology, 2010, 90(4): 418\u2013438.`),
      refPara(`[7] Morgan S T, Hansen J C, Hillyard S A. Selective attention to stimulus location modulates the steady-state visual evoked potential. Proceedings of the National Academy of Sciences, 1996, 93(10): 4770\u20134774.`),
      refPara(`[8] Kelly S P, Lalor E C, Reilly R B, et al. Visual spatial attention tracking using high-density SSVEP data for independent brain-computer communication. IEEE Transactions on Neural Systems and Rehabilitation Engineering, 2005, 13(2): 172\u2013178.`),
      refPara(`[9] Raza M Z, Omais M, Arshad H M E, et al. Effectiveness of Brain-Computer Interface (BCI)-Based Attention Training Game System for Symptom Reduction, Behavioral Enhancement, and Brain Function Modulation in Children With ADHD: A Systematic Review and Single-Arm Meta-Analysis. NeuroRegulation, 2025, 12(1): 51\u201378.`),
      refPara(`[10] Lin Z, Zhang C, Wu W, et al. Frequency recognition based on canonical correlation analysis for SSVEP-based BCIs. IEEE Transactions on Biomedical Engineering, 2006, 53(12): 2610\u20132614.`),
      refPara(`[11] Chen X, Wang Y, Nakanishi M, et al. High-speed spelling with a noninvasive brain-computer interface. Proceedings of the National Academy of Sciences, 2015, 112(44): E6058\u2013E6067.`),
      refPara(`[12] Wei Q, Li C, Wang Y, et al. Enhancing the performance of SSVEP-based BCIs by combining task-related component analysis and deep neural network. Scientific Reports, 2025, 15: 365.`),
      refPara(`[13] Chen R, Xu G, Zhang H, et al. A novel untrained SSVEP-EEG feature enhancement method using canonical correlation analysis and underdamped second-order stochastic resonance. Frontiers in Neuroscience, 2023, 17: 1246940.`),
      refPara(`[14] Lim C G, Soh C P, Lim S S Y, et al. Home-based brain\u2013computer interface attention training program for attention deficit hyperactivity disorder: a feasibility trial. Child and Adolescent Psychiatry and Mental Health, 2023, 17: 15.`),
      refPara(`[15] Yan C, Liu Y, Zhao J, et al. Integrating single-channel EEG neurofeedback into video game-based digital therapeutics for ADHD. Journal of NeuroEngineering and Rehabilitation, 2026, 23: 124.`),
      refPara(`[16] Kober S E, Wood G, Berger L M. Controlling Virtual Reality With Brain Signals: State of the Art of Using VR-Based Feedback in Neurofeedback Applications. Applied Psychophysiology and Biofeedback, 2025, 50: 593\u2013612.`),
    ],
  }],
});

Packer.toBuffer(doc).then(buffer => {
  const outPath = `/Users/qiujingyi.7/ssvep/apply/星空与萤火_申报书.docx`;
  fs.writeFileSync(outPath, buffer);
  console.log(`Document generated: ${outPath} (${buffer.length} bytes)`);
}).catch(err => {
  console.error(`Error:`, err);
  process.exit(1);
});
