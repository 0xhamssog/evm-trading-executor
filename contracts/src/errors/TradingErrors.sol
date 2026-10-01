// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Caller is not the admin or the authorized executor for this action.
error Unauthorized(address caller);

/// @notice Trading is paused.
error ContractPaused();

/// @notice Pause was requested while trading is already paused.
error AlreadyPaused();

/// @notice Unpause was requested while trading is already active.
error NotPaused();

/// @notice Router is not on the allowlist.
error RouterNotAllowed(address router);

/// @notice Token is not on the allowlist.
error TokenNotAllowed(address token);

/// @notice `amountIn` or `minAmountOut` is zero.
error InvalidAmount();

/// @notice Recipient is the zero address.
error InvalidRecipient();

/// @notice An admin or executor address is the zero address.
error InvalidAddress();

/// @notice Operation id is empty.
error InvalidOperationId();

/// @notice `block.timestamp` is after the trade deadline.
error DeadlineExpired(uint256 deadline, uint256 currentTime);

/// @notice Recipient received less `tokenOut` than `minAmountOut`.
error InsufficientOutput(uint256 amountOut, uint256 minAmountOut);

/// @notice Input and output tokens are the same address.
error IdenticalTokens();

/// @notice This operation id was already consumed by a successful trade.
error OperationAlreadyUsed(bytes32 operationId);

/// @notice Token balance or router report did not match the expected movement.
error UnexpectedBalance();

/// @notice ERC-20 call failed or returned `false`.
error TokenCallFailed();

/// @notice The executor was re-entered during a trade.
error Reentrancy();
