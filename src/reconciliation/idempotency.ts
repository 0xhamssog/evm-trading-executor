/** chainId + transactionHash + logIndex. One onchain log, one identity. */
export function eventIdentity(chainId: number, transactionHash: string, logIndex: number): string {
  return `${chainId}:${transactionHash.toLowerCase()}:${logIndex}`;
}
