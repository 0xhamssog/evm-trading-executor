// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Test and adapter surface for a single swap.
/// @dev This is not a universal DEX interface. Production adapters translate a real protocol
///      into this shape, or the executor is pointed at a reviewed adapter that implements it.
interface ITradingRouter {
    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut`.
    /// @dev The router pulls `tokenIn` from the caller and sends `tokenOut` to `recipient`.
    /// @param tokenIn Input token.
    /// @param tokenOut Output token.
    /// @param amountIn Exact input amount the router should pull.
    /// @param minAmountOut Minimum output required by the caller. Adapters may ignore it
    ///        because the executor enforces the recipient's received balance.
    /// @param recipient Account that receives `tokenOut`.
    /// @return amountOut Amount of `tokenOut` the router reports it delivered.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut);
}
