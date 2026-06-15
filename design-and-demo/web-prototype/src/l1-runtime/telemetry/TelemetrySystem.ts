export class TelemetrySystem {
  private logBuffer: string[] = [];
  private readonly telemetryListener = (event: Event): void => {
    const customEvent = event as CustomEvent<{ type: string; data: unknown }>;
    const { type, data } = customEvent.detail;
    this.record(type, data);
  };

  constructor() {
    window.addEventListener("telemetry_event", this.telemetryListener);
  }

  public record(eventType: string, payload: unknown): void {
    const objectPayload =
      payload !== null && typeof payload === "object" ? payload : { payload };
    const logLine = JSON.stringify({
      timestamp: Date.now(),
      event_type: eventType,
      ...objectPayload,
    });

    console.log(`[TELEMETRY JSONL] ${logLine}`);
    this.logBuffer.push(logLine);
  }

  public dumpSessionJSONL(): string {
    return this.logBuffer.join("\n");
  }

  public dispose(): void {
    window.removeEventListener("telemetry_event", this.telemetryListener);
  }
}
