import type { TradeResult } from "../events/decoder.js";
import type { TransactionState } from "../execution/stateMachine.js";

export type ReconciliationStatus = "SYNCED" | "MISMATCH" | "UNKNOWN";

export interface LocalTransactionRecord {
  operationId: string;
  state: TransactionState;
  router: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  minAmountOut: string;
  recipient: string;
  quotedAmountOut: string | null;
  transactionHash: string | null;
}

export interface ReceiptSnapshot {
  status: "success" | "reverted";
  transactionHash: string;
  blockNumber: string;
}

export interface BalanceSnapshot {
  tokenOutBefore: string;
  tokenOutAfter: string;
}

export interface ReconciliationResult {
  status: ReconciliationStatus;
  canonicalAmountOut: string | null;
  requestedAmountIn: string;
  quotedAmountOut: string | null;
  detail: string;
}

export interface ReconciliationInput {
  local: LocalTransactionRecord;
  receipt: ReceiptSnapshot | null;
  trade: TradeResult | null;
  balances?: BalanceSnapshot;
}

function same(left: string, right: string): boolean {
  return left.toLowerCase() === right.toLowerCase();
}

function result(
  status: ReconciliationStatus,
  input: ReconciliationInput,
  canonicalAmountOut: string | null,
  detail: string,
): ReconciliationResult {
  return {
    status,
    canonicalAmountOut,
    requestedAmountIn: input.local.amountIn,
    quotedAmountOut: input.local.quotedAmountOut,
    detail,
  };
}

/**
 * Compare the local record, the receipt, and the TradeExecuted event.
 * The event's amountOut is canonical. A quote is never treated as the fill.
 */
export function reconcile(input: ReconciliationInput): ReconciliationResult {
  if (input.receipt === null) {
    return result("UNKNOWN", input, null, "receipt is not available");
  }

  if (input.local.transactionHash !== null && !same(input.local.transactionHash, input.receipt.transactionHash)) {
    return result("MISMATCH", input, null, "local transaction hash does not match the receipt");
  }

  if (input.receipt.status === "reverted") {
    if (input.trade) return result("MISMATCH", input, input.trade.amountOut, "reverted receipt included a trade event");
    if (input.local.state === "CONFIRMED") {
      return result("MISMATCH", input, null, "local state is CONFIRMED but the receipt reverted");
    }
    return result("SYNCED", input, null, "transaction reverted and no trade event was recorded");
  }

  if (!input.trade) {
    return result("UNKNOWN", input, null, "receipt succeeded but TradeExecuted was not decoded");
  }

  if (!same(input.trade.transactionHash, input.receipt.transactionHash)) {
    return result("MISMATCH", input, input.trade.amountOut, "trade event transaction hash does not match the receipt");
  }
  if (input.trade.blockNumber !== input.receipt.blockNumber) {
    return result("MISMATCH", input, input.trade.amountOut, "trade event block does not match the receipt");
  }
  if (input.local.state === "FAILED") {
    return result("MISMATCH", input, input.trade.amountOut, "local state is FAILED but the receipt succeeded");
  }

  const fields: Array<[string, string, string]> = [
    [input.local.operationId, input.trade.operationId, "operationId"],
    [input.local.router, input.trade.router, "router"],
    [input.local.tokenIn, input.trade.tokenIn, "tokenIn"],
    [input.local.tokenOut, input.trade.tokenOut, "tokenOut"],
    [input.local.recipient, input.trade.recipient, "recipient"],
    [input.local.amountIn, input.trade.amountIn, "amountIn"],
  ];
  for (const [localValue, chainValue, label] of fields) {
    if (!same(localValue, chainValue)) {
      return result("MISMATCH", input, input.trade.amountOut, `${label} does not match the trade event`);
    }
  }

  let canonical: bigint;
  try {
    canonical = BigInt(input.trade.amountOut);
  } catch {
    return result("MISMATCH", input, null, "amountOut is not an integer string");
  }
  if (canonical < BigInt(input.local.minAmountOut)) {
    return result("MISMATCH", input, canonical.toString(), "event amountOut is below the signed minimum");
  }

  if (input.balances) {
    const delta = BigInt(input.balances.tokenOutAfter) - BigInt(input.balances.tokenOutBefore);
    if (delta !== canonical) {
      return result("MISMATCH", input, canonical.toString(), "tokenOut balance change does not match amountOut");
    }
  }

  const quoted = input.local.quotedAmountOut;
  const quoteNote =
    quoted !== null && quoted !== canonical.toString()
      ? ` quotedAmountOut ${quoted} is not the canonical fill.`
      : "";
  return result("SYNCED", input, canonical.toString(), `canonical amountOut is ${canonical.toString()}.${quoteNote}`);
}
