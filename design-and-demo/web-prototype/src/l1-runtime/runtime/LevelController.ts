import type { NeuroFrame } from "../NeuroFrame";

/**
 * Generic contract for a level controller.
 *
 * A level controller consumes standardized NeuroFrame data and produces
 * commands for the visual / video environment.
 */
export interface LevelController<TState, TCommand> {
  /**
   * Current level state.
   */
  readonly state: TState;

  /**
   * Update the level logic with one NeuroFrame.
   *
   * @param frame Standardized neural feedback frame.
   * @param deltaMs Time elapsed since the previous update, in milliseconds.
   */
  update(frame: NeuroFrame, deltaMs: number): TCommand;

  /**
   * Reset the level to its initial state.
   */
  reset(): void;
}