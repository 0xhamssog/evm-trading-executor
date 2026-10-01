import { encodeFunctionData, type Address, type Hex } from "viem";
import type { Logger } from "pino";
import { tradingExecutorAbi } from "../abi/tradingExecutor.js";
import { findTradeExecuted, type DecodedTradeEvent, type TradeLog, type TradeResult } from "../events/decoder.js";
import { logExecution } from "../logging/logger.js";
import { MemoryStore } from "../persistence/memoryStore.js";
import { assessIntent, assessSimulatedSlippage } from "../risk/engine.js";
import { reconcile, type ReconciliationResult } from "../reconciliation/reconcile.js";
import { TransactionTracker, type TransactionState } from "./stateMachine.js";
import type { CheckStatus, RiskPolicy, TradeIntent } from "./types.js";

export class LiveExecutionDisabledError extends Error {
  constructor() {
    super("Broadcast is disabled. Set EXECUTION_MODE=TESTNET to submit a transaction.");
    this.name = "LiveExecutionDisabledError";
  }
}

export class IntentRejectedError extends Error {
  readonly reasons: readonly string[];

  constructor(reasons: readonly string[]) {
    super(`Trade intent rejected: ${reasons.join("; ")}`);
    this.name = "IntentRejectedError";
    this.reasons = reasons;
  }
}

export class OperationAlreadySubmittedError extends Error {
  constructor(operationId: string) {
    super(`Operation ${operationId} was already submitted. Reconcile it instead of sending another transaction.`);
    this.name = "OperationAlreadySubmittedError";
  }
}

export interface ChainReceipt {
  status: "success" | "reverted";
  transactionHash: Hex;
  blockNumber: bigint;
  logs: TradeLog[];
}

/** Narrow chain port. A viem adapter can implement this. Tests use a fake. */
export interface ExecutionChain {
  send(input: { to: Address; data: Hex }): Promise<Hex>;
  waitForReceipt(hash: Hex): Promise<ChainReceipt | "TIMEOUT">;
}

export interface SimulatedExecution {
  mode: "SIMULATED";
  state: "SIMULATED";
  intent: TradeIntent;
  calldata: Hex;
  checks: {
    authorization: CheckStatus;
    routerAllowlist: CheckStatus;
    tokenAllowlist: CheckStatus;
    slippage: CheckStatus;
    deadline: CheckStatus;
  };
  broadcast: false;
}

export interface LiveExecutionResult {
  mode: "TESTNET";
  state: TransactionState;
  operationId: Hex;
  transactionHash: Hex | null;
  trade: TradeResult | null;
  reconciliation: ReconciliationResult;
  resubmitted: false;
}

export interface ExecutorClientOptions {
  mode: "SIMULATED" | "TESTNET";
  chainId: number;
  executorAddress: Address;
  policy: RiskPolicy;
  store: MemoryStore;
  logger: Logger;
  chain?: ExecutionChain;
}

/** Encode `executeTrade`. The quote is intentionally absent from the calldata. */
export function encodeExecuteTrade(intent: TradeIntent): Hex {
  return encodeFunctionData({
    abi: tradingExecutorAbi,
    functionName: "executeTrade",
    args: [
      intent.operationId,
      intent.router,
      intent.tokenIn,
      intent.tokenOut,
      intent.amountIn,
      intent.minAmountOut,
      intent.deadline,
      intent.recipient,
    ],
  });
}

/**
 * Execution layer. It accepts a trade intent, encodes it, and tracks the transaction.
 * It does not contain strategy logic and it does not resubmit after an RPC timeout.
 */
export class TradingExecutorClient {
  constructor(private readonly options: ExecutorClientOptions) {}

  encode(intent: TradeIntent): Hex {
    return encodeExecuteTrade(intent);
  }

  simulate(intent: TradeIntent, simulatedAmountOut: bigint): SimulatedExecution {
    const decision = assessIntent(intent, this.options.policy);
    return {
      mode: "SIMULATED",
      state: "SIMULATED",
      intent,
      calldata: this.encode(intent),
      checks: {
        authorization: decision.authorization,
        routerAllowlist: decision.routerAllowlist,
        tokenAllowlist: decision.tokenAllowlist,
        slippage: assessSimulatedSlippage(simulatedAmountOut, intent.minAmountOut),
        deadline: decision.deadline,
      },
      broadcast: false,
    };
  }

  async execute(intent: TradeIntent, simulatedAmountOut: bigint): Promise<SimulatedExecution | LiveExecutionResult> {
    if (this.options.mode !== "TESTNET") return this.simulate(intent, simulatedAmountOut);
    return this.submit(intent);
  }

  async submit(intent: TradeIntent): Promise<LiveExecutionResult> {
    if (this.options.mode !== "TESTNET" || !this.options.chain) throw new LiveExecutionDisabledError();
    if (this.options.store.getTransaction(intent.operationId)) {
      throw new OperationAlreadySubmittedError(intent.operationId);
    }

    const decision = assessIntent(intent, this.options.policy);
    if (!decision.accepted) throw new IntentRejectedError(decision.reasons);

    const started = Date.now();
    const tracker = new TransactionTracker();
    this.options.store.saveIntent(intent);
    tracker.transition("SIGNED");

    let hash: Hex;
    try {
      hash = await this.options.chain.send({ to: this.options.executorAddress, data: this.encode(intent) });
    } catch (error) {
      tracker.transition("FAILED");
      this.persistTransaction(intent.operationId, null, tracker.state);
      throw error;
    }

    tracker.transition("SUBMITTED");
    this.persistTransaction(intent.operationId, hash, tracker.state);
    logExecution(this.options.logger, {
      msg: "execution submitted",
      operationId: intent.operationId,
      transactionHash: hash,
      router: intent.router,
      tokenIn: intent.tokenIn,
      tokenOut: intent.tokenOut,
      state: tracker.state,
      durationMs: Date.now() - started,
    });

    tracker.transition("PENDING");
    const receipt = await this.wait(hash);
    return this.finish(intent, tracker, hash, receipt);
  }

  /**
   * Move an already submitted operation forward from a receipt.
   * Does not call the chain send path.
   */
  reconcileSubmitted(operationId: Hex, receipt: ChainReceipt | null): ReconciliationResult {
    const intent = this.options.store.getIntent(operationId);
    const stored = this.options.store.getTransaction(operationId);
    if (!intent || !stored) throw new Error(`No local record for operation ${operationId}`);

    const tracker = new TransactionTracker(stored.state);
    const trade = receipt ? findTradeExecuted(receipt.logs) : null;
    if (trade) this.options.store.saveEvent(this.options.chainId, trade);
    this.settle(tracker, receipt, trade);
    this.persistTransaction(operationId, stored.transactionHash, tracker.state);

    const reconciliation = reconcile({
      local: this.localRecord(intent, tracker.state, stored.transactionHash),
      receipt: receipt
        ? {
            status: receipt.status,
            transactionHash: receipt.transactionHash,
            blockNumber: receipt.blockNumber.toString(),
          }
        : null,
      trade,
    });
    this.options.store.saveReconciliation({
      operationId,
      status: reconciliation.status,
      canonicalAmountOut: reconciliation.canonicalAmountOut,
      detail: reconciliation.detail,
    });
    return reconciliation;
  }

  private async wait(hash: Hex): Promise<ChainReceipt | "TIMEOUT"> {
    try {
      return await this.options.chain!.waitForReceipt(hash);
    } catch {
      return "TIMEOUT";
    }
  }

  private finish(
    intent: TradeIntent,
    tracker: TransactionTracker,
    hash: Hex,
    receipt: ChainReceipt | "TIMEOUT",
  ): LiveExecutionResult {
    if (receipt === "TIMEOUT") {
      tracker.transition("UNKNOWN");
      this.persistTransaction(intent.operationId, hash, tracker.state);
      const reconciliation = reconcile({
        local: this.localRecord(intent, tracker.state, hash),
        receipt: null,
        trade: null,
      });
      this.options.store.saveReconciliation({
        operationId: intent.operationId,
        status: reconciliation.status,
        canonicalAmountOut: null,
        detail: reconciliation.detail,
      });
      return {
        mode: "TESTNET",
        state: tracker.state,
        operationId: intent.operationId,
        transactionHash: hash,
        trade: null,
        reconciliation,
        resubmitted: false,
      };
    }

    const trade = findTradeExecuted(receipt.logs);
    if (trade) this.options.store.saveEvent(this.options.chainId, trade);
    this.settle(tracker, receipt, trade);
    this.persistTransaction(intent.operationId, hash, tracker.state);
    const reconciliation = reconcile({
      local: this.localRecord(intent, tracker.state, hash),
      receipt: {
        status: receipt.status,
        transactionHash: receipt.transactionHash,
        blockNumber: receipt.blockNumber.toString(),
      },
      trade,
    });
    this.options.store.saveReconciliation({
      operationId: intent.operationId,
      status: reconciliation.status,
      canonicalAmountOut: reconciliation.canonicalAmountOut,
      detail: reconciliation.detail,
    });
    return {
      mode: "TESTNET",
      state: tracker.state,
      operationId: intent.operationId,
      transactionHash: hash,
      trade,
      reconciliation,
      resubmitted: false,
    };
  }

  private settle(tracker: TransactionTracker, receipt: ChainReceipt | null, trade: DecodedTradeEvent | null): void {
    if (!receipt) return;
    if (receipt.status === "reverted") {
      this.move(tracker, "FAILED");
      return;
    }
    if (trade) {
      this.move(tracker, "CONFIRMED");
      return;
    }
    this.move(tracker, "UNKNOWN");
  }

  private move(tracker: TransactionTracker, to: TransactionState): void {
    if (tracker.state === to) return;
    if (tracker.state === "SUBMITTED" && (to === "CONFIRMED" || to === "UNKNOWN")) {
      tracker.transition("PENDING");
    }
    if (tracker.state !== to) tracker.transition(to);
  }

  private persistTransaction(operationId: Hex, transactionHash: Hex | null, state: TransactionState): void {
    this.options.store.saveTransaction({ operationId, transactionHash, state });
  }

  private localRecord(intent: TradeIntent, state: TransactionState, transactionHash: string | null) {
    return {
      operationId: intent.operationId,
      state,
      router: intent.router,
      tokenIn: intent.tokenIn,
      tokenOut: intent.tokenOut,
      amountIn: intent.amountIn.toString(),
      minAmountOut: intent.minAmountOut.toString(),
      recipient: intent.recipient,
      quotedAmountOut: intent.quotedAmountOut.toString(),
      transactionHash,
    };
  }
}
