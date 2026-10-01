import { getAddress, isAddress, type Address } from "viem";
import type { CheckStatus, RiskDecision, RiskPolicy, TradeIntent } from "../execution/types.js";

function includesAddress(list: readonly Address[], value: Address): boolean {
  const needle = getAddress(value);
  return list.some((item) => getAddress(item) === needle);
}

function status(ok: boolean): CheckStatus {
  return ok ? "PASS" : "FAIL";
}

/**
 * Risk checks that run before any transaction is signed.
 * This module does not price a trade and does not choose a route.
 */
export function assessIntent(intent: TradeIntent, policy: RiskPolicy): RiskDecision {
  const reasons: string[] = [];

  const callerOk = isAddress(intent.caller) && getAddress(intent.caller) === getAddress(policy.authorizedCaller);
  if (!callerOk) reasons.push("caller is not the authorized executor");
  if (policy.paused) reasons.push("trading is paused");

  const routerOk = isAddress(intent.router) && includesAddress(policy.allowedRouters, intent.router);
  if (!routerOk) reasons.push("router is not allowlisted");

  const tokensOk =
    isAddress(intent.tokenIn) &&
    isAddress(intent.tokenOut) &&
    intent.tokenIn.toLowerCase() !== intent.tokenOut.toLowerCase() &&
    includesAddress(policy.allowedTokens, intent.tokenIn) &&
    includesAddress(policy.allowedTokens, intent.tokenOut);
  if (!tokensOk) reasons.push("token is not allowlisted");

  if (intent.amountIn <= 0n || intent.minAmountOut <= 0n) reasons.push("amount must be non-zero");
  if (!isAddress(intent.recipient)) reasons.push("recipient is invalid");
  if (!/^0x[0-9a-fA-F]{64}$/u.test(intent.operationId)) reasons.push("operation id is invalid");

  const deadlineOk = intent.deadline >= policy.nowSeconds;
  if (!deadlineOk) reasons.push("deadline has expired");

  const authorization = status(callerOk && !policy.paused);
  const routerAllowlist = status(routerOk);
  const tokenAllowlist = status(tokensOk);
  const deadline = status(deadlineOk);

  return {
    accepted: reasons.length === 0,
    authorization,
    routerAllowlist,
    tokenAllowlist,
    deadline,
    reasons,
  };
}

/** Compares a simulated or quoted fill with the minimum the caller is willing to accept. */
export function assessSimulatedSlippage(simulatedAmountOut: bigint, minAmountOut: bigint): CheckStatus {
  if (minAmountOut <= 0n) return "FAIL";
  return simulatedAmountOut >= minAmountOut ? "PASS" : "FAIL";
}
