import { describe, expect, it } from "vitest";
import { InvalidStateTransitionError, recoveryAction, TransactionTracker } from "../../src/execution/stateMachine.js";

describe("transaction state machine", () => {
  it("follows the happy path", () => {
    const tracker = new TransactionTracker();
    expect(tracker.transition("SIGNED")).toBe("SIGNED");
    expect(tracker.transition("SUBMITTED")).toBe("SUBMITTED");
    expect(tracker.transition("PENDING")).toBe("PENDING");
    expect(tracker.transition("CONFIRMED")).toBe("CONFIRMED");
  });

  it("rejects a skip from created to confirmed", () => {
    const tracker = new TransactionTracker();
    expect(() => tracker.transition("CONFIRMED")).toThrow(InvalidStateTransitionError);
    expect(tracker.state).toBe("CREATED");
  });

  it("records an unknown outcome after submission", () => {
    const tracker = new TransactionTracker();
    tracker.transition("SIGNED");
    tracker.transition("SUBMITTED");
    expect(tracker.transition("UNKNOWN")).toBe("UNKNOWN");
    expect(recoveryAction(tracker.state)).toBe("RECONCILE");
  });

  it("can settle an unknown transaction without a new submission state", () => {
    const tracker = new TransactionTracker("UNKNOWN");
    expect(tracker.transition("CONFIRMED")).toBe("CONFIRMED");
    expect(recoveryAction("CONFIRMED")).toBe("NONE");
    expect(recoveryAction("FAILED")).toBe("NONE");
    expect(recoveryAction("PENDING")).toBe("CONTINUE");
  });
});
