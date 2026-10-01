import { describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config/env.js";
import { FIXTURE } from "../fixtures/trade.js";

describe("loadConfig", () => {
  it("defaults to simulated mode", () => {
    const config = loadConfig({});
    expect(config.EXECUTION_MODE).toBe("SIMULATED");
    expect(config.CHAIN_ID).toBe(31337);
    expect(config.LOG_LEVEL).toBe("info");
  });

  it("fails when the log level is not recognized", () => {
    expect(() => loadConfig({ LOG_LEVEL: "loud" })).toThrow(/Invalid configuration/);
  });

  it("requires an RPC and executor address before testnet mode", () => {
    expect(() => loadConfig({ EXECUTION_MODE: "TESTNET" })).toThrow(/RPC_URL/);
    expect(() =>
      loadConfig({
        EXECUTION_MODE: "TESTNET",
        RPC_URL: "http://127.0.0.1:8545",
        EXECUTOR_ADDRESS: FIXTURE.executor,
      }),
    ).not.toThrow();
  });
});
