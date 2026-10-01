// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../../src/interfaces/IERC20Minimal.sol";

/// @title MockTradingRouter
/// @notice Test double that pulls `tokenIn` and pays a configured `tokenOut` amount.
/// @dev Not a DEX. `setAmountOut` chooses the fill used by the next swap.
contract MockTradingRouter {
    uint256 public amountToSend;
    bool public amountConfigured;
    bool public shouldRevert;
    bool public partialPull;
    uint256 public partialPullAmount;

    uint256 public allowanceAtSwap;
    address public payerAtSwap;

    error RouterSwapFailed();
    error AmountNotConfigured();
    error PullExceedsInput();

    function setAmountOut(uint256 amount) external {
        amountConfigured = true;
        amountToSend = amount;
    }

    function setShouldRevert(bool enabled) external {
        shouldRevert = enabled;
    }

    /// @notice Pull `amount` of the input instead of `amountIn`. The executor must refund the rest.
    function setPartialPull(uint256 amount) external {
        partialPull = true;
        partialPullAmount = amount;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256, address recipient)
        external
        returns (uint256 amountOut)
    {
        if (shouldRevert) revert RouterSwapFailed();
        if (!amountConfigured) revert AmountNotConfigured();

        allowanceAtSwap = IERC20Minimal(tokenIn).allowance(msg.sender, address(this));
        payerAtSwap = msg.sender;

        uint256 pullAmount = partialPull ? partialPullAmount : amountIn;
        if (pullAmount > amountIn) revert PullExceedsInput();
        if (pullAmount != 0) _moveFrom(tokenIn, msg.sender, address(this), pullAmount);

        amountOut = amountToSend;
        if (amountOut != 0) _move(tokenOut, recipient, amountOut);
    }

    /// @dev Accepts tokens that omit a boolean return so executor tests can use non-standard ERC-20s.
    function _moveFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        require(success && _ok(data), "transferFrom");
    }

    function _move(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
        require(success && _ok(data), "transfer");
    }

    function _ok(bytes memory data) private pure returns (bool) {
        if (data.length == 0) return true;
        if (data.length < 32) return false;
        return abi.decode(data, (bool));
    }
}
