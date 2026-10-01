import { encodePacked, getAddress, keccak256, type Address, type Hex } from "viem";

/** Deterministic id connecting a strategy request to a TradeExecuted event. */
export function createOperationId(wallet: Address, sequence: bigint): Hex {
  return keccak256(encodePacked(["string", "address", "uint256"], ["trade", getAddress(wallet), sequence]));
}
