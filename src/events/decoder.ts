import { decodeEventLog, getAddress, type Hex } from "viem";
import { tradingExecutorAbi } from "../abi/tradingExecutor.js";

/** JSON-safe trade record. Amounts stay decimal strings. */
export interface TradeResult {
  operationId: string;
  router: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  amountOut: string;
  recipient: string;
  transactionHash: string;
  blockNumber: string;
}

export interface DecodedTradeEvent extends TradeResult {
  logIndex: number;
}

export interface TradeLog {
  data: Hex;
  topics: [Hex, ...Hex[]];
  transactionHash: Hex;
  blockNumber: bigint;
  logIndex: number;
}

/** Decode one TradeExecuted log. Amounts are decimal strings, not JavaScript numbers. */
export function decodeTradeExecutedLog(log: TradeLog): DecodedTradeEvent {
  const decoded = decodeEventLog({
    abi: tradingExecutorAbi,
    eventName: "TradeExecuted",
    data: log.data,
    topics: log.topics,
  });

  return {
    operationId: decoded.args.operationId,
    router: getAddress(decoded.args.router),
    tokenIn: getAddress(decoded.args.tokenIn),
    tokenOut: getAddress(decoded.args.tokenOut),
    amountIn: decoded.args.amountIn.toString(),
    amountOut: decoded.args.amountOut.toString(),
    recipient: getAddress(decoded.args.recipient),
    transactionHash: log.transactionHash,
    blockNumber: log.blockNumber.toString(),
    logIndex: log.logIndex,
  };
}

export function findTradeExecuted(logs: readonly TradeLog[]): DecodedTradeEvent | null {
  for (const log of logs) {
    if (log.topics.length === 0) continue;
    try {
      return decodeTradeExecutedLog(log);
    } catch {
      continue;
    }
  }
  return null;
}
