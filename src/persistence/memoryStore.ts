import type { Hex } from "viem";
import type { DecodedTradeEvent } from "../events/decoder.js";
import type { TradeIntent } from "../execution/types.js";
import type { TransactionState } from "../execution/stateMachine.js";
import type { ReconciliationStatus } from "../reconciliation/reconcile.js";
import { eventIdentity } from "../reconciliation/idempotency.js";

export interface StoredTransaction {
  operationId: Hex;
  transactionHash: Hex | null;
  state: TransactionState;
}

export interface StoredReconciliation {
  operationId: string;
  status: ReconciliationStatus;
  canonicalAmountOut: string | null;
  detail: string;
}

/**
 * In-memory stand-in for the tables in `db/schema.sql`.
 * Amounts stay strings or bigints. This store does not open a database connection.
 */
export class MemoryStore {
  private readonly intents = new Map<string, TradeIntent>();
  private readonly transactions = new Map<string, StoredTransaction>();
  private readonly events = new Map<string, DecodedTradeEvent>();
  private readonly reconciliations: StoredReconciliation[] = [];

  saveIntent(intent: TradeIntent): void {
    this.intents.set(intent.operationId.toLowerCase(), intent);
  }

  getIntent(operationId: string): TradeIntent | undefined {
    return this.intents.get(operationId.toLowerCase());
  }

  saveTransaction(record: StoredTransaction): void {
    this.transactions.set(record.operationId.toLowerCase(), record);
  }

  getTransaction(operationId: string): StoredTransaction | undefined {
    return this.transactions.get(operationId.toLowerCase());
  }

  saveEvent(chainId: number, event: DecodedTradeEvent): { inserted: boolean; identity: string } {
    const identity = eventIdentity(chainId, event.transactionHash, event.logIndex);
    if (this.events.has(identity)) return { inserted: false, identity };
    this.events.set(identity, event);
    return { inserted: true, identity };
  }

  countEvents(): number {
    return this.events.size;
  }

  saveReconciliation(record: StoredReconciliation): void {
    this.reconciliations.push(record);
  }

  listReconciliations(): readonly StoredReconciliation[] {
    return this.reconciliations;
  }
}
