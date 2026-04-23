import { defaultState, LEVEL_DETAILS } from './types';
import type { AppState } from './types';
import { safeDt } from './Timing';
import { MarkdownRenderer } from '../utils/MarkdownRenderer';

export class App {
  private state: AppState;
  private animId = 0;
  private lastTime = 0;
  
  private mainEl: HTMLElement;
  private sidebarEl: HTMLElement;
  private videoEl: HTMLVideoElement | null = null;
  private timerEl: HTMLElement | null = null;

  constructor() {
    this.state = defaultState();
    this.mainEl = document.getElementById('main-content')!;
    this.sidebarEl = document.getElementById('sidebar')!;

    this.bindUIEvents();
    this.renderUI();
  }

  private onStateChange(): void {
    this.renderUI();
  }

  private bindUIEvents(): void {
    this.sidebarEl.addEventListener('click', (e) => {
      const target = e.target as HTMLElement;
      const navItem = target.closest('.nav-item') as HTMLElement;
      if (!navItem) return;

      const view = navItem.dataset.view;
      const levelIdx = navItem.dataset.level;

      if (view) {
        this.state.currentView = view;
        this.state.activeLevelIndex = -2; // Reset
        this.renderUI();
      } else if (levelIdx !== undefined) {
        this.state.currentView = 'level-detail';
        this.state.selectedLevelIndex = parseInt(levelIdx);
        this.state.activeLevelIndex = -2; // Reset
        this.renderUI();
      }
    });
  }

  private renderUI(): void {
    // Update sidebar active state
    this.sidebarEl.querySelectorAll('.nav-item').forEach(item => {
      const i = item as HTMLElement;
      const isTrainingThisLevel = this.state.currentView === 'training' && i.dataset.level === String(this.state.activeLevelIndex);
      const isTrainingCalibrate = this.state.currentView === 'training' && i.dataset.view === 'calibrate' && this.state.activeLevelIndex === -1;
      
      const isActive = (i.dataset.view === this.state.currentView) ||
                       (i.dataset.level === String(this.state.selectedLevelIndex) && this.state.currentView === 'level-detail') ||
                       isTrainingThisLevel || isTrainingCalibrate;
      
      i.classList.toggle('active', isActive);
      
      // Update text to "训练中" if training
      if (isTrainingThisLevel || isTrainingCalibrate) {
        const textNode = i.childNodes[i.childNodes.length - 1];
        if (textNode.nodeType === Node.TEXT_NODE) {
           const baseName = isTrainingCalibrate ? '标定' : LEVEL_DETAILS[this.state.activeLevelIndex].title;
           textNode.textContent = ` ${baseName} 训练中`;
        }
      } else {
        // Reset text
        const textNode = i.childNodes[i.childNodes.length - 1];
        if (textNode.nodeType === Node.TEXT_NODE) {
           if (i.dataset.view === 'calibrate') textNode.textContent = ' 标定';
           else if (i.dataset.view === 'about') textNode.textContent = ' 关于';
           else if (i.dataset.level !== undefined) textNode.textContent = ` ${LEVEL_DETAILS[parseInt(i.dataset.level)].title}`;
           else if (i.dataset.view === 'home') textNode.textContent = ' 首页';
        }
      }
    });

    if (this.state.currentView === 'home') {
      this.renderHome();
    } else if (this.state.currentView === 'calibrate') {
      this.renderCalibrate();
    } else if (this.state.currentView === 'level-detail') {
      this.renderLevelDetail(this.state.selectedLevelIndex);
    } else if (this.state.currentView === 'about') {
      this.renderAbout();
    } else if (this.state.currentView === 'training') {
      this.renderTraining();
    }
  }

  private renderTraining(): void {
    const isCalibrate = this.state.activeLevelIndex === -1;
    const levelIdx = this.state.activeLevelIndex;
    const level = isCalibrate ? { title: '标定', target: '请凝视中心光点', advice: '放松双眼 · 保持稳定注视' } : LEVEL_DETAILS[levelIdx];
    const videoSrc = isCalibrate ? '/videos/calibrate.mp4' : `/videos/l${levelIdx + 1}.mp4`;
    const layoutClass = isCalibrate ? 'layout-calibrate' : `layout-l${levelIdx + 1}`;

    this.mainEl.innerHTML = `
      <div class="training-view ${layoutClass}">
        <video id="training-video" autoplay loop muted playsinline src="${videoSrc}"></video>
        
        <div class="training-ui-top-left">
          <div class="glass-capsule status-tag">
            <span id="status-text">${isCalibrate ? '标定中' : level.title + ' 训练中'}</span>
          </div>
          <div class="training-instruction" id="instruction-text">${level.target}</div>
        </div>

        <div class="training-ui-top-right">
          <div class="glass-capsule timer-tag" id="timer-text">00:00</div>
          <button class="glass-capsule icon-btn" id="btn-pause-training">
            <div class="pause-icon"></div>
          </button>
        </div>

        <div class="training-ui-bottom">
          <div class="glass-capsule advice-tag">
            <span id="advice-text">${level.advice}</span>
          </div>
        </div>
      </div>
    `;

    this.videoEl = document.getElementById('training-video') as HTMLVideoElement;
    this.timerEl = document.getElementById('timer-text')!;
    this.state.time = 0;
    this.state.paused = false;

    document.getElementById('btn-pause-training')?.addEventListener('click', () => {
      this.state.paused = !this.state.paused;
      if (this.state.paused) this.videoEl?.pause();
      else this.videoEl?.play();
    });

    this.lastTime = performance.now();
    if (this.animId) cancelAnimationFrame(this.animId);
    this.tick(this.lastTime);
  }

  private async renderAbout(): Promise<void> {
    this.mainEl.innerHTML = `<div class="about-container"><p style="opacity: 0.5;">Loading...</p></div>`;
    
    try {
      const response = await fetch('/about.md');
      const markdown = await response.text();
      const contentHtml = MarkdownRenderer.render(markdown);

      this.mainEl.innerHTML = `
        <div class="about-container">
          <div class="about-header">
            <div class="breadcrumb">ⓘ About</div>
          </div>
          
          <div class="about-hero">
            <div class="hero-content">
              <h1>关于本系统</h1>
              <p class="subtitle">从 SSVEP 到场景化注意力训练：我们为什么这样设计本系统</p>
              <div class="meta-info">
                <span>⚛︎ 研究性博客</span>
                <span>☉ v0.1</span>
                <span>⊞ Demo</span>
                <span>🕒 更新于 2026</span>
              </div>
            </div>
          </div>

          <div class="about-body">
            ${contentHtml}
          </div>
        </div>
      `;
    } catch (err) {
      this.mainEl.innerHTML = `<div class="about-container"><p>Failed to load about.md</p></div>`;
    }
  }

  private renderCalibrate(): void {
    this.mainEl.innerHTML = `
      <div class="view-container">
        <div class="hero-banner" style="background-image: url('/banners/calibrate.png')">
          <div class="hero-overlay">
            <h2>标定关卡</h2>
            <p>与频率共鸣，找到稳定的凝视。</p>
          </div>
        </div>

        <div class="action-card">
          <div class="action-info">
            <div class="action-icon"><img src="/icons/calibrate.png" /></div>
            <div class="action-text">
              <h3>静心凝视，感受星轨的流动</h3>
              <p>在不追随、不抗拒中，让视线与星轨自然同频，建立内在的稳定中心。</p>
            </div>
          </div>
          <button class="btn-primary" id="btn-start-calibrate">开始标定</button>
        </div>
      </div>
    `;

    document.getElementById('btn-start-calibrate')?.addEventListener('click', () => {
      this.state.currentView = 'training';
      this.state.activeLevelIndex = -1;
      this.renderUI();
    });
  }

  private renderHome(): void {
    this.mainEl.innerHTML = `
      <div class="view-container">
        <div class="hero-banner" style="background-image: url('/banners/home.png')">
          <div class="hero-overlay">
            <h2>欢迎回来</h2>
            <p>在宁静中训练专注，在专注中遇见更好的自己。</p>
          </div>
        </div>
        
        <h3 style="margin-bottom: 24px; font-weight: 500; font-size: 1.25rem;">训练关卡</h3>
        <div class="level-grid">
          ${LEVEL_DETAILS.map((l, i) => `
            <div class="level-card" data-index="${i}">
              <div class="level-thumb" style="background-image: url('${l.banner}')"></div>
              <div class="level-info">
                <h3>${l.title}</h3>
                <p>${l.desc}</p>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;

    this.mainEl.querySelectorAll('.level-card').forEach(card => {
      card.addEventListener('click', () => {
        this.state.currentView = 'level-detail';
        this.state.selectedLevelIndex = parseInt((card as HTMLElement).dataset.index!);
        this.renderUI();
      });
    });
  }

  private renderLevelDetail(index: number): void {
    const level = LEVEL_DETAILS[index];
    this.mainEl.innerHTML = `
      <div class="view-container">
        <div class="hero-banner" style="background-image: url('${level.banner}')">
          <div class="hero-overlay">
            <h2>${level.title}</h2>
            <p>${level.desc}</p>
          </div>
        </div>

        <div class="action-card">
          <div class="action-info">
            <div class="action-icon"><img src="${level.icon}" /></div>
            <div class="action-text">
              <h3>专注起点</h3>
              <p>${level.target}</p>
              <p style="margin-top: 4px; font-size: 0.85rem; opacity: 0.6;">建议时长: ${level.duration}</p>
            </div>
          </div>
          <button class="btn-primary" id="btn-start-training">开始训练</button>
        </div>
      </div>
    `;

    document.getElementById('btn-start-training')?.addEventListener('click', () => {
      this.state.currentView = 'training';
      this.state.activeLevelIndex = index;
      this.renderUI();
    });
  }

  private tick = (now: number): void => {
    if (this.state.currentView !== 'training') return;

    const rawDt = (now - this.lastTime) / 1000;
    this.lastTime = now;
    const dt = safeDt(rawDt);

    if (!this.state.paused) {
      this.state.time += dt;
      
      if (this.state.activeLevelIndex === 3 || this.state.activeLevelIndex === 4) {
        if (this.videoEl && this.videoEl.currentTime >= 2) {
          this.videoEl.currentTime = 0;
        }
      }
      
      if (this.timerEl) {
        const mins = Math.floor(this.state.time / 60);
        const secs = Math.floor(this.state.time % 60);
        this.timerEl.textContent = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
      }
    }

    this.animId = requestAnimationFrame(this.tick);
  }

  registerLevel(index: number, level: any): void {
    // Legacy support for main.ts, but we use video mocks now
  }

  start(): void {
    this.renderUI();
  }
}
