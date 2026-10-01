// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ExecutorFixture} from "../utils/ExecutorFixture.sol";

/// @notice Executor, mock router, and mock token moving together.
contract TradingExecutorIntegrationTest is ExecutorFixture {
    function test_fullTradeMovesBalancesAndClearsCustody() public {
        uint256 amountIn = 1_000_000;
        uint256 amountOut = 1_500_000;
        _prepare(amountIn, amountOut);

        uint256 got = _execute(keccak256("integration"), amountIn, 1_000_000, block.timestamp + 1 hours);

        assertEq(got, amountOut);
        assertEq(tokenIn.balanceOf(executorCaller), 0);
        assertEq(tokenIn.balanceOf(address(router)), amountIn);
        assertEq(tokenIn.balanceOf(address(tradingExecutor)), 0);
        assertEq(tokenOut.balanceOf(recipient), amountOut);
        assertEq(tokenOut.balanceOf(address(router)), 0);
        assertEq(tokenOut.balanceOf(address(tradingExecutor)), 0);
        assertEq(tokenIn.allowance(executorCaller, address(tradingExecutor)), 0);
        assertEq(tokenIn.allowance(address(tradingExecutor), address(router)), 0);
        assertTrue(tradingExecutor.usedOperationIds(keccak256("integration")));
    }

    function test_partialRouterPullIsRefunded() public {
        uint256 amountIn = 100;
        uint256 pullAmount = 40;
        uint256 amountOut = 50;
        _prepare(amountIn, amountOut);
        router.setPartialPull(pullAmount);

        uint256 got = _execute(keccak256("partial"), amountIn, amountOut, block.timestamp + 1 hours);

        assertEq(got, amountOut);
        assertEq(tokenIn.balanceOf(executorCaller), amountIn - pullAmount);
        assertEq(tokenIn.balanceOf(address(router)), pullAmount);
        assertEq(tokenIn.balanceOf(address(tradingExecutor)), 0);
        assertEq(tokenOut.balanceOf(recipient), amountOut);
        assertEq(tokenIn.allowance(address(tradingExecutor), address(router)), 0);
    }

    function test_failedSlippageLeavesBalancesUnchanged() public {
        _prepare(100, 90);
        uint256 callerBefore = tokenIn.balanceOf(executorCaller);
        uint256 routerInBefore = tokenIn.balanceOf(address(router));
        uint256 routerOutBefore = tokenOut.balanceOf(address(router));

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSignature("InsufficientOutput(uint256,uint256)", 90, 95));
        tradingExecutor.executeTrade(
            keccak256("integration-revert"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            100,
            95,
            block.timestamp + 1 hours,
            recipient
        );

        assertEq(tokenIn.balanceOf(executorCaller), callerBefore);
        assertEq(tokenIn.balanceOf(address(router)), routerInBefore);
        assertEq(tokenOut.balanceOf(address(router)), routerOutBefore);
        assertEq(tokenOut.balanceOf(recipient), 0);
        assertEq(tokenIn.allowance(address(tradingExecutor), address(router)), 0);
        assertFalse(tradingExecutor.usedOperationIds(keccak256("integration-revert")));
    }
}
