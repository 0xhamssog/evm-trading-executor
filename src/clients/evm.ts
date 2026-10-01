import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  type Account,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";
import type { ChainReceipt, ExecutionChain } from "../execution/executor.js";

/** Build a viem chain description from configuration. No request is sent. */
export function chainFromId(chainId: number, rpcUrl: string) {
  return defineChain({
    id: chainId,
    name: `evm-${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  });
}

export function createReadClient(rpcUrl: string, chainId: number): PublicClient {
  return createPublicClient({
    chain: chainFromId(chainId, rpcUrl),
    transport: http(rpcUrl),
  });
}

/**
 * Opt-in broadcast adapter.
 * The account is supplied by the host process. This module does not read a key from disk.
 */
export function createViemExecutionChain(input: {
  rpcUrl: string;
  chainId: number;
  account: Account;
}): ExecutionChain {
  const chain = chainFromId(input.chainId, input.rpcUrl);
  const publicClient = createPublicClient({ chain, transport: http(input.rpcUrl) });
  const walletClient = createWalletClient({ account: input.account, chain, transport: http(input.rpcUrl) });

  return {
    async send({ to, data }: { to: Address; data: Hex }) {
      return walletClient.sendTransaction({ account: input.account, chain, to, data });
    },
    async waitForReceipt(hash: Hex): Promise<ChainReceipt | "TIMEOUT"> {
      try {
        const receipt = await publicClient.waitForTransactionReceipt({ hash, timeout: 60_000 });
        return {
          status: receipt.status === "success" ? "success" : "reverted",
          transactionHash: receipt.transactionHash,
          blockNumber: receipt.blockNumber,
          logs: receipt.logs.map((log) => ({
            data: log.data,
            topics: log.topics as [Hex, ...Hex[]],
            transactionHash: log.transactionHash ?? hash,
            blockNumber: log.blockNumber ?? receipt.blockNumber,
            logIndex: log.logIndex ?? 0,
          })),
        };
      } catch (error) {
        if (error instanceof Error && error.name === "WaitForTransactionReceiptTimeoutError") return "TIMEOUT";
        throw error;
      }
    },
  };
}
