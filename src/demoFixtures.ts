import { encodeAbiParameters, encodeEventTopics, getAddress, type Hex } from "viem";
import { tradingExecutorAbi } from "./abi/tradingExecutor.js";
import type { TradeLog } from "./events/decoder.js";
import { createOperationId } from "./execution/operationId.js";
import type { RiskPolicy, TradeIntent } from "./execution/types.js";

/** Obvious fixture addresses. They are not deployed contracts. */
export const FIXTURE = {
  caller: getAddress("0x0000000000000000000000000000000000000001"),
  router: getAddress("0x0000000000000000000000000000000000000002"),
  tokenIn: getAddress("0x0000000000000000000000000000000000000003"),
  tokenOut: getAddress("0x0000000000000000000000000000000000000004"),
  recipient: getAddress("0x0000000000000000000000000000000000000005"),
  executor: getAddress("0x0000000000000000000000000000000000000006"),
} as const;

/** Placeholder hash used only by the simulated demo and unit fixtures. */
export const FIXTURE_TX_HASH = `0x${"11".repeat(32)}` as Hex;

export function fixtureIntent(overrides: Partial<TradeIntent> = {}): TradeIntent {
  const caller = overrides.caller ?? FIXTURE.caller;
  return {
    operationId: createOperationId(caller, 1n),
    chainId: 31337,
    caller,
    router: FIXTURE.router,
    tokenIn: FIXTURE.tokenIn,
    tokenOut: FIXTURE.tokenOut,
    amountIn: 1000n,
    minAmountOut: 950n,
    deadline: 2_000_000_000n,
    recipient: FIXTURE.recipient,
    quotedAmountOut: 1000n,
    ...overrides,
  };
}

export function fixturePolicy(nowSeconds = 1_700_000_000n): RiskPolicy {
  return {
    authorizedCaller: FIXTURE.caller,
    paused: false,
    allowedRouters: [FIXTURE.router],
    allowedTokens: [FIXTURE.tokenIn, FIXTURE.tokenOut],
    nowSeconds,
  };
}

export function buildFixtureLog(input: {
  intent: TradeIntent;
  amountOut: bigint;
  transactionHash: Hex;
  blockNumber: bigint;
  logIndex: number;
}): TradeLog {
  const topics = encodeEventTopics({
    abi: tradingExecutorAbi,
    eventName: "TradeExecuted",
    args: {
      operationId: input.intent.operationId,
      router: input.intent.router,
      tokenIn: input.intent.tokenIn,
    },
  });
  const topic0 = topics[0];
  if (!topic0) throw new Error("fixture log is missing an event topic");
  const data = encodeAbiParameters(
    [
      { type: "address", name: "tokenOut" },
      { type: "uint256", name: "amountIn" },
      { type: "uint256", name: "amountOut" },
      { type: "address", name: "recipient" },
    ],
    [input.intent.tokenOut, input.intent.amountIn, input.amountOut, input.intent.recipient],
  );
  return {
    data,
    topics: [topic0, ...topics.slice(1)] as [Hex, ...Hex[]],
    transactionHash: input.transactionHash,
    blockNumber: input.blockNumber,
    logIndex: input.logIndex,
  };
}
