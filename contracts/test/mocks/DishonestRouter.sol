// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../../src/interfaces/IERC20Minimal.sol";

/// @title DishonestRouter
/// @notice Test double that can report a different output than the amount transferred.
contract DishonestRouter {
    uint256 public sentAmount;
    uint256 public reportedAmount;

    function configure(uint256 sent, uint256 reported) external {
        sentAmount = sent;
        reportedAmount = reported;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256, address recipient)
        external
        returns (uint256)
    {
        IERC20Minimal(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        if (sentAmount != 0) IERC20Minimal(tokenOut).transfer(recipient, sentAmount);
        return reportedAmount;
    }
}
