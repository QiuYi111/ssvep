// 官方接口
export interface SSVEPStimulusConfig {
  frequencyHz: number;
  opacityMin: number;
  opacityMax: number;
  color: string;
  radius: number;
  modulation: "smooth_sine";
}

export class TargetLight {
  public gl: WebGLRenderingContext;
  public video: HTMLVideoElement;
  public canvas: HTMLCanvasElement;

  // 默认配置：柔光呼吸效果（花心区域亮度调制）
  public config: SSVEPStimulusConfig = {
    frequencyHz: 15,
    opacityMin: 0.18,          // 低相位：微弱暖光
    opacityMax: 0.65,          // 高相位：明显亮度脉冲
    color: "#fff5e0",          // 暖白（匹配金色花心）
    radius: 0.13,              // 大范围覆盖花心区域
    modulation: "smooth_sine"
  };

  private program: WebGLProgram | null = null;
  private colorLoc: WebGLUniformLocation | null = null;
  private alphaLoc: WebGLUniformLocation | null = null;
  private offsetLoc: WebGLUniformLocation | null = null;
  private scaleLoc: WebGLUniformLocation | null = null;

  // 目标位置：固定视频正中心
  public targetPos = { x: 0.5, y: 0.5 };

  // 对外暴露状态（供 telemetry 读取）
  public phase: number = 0;
  public opacity: number = 0;

  constructor(canvas: HTMLCanvasElement, video: HTMLVideoElement) {
    const gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: false });
    if (!gl) throw new Error('不支持WebGL');
    this.gl = gl;
    this.video = video;
    this.canvas = canvas;

    // 混合模式：加法混合（additive）—— 光晕提亮底层视频，不遮挡
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    
    this.initShader();
    this.resize(); // 初始化尺寸
    this.bindResizeListener(); // 监听窗口/视频尺寸变化
  }

  private initShader() {
    const vsSource = `
      attribute vec2 a_Pos;
      uniform vec2 u_Offset;
      uniform float u_Scale;
      varying vec2 v_Pos;

      void main() {
        v_Pos = a_Pos;
        gl_Position = vec4(a_Pos * u_Scale + u_Offset, 0.0, 1.0);
      }
    `;

    const fsSource = `
      precision mediump float;
      uniform vec3 u_Color;
      uniform float u_Alpha;
      varying vec2 v_Pos;

      void main() {
        // 径向距离（0 = 光晕中心, 1 = 光晕边缘）
        float d = length(v_Pos);

        // 高斯式柔和衰减：中心最亮，向外指数衰减
        // sigma=0.45 使得边缘(d=1)处透明度降到中心约 1/150
        float sigma = 0.45;
        float gaussian = exp(-(d * d) / (2.0 * sigma * sigma));

        // 整体透明度 = 正弦调制值 × 高斯径向衰减
        float alpha = u_Alpha * gaussian;

        gl_FragColor = vec4(u_Color, alpha);
      }
    `;

    const gl = this.gl;
    // 编译顶点着色器
    const vs = gl.createShader(gl.VERTEX_SHADER)!;
    gl.shaderSource(vs, vsSource);
    gl.compileShader(vs);
    // 编译片元着色器
    const fs = gl.createShader(gl.FRAGMENT_SHADER)!;
    gl.shaderSource(fs, fsSource);
    gl.compileShader(fs);

    // 创建着色器程序
    const program = gl.createProgram()!;
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);
    this.program = program;

    // 获取 uniform 位置
    this.colorLoc = gl.getUniformLocation(program, "u_Color");
    this.alphaLoc = gl.getUniformLocation(program, "u_Alpha");
    this.offsetLoc = gl.getUniformLocation(program, "u_Offset");
    this.scaleLoc = gl.getUniformLocation(program, "u_Scale");

    // 正方形顶点数据（用于绘制圆形）
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
      gl.STATIC_DRAW
    );

    const posLoc = gl.getAttribLocation(program, "a_Pos");
    gl.enableVertexAttribArray(posLoc);
    gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
  }

  // 十六进制颜色转RGB
  private hexToRgb(hex: string): [number, number, number] {
    const r = parseInt(hex.slice(1, 3), 16) / 255;
    const g = parseInt(hex.slice(3, 5), 16) / 255;
    const b = parseInt(hex.slice(5, 7), 16) / 255;
    return [r, g, b];
  }

  // 计算视频在画布中的真实渲染区域（解决黑边/objectFit问题）
  public getRenderedTargetRect() {
    const { video, canvas, targetPos, config } = this;
    const { videoWidth, videoHeight } = video;
    const rect = canvas.getBoundingClientRect();
    const cssWidth = rect.width;
    const cssHeight = rect.height;

    if (!videoWidth || !videoHeight) {
      return { cssX: cssWidth / 2, cssY: cssHeight / 2, cssRadius: 0 };
    }

    const videoRatio = videoWidth / videoHeight;
    const displayRatio = cssWidth / cssHeight;

    let renderWidth = cssWidth;
    let renderHeight = cssHeight;
    let offsetLeft = 0;
    let offsetTop = 0;

    // 计算视频实际显示区域（去除黑边）
    if (videoRatio > displayRatio) {
      renderHeight = cssWidth / videoRatio;
      offsetTop = (cssHeight - renderHeight) / 2;
    } else {
      renderWidth = cssHeight * videoRatio;
      offsetLeft = (cssWidth - renderWidth) / 2;
    }

    // 目标在视频上的CSS坐标
    const cssX = offsetLeft + targetPos.x * renderWidth;
    const cssY = offsetTop + targetPos.y * renderHeight;
    const cssRadius = config.radius * Math.min(renderWidth, renderHeight);

    return { cssX, cssY, cssRadius };
  }

  // CSS坐标 → WebGL标准设备坐标
  public toWebGLCoords(cssX: number, cssY: number, cssRadius: number) {
    const rect = this.canvas.getBoundingClientRect();
    const cssWidth = rect.width;
    const cssHeight = rect.height;

    // WebGL坐标范围：[-1,1]
    const glX = (cssX / cssWidth) * 2 - 1;
    const glY = 1 - (cssY / cssHeight) * 2;
    const glScale = (cssRadius / cssWidth) * 2;

    return { glX, glY, glScale };
  }

  // 尺寸自适应（DPI+窗口缩放）
  public resize() {
    const dpr = window.devicePixelRatio || 1;
    const rect = this.canvas.getBoundingClientRect();
    
    this.canvas.width = rect.width * dpr;
    this.canvas.height = rect.height * dpr;
    this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
  }

  // 监听尺寸变化
  private bindResizeListener() {
    window.addEventListener('resize', () => this.resize());
    this.video.addEventListener('loadedmetadata', () => this.resize());
  }

  // 外部更新配置（支持level.json热更新）
  public setConfig(newConfig: Partial<SSVEPStimulusConfig>) {
    this.config = { ...this.config, ...newConfig };
  }

  // 核心渲染更新
update() {
  const gl = this.gl;
  if (!this.program) return;

  // ✅ 新增：每次绘制前，切回 TargetLight 的着色器程序
  gl.useProgram(this.program);

  const { cssX, cssY, cssRadius } = this.getRenderedTargetRect();
  const { glX, glY, glScale } = this.toWebGLCoords(cssX, cssY, cssRadius);

  // 15Hz正弦透明度计算（完全满足要求）
  const timeSeconds = performance.now() / 1000;
  this.phase = (timeSeconds * this.config.frequencyHz) % 1;
  const wave = 0.5 + 0.5 * Math.sin(2 * Math.PI * this.phase);
  this.opacity = this.config.opacityMin + wave * (this.config.opacityMax - this.config.opacityMin);

  const color = this.hexToRgb(this.config.color);

  gl.uniform3fv(this.colorLoc!, color);
  gl.uniform1f(this.alphaLoc!, this.opacity);
  gl.uniform2f(this.offsetLoc!, glX, glY);
  gl.uniform1f(this.scaleLoc!, glScale);
  gl.drawArrays(gl.TRIANGLES, 0, 6);
}

  // 独立渲染循环（视频暂停也正常运行）
  start() {
    const loop = () => {
      this.update();
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }
}
