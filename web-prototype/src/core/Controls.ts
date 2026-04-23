import type { AppState } from './types';
import { LEVEL_NAMES, LEVEL_ENGLISH } from './types';

type OnChange = (state: AppState) => void;

export class Controls {
  private state: AppState;
  private onChange: OnChange;
  private captionEl: HTMLElement;

  constructor(state: AppState, onChange: OnChange) {
    this.state = state;
    this.onChange = onChange;

    this.captionEl = document.getElementById('caption')!;
    this.bindKeys();
  }

  private emit(partial: Partial<AppState>): void {
    Object.assign(this.state, partial);
    this.onChange(this.state);
  }

  updateCaption(dynamicSubtitle?: string): void {
    const i = this.state.activeLevelIndex;
    const sub = dynamicSubtitle ?? LEVEL_ENGLISH[i];
    if (this.captionEl) {
      this.captionEl.innerHTML =
        `<span class="level-name">${LEVEL_NAMES[i]}</span> — ${sub}`;
    }
  }

  private bindKeys(): void {
    window.addEventListener('keydown', (e) => {
      if (e.target instanceof HTMLInputElement) return;

      switch (e.key.toLowerCase()) {
        case 'escape':
          if (this.state.isTraining) {
            this.emit({ isTraining: false });
          }
          break;
        case ' ':
          e.preventDefault();
          this.emit({ paused: !this.state.paused });
          break;
      }
    });
  }
}
