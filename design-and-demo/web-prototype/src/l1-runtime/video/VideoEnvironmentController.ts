/**
 * VideoEnvironmentController — wraps HTMLVideoElement, implements spec Section 7.
 *
 * Manages video segment switching, playback control, and telemetry emission.
 * Does NOT touch WebGL or level logic.
 */

export type VideoSegmentKey =
  | "closedLoop"
  | "openingTransition"
  | "openLoop"
  | "closingTransition";

export type VideoTelemetryEvent =
  | { type: "video_load_start"; segment: VideoSegmentKey; timestampMs: number }
  | { type: "video_load_success"; segment: VideoSegmentKey; timestampMs: number }
  | { type: "video_play"; segment: VideoSegmentKey; timestampMs: number }
  | { type: "video_ended"; segment: VideoSegmentKey; timestampMs: number }
  | { type: "video_error"; segment: VideoSegmentKey; timestampMs: number; message: string };

export interface LevelVideoConfig {
  videos: Record<VideoSegmentKey, string>;
  videoSpec: {
    naturalWidth: number;
    naturalHeight: number;
    expectedFps: number;
  };
}

export class VideoEnvironmentController {
  private videoEl: HTMLVideoElement;
  private currentSegment: VideoSegmentKey | null = null;
  private listeners: Set<(event: VideoTelemetryEvent) => void> = new Set();
  private levelBasePath: string;
  private videoUrls: Record<VideoSegmentKey, string> | null = null;

  constructor(videoEl: HTMLVideoElement, levelBasePath: string = "levels/l1") {
    this.videoEl = videoEl;
    this.levelBasePath = levelBasePath;

    // Listen for video-ended to emit telemetry
    this.videoEl.addEventListener("ended", () => {
      if (this.currentSegment) {
        this.emit({
          type: "video_ended",
          segment: this.currentSegment,
          timestampMs: performance.now(),
        });
      }
    });

    this.videoEl.addEventListener("error", () => {
      if (this.currentSegment) {
        this.emit({
          type: "video_error",
          segment: this.currentSegment,
          timestampMs: performance.now(),
          message: "Video element error",
        });
      }
    });
  }

  /**
   * Load level configuration and pre-check video URLs.
   * Spec Section 4.4: missing resources must produce clear developer errors.
   */
  async loadLevel(config: LevelVideoConfig): Promise<void> {
    this.videoUrls = {} as Record<VideoSegmentKey, string>;

    for (const [key, path] of Object.entries(config.videos)) {
      const url = `${this.levelBasePath}/${path}`;
      this.videoUrls[key as VideoSegmentKey] = url;
    }
  }

  /**
   * Play a video segment. If loop=true, the video will loop.
   * Emits video_load_start, video_load_success, and video_play events.
   */
  async playSegment(
    segment: VideoSegmentKey,
    options: { loop: boolean } = { loop: false }
  ): Promise<void> {
    if (!this.videoUrls) {
      throw new Error("Level not loaded. Call loadLevel() first.");
    }

    const url = this.videoUrls[segment];
    if (!url) {
      throw new Error(
        `LevelResourceError: l1 missing video for segment '${segment}'`
      );
    }

    this.emit({
      type: "video_load_start",
      segment,
      timestampMs: performance.now(),
    });

    // Only change src if segment changed
    if (this.currentSegment !== segment) {
      this.videoEl.src = url;
      this.videoEl.loop = options.loop;
      this.currentSegment = segment;
    }

    try {
      await this.videoEl.play();
      this.emit({
        type: "video_load_success",
        segment,
        timestampMs: performance.now(),
      });
      this.emit({
        type: "video_play",
        segment,
        timestampMs: performance.now(),
      });
    } catch (err) {
      this.emit({
        type: "video_error",
        segment,
        timestampMs: performance.now(),
        message: String(err),
      });
      throw err;
    }
  }

  pause(): void {
    this.videoEl.pause();
  }

  resume(): void {
    this.videoEl.play().catch(() => {});
  }

  getCurrentSegment(): VideoSegmentKey | null {
    return this.currentSegment;
  }

  getVideoElement(): HTMLVideoElement {
    return this.videoEl;
  }

  onEvent(listener: (event: VideoTelemetryEvent) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: VideoTelemetryEvent): void {
    this.listeners.forEach((cb) => cb(event));
    console.log(`[Video] ${event.type}: ${event.segment}`);
  }
}
