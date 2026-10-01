import { encodePacked, keccak256 } from "viem";
import { describe, expect, it } from "vitest";
import { createOperationId } from "../../src/execution/operationId.js";
import { FIXTURE } from "../fixtures/trade.js";

describe("createOperationId", () => {
  it("packs the trade label, wallet, and sequence", () => {
    const sequence = 7n;
    const expected = keccak256(encodePacked(["string", "address", "uint256"], ["trade", FIXTURE.caller, sequence]));
    expect(createOperationId(FIXTURE.caller, sequence)).toBe(expected);
  });

  it("changes when the sequence changes", () => {
    expect(createOperationId(FIXTURE.caller, 1n)).not.toBe(createOperationId(FIXTURE.caller, 2n));
  });
});
