import { describe, expect, it } from "vitest";
import { runDemo } from "../../src/demo.js";

describe("demo", () => {
  it("prints a simulated pass and does not claim a broadcast", async () => {
    const output = await runDemo();
    expect(output).toContain("Authorization: PASS");
    expect(output).toContain("Router Allowlist: PASS");
    expect(output).toContain("Token Allowlist: PASS");
    expect(output).toContain("Slippage Check: PASS");
    expect(output).toContain("Deadline Check: PASS");
    expect(output).toContain("Transaction State: SIMULATED");
    expect(output).toContain("Event Decode: PASS");
    expect(output).toContain("Reconciliation: PASS");
    expect(output).toContain("fixture, not broadcast");
    expect(output).toContain("canonicalAmountOut=970");
    expect(output).toContain("quotedAmountOut=1000");
  });
});
