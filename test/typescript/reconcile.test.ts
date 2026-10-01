import { describe, expect, it } from "vitest";
import type { TradeResult } from "../../src/events/decoder.js";
import { reconcile, type LocalTransactionRecord } from "../../src/reconciliation/reconcile.js";
import { FIXTURE, FIXTURE_TX_HASH, fixtureIntent } from "../fixtures/trade.js";

function local(intent = fixtureIntent(), state: LocalTransactionRecord["state"] = "CONFIRMED"): LocalTransactionRecord {
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
    transactionHash: FIXTURE_TX_HASH,
  };
}

function trade(amountOut: string, intent = fixtureIntent()): TradeResult {
  return {
    operationId: intent.operationId,
    router: FIXTURE.router,
    tokenIn: FIXTURE.tokenIn,
    tokenOut: FIXTURE.tokenOut,
    amountIn: intent.amountIn.toString(),
    amountOut,
    recipient: FIXTURE.recipient,
    transactionHash: FIXTURE_TX_HASH,
    blockNumber: "9",
  };
}

describe("reconcile", () => {
  it("uses the event amount when the quote is different", () => {
    const intent = fixtureIntent({ amountIn: 100n, minAmountOut: 50n, quotedAmountOut: 100n });
    const result = reconcile({
      local: local(intent),
      receipt: { status: "success", transactionHash: FIXTURE_TX_HASH, blockNumber: "9" },
      trade: trade("63", intent),
      balances: { tokenOutBefore: "0", tokenOutAfter: "63" },
    });

    expect(result.status).toBe("SYNCED");
    expect(result.canonicalAmountOut).toBe("63");
    expect(result.requestedAmountIn).toBe("100");
    expect(result.detail).toContain("quotedAmountOut 100 is not the canonical fill");
  });

  it("reports a mismatch when the stored fill disagrees with the event", () => {
    const intent = fixtureIntent();
    const record = local(intent);
    record.amountIn = "1";
    const result = reconcile({
      local: record,
      receipt: { status: "success", transactionHash: FIXTURE_TX_HASH, blockNumber: "9" },
      trade: trade(intent.minAmountOut.toString(), intent),
    });
    expect(result.status).toBe("MISMATCH");
  });

  it("returns unknown when the receipt is missing", () => {
    const result = reconcile({ local: local(fixtureIntent(), "UNKNOWN"), receipt: null, trade: null });
    expect(result.status).toBe("UNKNOWN");
    expect(result.canonicalAmountOut).toBeNull();
  });

  it("treats a reverted receipt with no event as a consistent failure", () => {
    const result = reconcile({
      local: local(fixtureIntent(), "FAILED"),
      receipt: { status: "reverted", transactionHash: FIXTURE_TX_HASH, blockNumber: "9" },
      trade: null,
    });
    expect(result.status).toBe("SYNCED");
    expect(result.canonicalAmountOut).toBeNull();
  });
});
