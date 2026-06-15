// DebugMask.ts
export class DebugMask {
  private gl: WebGLRenderingContext;

  private program: WebGLProgram | null = null;
  private colorLoc: WebGLUniformLocation | null = null;
  private alphaLoc: WebGLUniformLocation | null = null;
  private offsetLoc: WebGLUniformLocation | null = null;
  private scaleLoc: WebGLUniformLocation | null = null;
  // 新增：环形宽度控制（可根据需求调整）
  private ringWidth = 0.1;

  public enabled = true;
  public color = [0.0,0.0,1.0]; // 深蓝色
  public opacity = 0.4;

  constructor(gl: WebGLRenderingContext) {
    this.gl = gl;
    this.initShader();
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

    // 核心修改：片元着色器改为绘制环形
    const fsSource = `
      precision mediump float;
      uniform vec3 u_Color;
      uniform float u_Alpha;
      varying vec2 v_Pos;
      void main() {
        float d = length(v_Pos); // 像素到圆心（0,0）的距离
        // 只保留：距离 ≤ 1.0（外边界） 且 距离 ≥ (1.0 - 环形宽度)（内边界）的区域
        if (d > 1.0 || d < (1.0 - ${this.ringWidth})) {
          discard; // 丢弃不在环形范围内的像素
        }
        gl_FragColor = vec4(u_Color, u_Alpha);
      }
    `;

    const gl = this.gl;
    const vs = gl.createShader(gl.VERTEX_SHADER)!;
    gl.shaderSource(vs, vsSource);
    gl.compileShader(vs);

    const fs = gl.createShader(gl.FRAGMENT_SHADER)!;
    gl.shaderSource(fs, fsSource);
    gl.compileShader(fs);

    const program = gl.createProgram()!;
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);
    this.program = program;

    this.colorLoc = gl.getUniformLocation(program, "u_Color");
    this.alphaLoc = gl.getUniformLocation(program, "u_Alpha");
    this.offsetLoc = gl.getUniformLocation(program, "u_Offset");
    this.scaleLoc = gl.getUniformLocation(program, "u_Scale");

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

  draw(glX: number, glY: number, glScale: number) {
    if (!this.enabled || !this.program) return;

    const gl = this.gl;
    gl.useProgram(this.program);

    gl.uniform3fv(this.colorLoc, this.color);
    gl.uniform1f(this.alphaLoc, this.opacity);
    gl.uniform2f(this.offsetLoc, glX, glY);
    gl.uniform1f(this.scaleLoc, glScale * 1.2); // 比目标大一点
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }
}