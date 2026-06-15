/**
 * TelemetryEvents — all 7 event types per spec Section 9.
 *
 * M1 must produce JSONL telemetry output. Every line is one event.
 */

import type { NeuroFrame } from "../NeuroFrame";
import type { L1VisualState } from "../levels/L1Controller";

// ── Session events ────────────────────────────────────────

export interface SessionStartEvent {
  type: "session_start";
  timestampMs: number;
  levelId: string;
  runtimeMode: "training" | "developer";
}

export interface SessionEndEvent {
  type: "session_end";
  timestampMs: number;
  levelId: string;
  durationMs: number;
}

// ── NeuroFrame event ──────────────────────────────────────

export interface NeuroFrameEvent {
  type: "neuro_frame";
  timestampMs: number;
  frame: NeuroFrame;
}

// ── State transition event ────────────────────────────────

export interface L1StateTransitionEvent {
  type: "l1_state_transition";
  timestampMs: number;
  from: L1VisualState;
  to: L1VisualState;
  reason: string;
  bloomProgress: number;
}

// ── Video events ──────────────────────────────────────────

export interface VideoLoadStartEvent {
  type: "video_load_start";
  segment: string;
  timestampMs: number;
}

export interface VideoLoadSuccessEvent {
  type: "video_load_success";
  segment: string;
  timestampMs: number;
}

export interface VideoPlayEvent {
  type: "video_play";
  segment: string;
  timestampMs: number;
}

export interface VideoEndedEvent {
  type: "video_ended";
  segment: string;
  timestampMs: number;
}

export interface VideoErrorEvent {
  type: "video_error";
  segment: string;
  timestampMs: number;
  message: string;
}

export type VideoTelemetryEvent =
  | VideoLoadStartEvent
  | VideoLoadSuccessEvent
  | VideoPlayEvent
  | VideoEndedEvent
  | VideoErrorEvent;

// ── Stimulus frame event ──────────────────────────────────

export interface StimulusFrameEvent {
  type: "stimulus_frame";
  timestampMs: number;
  targetFrequencyHz: number;
  phase: number;
  opacity: number;
  rafDeltaMs: number;
  droppedFrameEstimate: boolean;
  videoSegment: string;
  l1State: L1VisualState;
}

// ── Runtime error event ───────────────────────────────────

export interface RuntimeErrorEvent {
  type: "runtime_error";
  timestampMs: number;
  code: string;
  message: string;
  context?: unknown;
}

// ── Union type ────────────────────────────────────────────

export type TelemetryEvent =
  | SessionStartEvent
  | SessionEndEvent
  | NeuroFrameEvent
  | L1StateTransitionEvent
  | VideoTelemetryEvent
  | StimulusFrameEvent
  | RuntimeErrorEvent;
