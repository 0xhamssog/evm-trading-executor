import { Writable } from "node:stream";
import { decodeFunctionData } from "viem";
import { describe, expect, it } from "vitest";
import { tradingExecutorAbi } from "../../src/abi/tradingExecutor.js";
import type { ChainReceipt, ExecutionChain } from "../../src/execution/executor.js";
import {
  IntentRejectedError,
  LiveExecutionDisabledError,
  OperationAlreadySubmittedError,
  TradingExecutorClient,
} from "../../src/execution/executor.js";
import { createLogger } from "../../src/logging/logger.js";
import { MemoryStore } from "../../src/persistence/memoryStore.js";
import { buildFixtureLog, FIXTURE, FIXTURE_TX_HASH, fixtureIntent, fixturePolicy } from "../fixtures/trade.js";

function logger() {
  return createLogger("silent");
}

function client(mode: "SIMULATED" | "TESTNET", chain?: ExecutionChain, store = new MemoryStore()) {
  return new TradingExecutorClient({
    mode,
    chainId: 31337,
    executorAddress: FIXTURE.executor,
    policy: fixturePolicy(),
    store,
    logger: logger(),
    ...(chain ? { chain } : {}),
  });
}

describe("TradingExecutorClient", () => {
  it("simulates without sending", async () => {
    let sends = 0;
    const chain: ExecutionChain = {
      async send() {
        sends += 1;
        return FIXTURE_TX_HASH;
      },
      async waitForReceipt() {
        return "TIMEOUT";
      },
    };
    const result = await client("SIMULATED", chain).execute(fixtureIntent(), 970n);
    expect(result.mode).toBe("SIMULATED");
    if (result.mode !== "SIMULATED") return;
    expect(result.broadcast).toBe(false);
    expect(result.checks.slippage).toBe("PASS");
    expect(sends).toBe(0);

    const decoded = decodeFunctionData({ abi: tradingExecutorAbi, data: result.calldata });
    expect(decoded.functionName).toBe("executeTrade");
    expect(decoded.args).toHaveLength(8);
  });

  it("refuses to submit unless testnet mode is explicit", async () => {
    await expect(client("SIMULATED").submit(fixtureIntent())).rejects.toBeInstanceOf(LiveExecutionDisabledError);
  });

  it("does not send a rejected intent", async () => {
    let sends = 0;
    const chain: ExecutionChain = {
      async send() {
        sends += 1;
        return FIXTURE_TX_HASH;
      },
      async waitForReceipt() {
        return "TIMEOUT";
      },
    };
    const intent = fixtureIntent({ amountIn: 0n });
    await expect(client("TESTNET", chain).submit(intent)).rejects.toBeInstanceOf(IntentRejectedError);
    expect(sends).toBe(0);
  });

  it("marks a timeout as unknown and does not resubmit", async () => {
    let sends = 0;
    const chain: ExecutionChain = {
      async send() {
        sends += 1;
        return FIXTURE_TX_HASH;
      },
      async waitForReceipt() {
        return "TIMEOUT";
      },
    };
    const store = new MemoryStore();
    const executor = client("TESTNET", chain, store);
    const intent = fixtureIntent();
    const first = await executor.submit(intent);
    expect(first.state).toBe("UNKNOWN");
    expect(first.resubmitted).toBe(false);
    expect(first.reconciliation.status).toBe("UNKNOWN");
    expect(sends).toBe(1);

    await expect(executor.submit(intent)).rejects.toBeInstanceOf(OperationAlreadySubmittedError);
    expect(sends).toBe(1);

    const receipt: ChainReceipt = {
      status: "success",
      transactionHash: FIXTURE_TX_HASH,
      blockNumber: 8n,
      logs: [
        buildFixtureLog({
          intent,
          amountOut: 970n,
          transactionHash: FIXTURE_TX_HASH,
          blockNumber: 8n,
          logIndex: 0,
        }),
      ],
    };
    const reconciled = executor.reconcileSubmitted(intent.operationId, receipt);
    expect(reconciled.status).toBe("SYNCED");
    expect(reconciled.canonicalAmountOut).toBe("970");
    expect(store.getTransaction(intent.operationId)?.state).toBe("CONFIRMED");
    expect(store.countEvents()).toBe(1);
    expect(sends).toBe(1);
  });

  it("logs the execution fields and nothing else", () => {
    const lines: string[] = [];
    const log = createLogger(
      "info",
      new Writable({
        write(chunk, _encoding, callback) {
          lines.push(chunk.toString());
          callback();
        },
      }),
    );
    log.info(
      {
        operationId: "0xabc",
        transactionHash: "fixture-not-broadcast",
        router: FIXTURE.router,
        tokenIn: FIXTURE.tokenIn,
        tokenOut: FIXTURE.tokenOut,
        state: "SUBMITTED",
        durationMs: 1,
      },
      "execution submitted",
    );
    const text = lines.join("");
    expect(text).toContain("operationId");
    expect(text).toContain("SUBMITTED");
    expect(text.toLowerCase()).not.toContain("private");
    expect(text).not.toContain("seed");
  });
});
