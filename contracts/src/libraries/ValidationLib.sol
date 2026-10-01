// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeadlineExpired, IdenticalTokens, InvalidAmount, InvalidRecipient} from "../errors/TradingErrors.sol";

/// @notice Pure trade-input checks shared by the executor.
library ValidationLib {
    /// @notice Reject empty amounts, identical tokens, a zero recipient, and an expired deadline.
    /// @dev `minAmountOut == 0` is rejected so slippage protection cannot be disabled by accident.
    function validateTradeInputs(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address recipient
    ) internal view {
        if (amountIn == 0 || minAmountOut == 0) revert InvalidAmount();
        if (tokenIn == tokenOut) revert IdenticalTokens();
        if (recipient == address(0)) revert InvalidRecipient();
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
    }
}
