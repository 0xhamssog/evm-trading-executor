import type { Address, Hex } from "viem";

/** A request the execution layer can encode. Strategy code does not live in this type. */
export interface TradeIntent {
  operationId: Hex;
  chainId: number;
  caller: Address;
  router: Address;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOut: bigint;
  deadline: bigint;
  recipient: Address;
  /** Offchain quote. The contract does not receive this value. */
  quotedAmountOut: bigint;
}

export interface RiskPolicy {
  authorizedCaller: Address;
  paused: boolean;
  allowedRouters: readonly Address[];
  allowedTokens: readonly Address[];
  nowSeconds: bigint;
}

export type CheckStatus = "PASS" | "FAIL";

export interface RiskDecision {
  accepted: boolean;
  authorization: CheckStatus;
  routerAllowlist: CheckStatus;
  tokenAllowlist: CheckStatus;
  deadline: CheckStatus;
  reasons: string[];
}
