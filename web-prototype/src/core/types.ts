export interface AppState {
  time: number;
  attention: number;
  targetFrequency: number;
  distractorFrequency: number;
  bloomStrength: number;
  particleDensity: number;
  reduceMotion: boolean;
  paused: boolean;
  activeLevelIndex: number;
  showTargetMask: boolean;
  debugVisible: boolean;
  currentView: string; // 'home', 'calibrate', 'settings', 'level-detail'
  selectedLevelIndex: number;
  isTraining: boolean;
}

export interface RenderContext {
  ctx: CanvasRenderingContext2D;
  width: number;
  height: number;
  dpr: number;
}

export const LEVEL_NAMES = [
  '涟漪绽放', '萤火引路', '星图寻迹',
  '真假萤火', '飞燕破云', '流星试炼',
] as const;

export const LEVEL_ENGLISH = [
  'Lotus Lake', 'Firefly Forest', 'Constellation Trace',
  'Dual Fireflies', 'Storm Swallow', 'Meteor Trial',
] as const;

export const LEVEL_DETAILS = [
  {
    title: 'L1 涟漪绽放',
    desc: '觉察呼吸与身体，建立专注的锚点。',
    target: '凝视花蕊',
    advice: '呼吸 · 轻柔回到当下',
    duration: '10-15 分钟',
    status: '平稳',
    banner: '/banners/l1.png',
    icon: '/icons/l1.png'
  },
  {
    title: 'L2 雾林寻迹',
    desc: '在迷雾中穿行，捕捉流动的微光。',
    target: '跟随前方暖光',
    advice: '保持稳定注视',
    duration: '15-20 分钟',
    status: '挑战',
    banner: '/banners/l2.png',
    icon: '/icons/l2.png'
  },
  {
    title: 'L3 星轨连心',
    desc: '连接散落的觉知，编织成内在的完整。',
    target: '连接下一颗星',
    advice: '让目光缓慢停留',
    duration: '12-18 分钟',
    status: '深邃',
    banner: '/banners/l3.png',
    icon: '/icons/l3.png'
  },
  {
    title: 'L4 真假萤火',
    desc: '真假交织，保持内心的纯净。',
    target: '辨别真实之光',
    advice: '追随暖色光点',
    duration: '10 分钟',
    status: '高阶',
    banner: '/banners/l4.png',
    icon: '/icons/l4.png'
  },
  {
    title: 'L5 飞燕破云',
    desc: '风雨交加，守住内心的稳，穿云而过。',
    target: '守住飞燕',
    advice: '不追随闪电',
    duration: '20-30 分钟',
    status: '沉浸',
    banner: '/banners/l5.png',
    icon: '/icons/l5.png'
  },
  {
    title: 'L6 流星试炼',
    desc: '在纷繁的流星中，守住唯一的恒星。',
    target: '稳住焦点',
    advice: '流星掠过也不偏移',
    duration: '5-10 分钟',
    status: '爆发',
    banner: '/banners/l6.png',
    icon: '/icons/l6.png'
  }
];

export function defaultState(): AppState {
  return {
    time: 0,
    attention: 0.5,
    targetFrequency: 15,
    distractorFrequency: 20,
    bloomStrength: 0.5,
    particleDensity: 0.7,
    reduceMotion: false,
    paused: false,
    activeLevelIndex: 0,
    showTargetMask: false,
    debugVisible: false,
    currentView: 'home',
    selectedLevelIndex: 0,
    isTraining: false,
  };
}
