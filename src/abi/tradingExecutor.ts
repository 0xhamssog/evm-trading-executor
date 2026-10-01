export const tradingExecutorAbi = [
  {
    type: "function",
    name: "executeTrade",
    stateMutability: "nonpayable",
    inputs: [
      { name: "operationId", type: "bytes32" },
      { name: "router", type: "address" },
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "deadline", type: "uint256" },
      { name: "recipient", type: "address" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    type: "event",
    name: "TradeExecuted",
    inputs: [
      { name: "operationId", type: "bytes32", indexed: true },
      { name: "router", type: "address", indexed: true },
      { name: "tokenIn", type: "address", indexed: true },
      { name: "tokenOut", type: "address", indexed: false },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "recipient", type: "address", indexed: false },
    ],
    anonymous: false,
  },
] as const;
