import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const roots = ["src", "contracts/src", "contracts/script", "contracts/test", "test"];
const secretAssignments = ["PRIV" + "ATE_KEY", "SEED" + "_PHRASE", "MNE" + "MONIC", "WALL" + "ET_SECRET"].map(
  (name) => new RegExp(`${name}\\s*=`),
);

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) return files(path);
    return [path];
  });
}

describe("repository secrets", () => {
  it("does not assign a signing secret in source", () => {
    const paths = roots.flatMap((root) => files(root));
    paths.push(".env.example");
    for (const path of paths) {
      const text = readFileSync(path, "utf8");
      for (const pattern of secretAssignments) {
        expect(text, path).not.toMatch(pattern);
      }
    }
  });

  it("does not expose an arbitrary call on the executor", () => {
    const source = readFileSync("contracts/src/TradingExecutor.sol", "utf8");
    expect(source).not.toContain("delegatecall");
    expect(source).not.toMatch(/function\s+call\s*\(/);
    expect(source).not.toContain(".call(");
  });
});
