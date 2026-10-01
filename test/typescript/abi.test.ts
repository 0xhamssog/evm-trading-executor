import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { tradingExecutorAbi } from "../../src/abi/tradingExecutor.js";

interface AbiItem {
  type: string;
  name?: string;
  inputs?: Array<{ name: string; type: string; indexed?: boolean }>;
}

describe("TradingExecutor ABI", () => {
  it("matches the Foundry artifact for executeTrade and TradeExecuted", () => {
    const artifact = JSON.parse(readFileSync("out/TradingExecutor.sol/TradingExecutor.json", "utf8")) as {
      abi: AbiItem[];
    };
    const execute = artifact.abi.find((item) => item.type === "function" && item.name === "executeTrade");
    const event = artifact.abi.find((item) => item.type === "event" && item.name === "TradeExecuted");
    const tsExecute = tradingExecutorAbi.find((item) => item.type === "function" && item.name === "executeTrade");
    const tsEvent = tradingExecutorAbi.find((item) => item.type === "event" && item.name === "TradeExecuted");

    expect(execute?.inputs?.map((input) => `${input.type} ${input.name}`)).toEqual(
      tsExecute?.inputs.map((input) => `${input.type} ${input.name}`),
    );
    expect(event?.inputs?.map((input) => `${input.type} ${input.name} ${Boolean(input.indexed)}`)).toEqual(
      tsEvent?.inputs.map((input) => `${input.type} ${input.name} ${Boolean(input.indexed)}`),
    );
  });
});
