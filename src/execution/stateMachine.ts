export const TRANSACTION_STATES = [
  "CREATED",
  "SIGNED",
  "SUBMITTED",
  "PENDING",
  "CONFIRMED",
  "FAILED",
  "UNKNOWN",
] as const;

export type TransactionState = (typeof TRANSACTION_STATES)[number];

const TRANSITIONS: Record<TransactionState, readonly TransactionState[]> = {
  CREATED: ["SIGNED"],
  SIGNED: ["SUBMITTED", "FAILED"],
  SUBMITTED: ["PENDING", "UNKNOWN", "FAILED"],
  PENDING: ["CONFIRMED", "FAILED", "UNKNOWN"],
  UNKNOWN: ["CONFIRMED", "FAILED", "PENDING"],
  CONFIRMED: [],
  FAILED: [],
};

export class InvalidStateTransitionError extends Error {
  readonly from: TransactionState;
  readonly to: TransactionState;

  constructor(from: TransactionState, to: TransactionState) {
    super(`Illegal transaction transition: ${from} -> ${to}`);
    this.name = "InvalidStateTransitionError";
    this.from = from;
    this.to = to;
  }
}

export function canTransition(from: TransactionState, to: TransactionState): boolean {
  return TRANSITIONS[from].includes(to);
}

export function assertTransition(from: TransactionState, to: TransactionState): void {
  if (!canTransition(from, to)) throw new InvalidStateTransitionError(from, to);
}

/** Tracks one transaction. It never submits or resubmits a transaction. */
export class TransactionTracker {
  private current: TransactionState;

  constructor(initial: TransactionState = "CREATED") {
    this.current = initial;
  }

  get state(): TransactionState {
    return this.current;
  }

  transition(to: TransactionState): TransactionState {
    assertTransition(this.current, to);
    this.current = to;
    return this.current;
  }
}

export type RecoveryAction = "CONTINUE" | "RECONCILE" | "NONE";

/**
 * What an operator may do next.
 * UNKNOWN means reconcile the hash that was already submitted. It does not mean send again.
 */
export function recoveryAction(state: TransactionState): RecoveryAction {
  if (state === "UNKNOWN") return "RECONCILE";
  if (state === "CONFIRMED" || state === "FAILED") return "NONE";
  return "CONTINUE";
}
