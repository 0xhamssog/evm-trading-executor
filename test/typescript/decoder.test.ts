import { describe, expect, it } from "vitest";
import { decodeTradeExecutedLog } from "../../src/events/decoder.js";
import { buildFixtureLog, FIXTURE, FIXTURE_TX_HASH, fixtureIntent } from "../fixtures/trade.js";

describe("TradeExecuted decoder", () => {
  it("returns decimal strings for amounts", () => {
    const intent = fixtureIntent({ amountIn: 100n, quotedAmountOut: 100n });
    const decoded = decodeTradeExecutedLog(
      buildFixtureLog({
        intent,
        amountOut: 63n,
        transactionHash: FIXTURE_TX_HASH,
        blockNumber: 42n,
        logIndex: 4,
      }),
    );

    expect(decoded).toMatchObject({
      operationId: intent.operationId,
      router: FIXTURE.router,
      tokenIn: FIXTURE.tokenIn,
      tokenOut: FIXTURE.tokenOut,
      amountIn: "100",
      amountOut: "63",
      recipient: FIXTURE.recipient,
      transactionHash: FIXTURE_TX_HASH,
      blockNumber: "42",
      logIndex: 4,
    });
    expect(typeof decoded.amountOut).toBe("string");
  });
});
