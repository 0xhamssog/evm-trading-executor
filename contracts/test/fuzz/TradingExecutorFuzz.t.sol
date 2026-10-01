// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ExecutorFixture} from "../utils/ExecutorFixture.sol";
import {
    DeadlineExpired,
    InsufficientOutput,
    InvalidAmount,
    RouterNotAllowed,
    TokenNotAllowed,
    Unauthorized
} from "../../src/errors/TradingErrors.sol";

/// @notice Property tests for amount, deadline, authorization, and allowlists.
contract TradingExecutorFuzzTest is ExecutorFixture {
    function testFuzz_amountInZeroAlwaysReverts(uint256 minAmountOut, uint256 deadline, bytes32 operationId) public {
        minAmountOut = bound(minAmountOut, 1, type(uint128).max);
        deadline = bound(deadline, block.timestamp, type(uint64).max);
        vm.assume(operationId != bytes32(0));

        vm.prank(executorCaller);
        vm.expectRevert(InvalidAmount.selector);
        tradingExecutor.executeTrade(
            operationId, address(router), address(tokenIn), address(tokenOut), 0, minAmountOut, deadline, recipient
        );
    }

    function testFuzz_minAmountOutZeroAlwaysReverts(uint256 amountIn, uint256 deadline, bytes32 operationId) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        deadline = bound(deadline, block.timestamp, type(uint64).max);
        vm.assume(operationId != bytes32(0));

        vm.prank(executorCaller);
        vm.expectRevert(InvalidAmount.selector);
        tradingExecutor.executeTrade(
            operationId, address(router), address(tokenIn), address(tokenOut), amountIn, 0, deadline, recipient
        );
    }

    function testFuzz_expiredDeadlineAlwaysReverts(uint256 currentTime, uint256 deadline, uint256 amountIn) public {
        currentTime = bound(currentTime, 2, type(uint64).max);
        deadline = bound(deadline, 1, currentTime - 1);
        amountIn = bound(amountIn, 1, type(uint128).max);
        vm.warp(currentTime);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(DeadlineExpired.selector, deadline, currentTime));
        tradingExecutor.executeTrade(
            keccak256("fuzz-deadline"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            amountIn,
            1,
            deadline,
            recipient
        );
    }

    function testFuzz_deadlineEqualToTimestampSucceeds(uint64 currentTime, uint96 amountIn) public {
        currentTime = uint64(bound(currentTime, 1, type(uint64).max));
        amountIn = uint96(bound(amountIn, 1, 1_000_000 ether));
        vm.warp(currentTime);
        _prepare(amountIn, amountIn);

        uint256 amountOut = _execute(keccak256("fuzz-deadline-ok"), amountIn, amountIn, currentTime);
        assertGe(amountOut, amountIn);
        assertEq(amountOut, amountIn);
    }

    function testFuzz_outputBelowMinimumAlwaysReverts(uint96 amountIn, uint96 minAmountOut, uint96 actualOut) public {
        amountIn = uint96(bound(amountIn, 1, 1_000_000 ether));
        minAmountOut = uint96(bound(minAmountOut, 1, 1_000_000 ether));
        actualOut = uint96(bound(actualOut, 0, minAmountOut - 1));
        _prepare(amountIn, actualOut);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(InsufficientOutput.selector, actualOut, minAmountOut));
        tradingExecutor.executeTrade(
            keccak256("fuzz-slip"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            amountIn,
            minAmountOut,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function testFuzz_outputAtOrAboveMinimumSucceeds(uint96 amountIn, uint96 minAmountOut, uint96 extra) public {
        amountIn = uint96(bound(amountIn, 1, 1_000_000 ether));
        minAmountOut = uint96(bound(minAmountOut, 1, 1_000_000 ether));
        extra = uint96(bound(extra, 0, 1_000_000 ether));
        uint256 actualOut = uint256(minAmountOut) + uint256(extra);
        _prepare(amountIn, actualOut);

        uint256 amountOut = _execute(keccak256("fuzz-fill"), amountIn, minAmountOut, block.timestamp + 1 days);
        assertEq(amountOut, actualOut);
        assertGe(amountOut, minAmountOut);
    }

    function testFuzz_unauthorizedCallerAlwaysReverts(address caller) public {
        vm.assume(caller != executorCaller);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        tradingExecutor.executeTrade(
            keccak256("fuzz-auth"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function testFuzz_unknownRouterAlwaysReverts(address unknownRouter) public {
        vm.assume(unknownRouter != address(router));
        vm.assume(!tradingExecutor.allowedRouters(unknownRouter));

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(RouterNotAllowed.selector, unknownRouter));
        tradingExecutor.executeTrade(
            keccak256("fuzz-router"),
            unknownRouter,
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function testFuzz_unknownTokenAlwaysReverts(address unknownToken) public {
        vm.assume(unknownToken != address(tokenIn) && unknownToken != address(tokenOut));
        vm.assume(!tradingExecutor.allowedTokens(unknownToken));

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, unknownToken));
        tradingExecutor.executeTrade(
            keccak256("fuzz-token"),
            address(router),
            unknownToken,
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }
}
