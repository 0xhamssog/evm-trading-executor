import { describe, expect, it } from "vitest";
import { decodeTradeExecutedLog } from "../../src/events/decoder.js";
import { MemoryStore } from "../../src/persistence/memoryStore.js";
import { eventIdentity } from "../../src/reconciliation/idempotency.js";
import { buildFixtureLog, FIXTURE_TX_HASH, fixtureIntent } from "../fixtures/trade.js";

describe("event idempotency", () => {
  it("stores one trade when the same log is processed twice", () => {
    const intent = fixtureIntent();
    const event = decodeTradeExecutedLog(
      buildFixtureLog({
        intent,
        amountOut: 970n,
        transactionHash: FIXTURE_TX_HASH,
        blockNumber: 3n,
        logIndex: 2,
      }),
    );
    const store = new MemoryStore();
    const chainId = 31337;
    const first = store.saveEvent(chainId, event);
    const second = store.saveEvent(chainId, event);

    expect(first.inserted).toBe(true);
    expect(second.inserted).toBe(false);
    expect(first.identity).toBe(eventIdentity(chainId, FIXTURE_TX_HASH, 2));
    expect(store.countEvents()).toBe(1);
  });
});
