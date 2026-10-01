import { Writable } from "node:stream";
import { pathToFileURL } from "node:url";
import { decodeFunctionData, getAddress } from "viem";
import { tradingExecutorAbi } from "./abi/tradingExecutor.js";
import { loadConfig } from "./config/env.js";
import { decodeTradeExecutedLog } from "./events/decoder.js";
import { TradingExecutorClient } from "./execution/executor.js";
import { createOperationId } from "./execution/operationId.js";
import { createLogger, logExecution } from "./logging/logger.js";
import { MemoryStore } from "./persistence/memoryStore.js";
import { reconcile } from "./reconciliation/reconcile.js";
import { assessIntent, assessSimulatedSlippage } from "./risk/engine.js";
import { buildFixtureLog, FIXTURE, FIXTURE_TX_HASH, fixtureIntent, fixturePolicy } from "./demoFixtures.js";

/** Run the local simulated flow. This function does not broadcast a transaction. */
export async function runDemo(): Promise<string> {
  const config = loadConfig({
    EXECUTION_MODE: "SIMULATED",
    CHAIN_ID: "31337",
    LOG_LEVEL: "info",
    API_PORT: "3000",
  });

  const intent = fixtureIntent({
    operationId: createOperationId(FIXTURE.caller, 1n),
    amountIn: 1000n,
    minAmountOut: 950n,
    quotedAmountOut: 1000n,
    deadline: 2_000_000_000n,
  });
  const simulatedAmountOut = 970n;
  const policy = fixturePolicy(1_700_000_000n);
  const decision = assessIntent(intent, policy);
  const slippage = assessSimulatedSlippage(simulatedAmountOut, intent.minAmountOut);

  const store = new MemoryStore();
  const chunks: string[] = [];
  const logger = createLogger(
    config.LOG_LEVEL,
    new Writable({
      write(chunk, _encoding, callback) {
        chunks.push(chunk.toString());
        callback();
      },
    }),
  );
  const client = new TradingExecutorClient({
    mode: config.EXECUTION_MODE,
    chainId: config.CHAIN_ID,
    executorAddress: getAddress(FIXTURE.executor),
    policy,
    store,
    logger,
  });

  const simulated = await client.execute(intent, simulatedAmountOut);
  if (simulated.mode !== "SIMULATED") {
    throw new Error("demo must stay in simulated mode");
  }

  const decodedCall = decodeFunctionData({ abi: tradingExecutorAbi, data: simulated.calldata });
  if (decodedCall.functionName !== "executeTrade") {
    throw new Error("demo encoded an unexpected function");
  }

  const trade = decodeTradeExecutedLog(
    buildFixtureLog({
      intent,
      amountOut: simulatedAmountOut,
      transactionHash: FIXTURE_TX_HASH,
      blockNumber: 1n,
      logIndex: 0,
    }),
  );
  const reconciliation = reconcile({
    local: {
      operationId: intent.operationId,
      state: "CONFIRMED",
      router: intent.router,
      tokenIn: intent.tokenIn,
      tokenOut: intent.tokenOut,
      amountIn: intent.amountIn.toString(),
      minAmountOut: intent.minAmountOut.toString(),
      recipient: intent.recipient,
      quotedAmountOut: intent.quotedAmountOut.toString(),
      transactionHash: FIXTURE_TX_HASH,
    },
    receipt: {
      status: "success",
      transactionHash: FIXTURE_TX_HASH,
      blockNumber: "1",
    },
    trade,
    balances: { tokenOutBefore: "0", tokenOutAfter: simulatedAmountOut.toString() },
  });

  logExecution(logger, {
    msg: "execution simulated",
    operationId: intent.operationId,
    transactionHash: "fixture-not-broadcast",
    router: intent.router,
    tokenIn: intent.tokenIn,
    tokenOut: intent.tokenOut,
    state: "SIMULATED",
    durationMs: 0,
  });

  const eventDecode = trade.amountOut === simulatedAmountOut.toString() ? "PASS" : "FAIL";
  const reconciliationStatus = reconciliation.status === "SYNCED" ? "PASS" : "FAIL";
  const lines = [
    "EVM Trading Executor",
    "--------------------",
    "",
    `Authorization: ${decision.authorization}`,
    `Router Allowlist: ${decision.routerAllowlist}`,
    `Token Allowlist: ${decision.tokenAllowlist}`,
    `Slippage Check: ${slippage}`,
    `Deadline Check: ${decision.deadline}`,
    "Transaction State: SIMULATED",
    `Event Decode: ${eventDecode}`,
    `Reconciliation: ${reconciliationStatus}`,
    "",
    "Simulated flow (fixture, not broadcast)",
    `operationId=${intent.operationId}`,
    "transactionHash=fixture-not-broadcast",
    `router=${intent.router}`,
    `tokenIn=${intent.tokenIn}`,
    `tokenOut=${intent.tokenOut}`,
    `amountIn=${intent.amountIn.toString()}`,
    `quotedAmountOut=${intent.quotedAmountOut.toString()}`,
    `amountOut=${trade.amountOut}`,
    "state=SIMULATED",
    `reconciliation=${reconciliation.status}`,
    `canonicalAmountOut=${reconciliation.canonicalAmountOut ?? ""}`,
    "",
    chunks.join("").trim(),
  ];
  return lines.join("\n");
}

const invoked = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (import.meta.url === invoked) {
  const output = await runDemo();
  console.log(output);
}
