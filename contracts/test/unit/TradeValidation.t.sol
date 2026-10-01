// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ExecutorFixture} from "../utils/ExecutorFixture.sol";
import {
    DeadlineExpired,
    IdenticalTokens,
    InvalidAddress,
    InvalidAmount,
    InvalidOperationId,
    InvalidRecipient,
    OperationAlreadyUsed,
    RouterNotAllowed,
    TokenNotAllowed
} from "../../src/errors/TradingErrors.sol";

contract AllowlistTest is ExecutorFixture {
    function test_unknownRouterReverts() public {
        address unknown = makeAddr("unknown-router");
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(RouterNotAllowed.selector, unknown));
        tradingExecutor.executeTrade(
            keccak256("router"),
            unknown,
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_removedRouterReverts() public {
        vm.prank(admin);
        tradingExecutor.setRouterAllowed(address(router), false);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(RouterNotAllowed.selector, address(router)));
        tradingExecutor.executeTrade(
            keccak256("router-removed"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_unknownTokenInReverts() public {
        address unknown = makeAddr("unknown-in");
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, unknown));
        tradingExecutor.executeTrade(
            keccak256("token-in"),
            address(router),
            unknown,
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_unknownTokenOutReverts() public {
        address unknown = makeAddr("unknown-out");
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, unknown));
        tradingExecutor.executeTrade(
            keccak256("token-out"),
            address(router),
            address(tokenIn),
            unknown,
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_removedTokenReverts() public {
        vm.prank(admin);
        tradingExecutor.setTokenAllowed(address(tokenIn), false);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(TokenNotAllowed.selector, address(tokenIn)));
        tradingExecutor.executeTrade(
            keccak256("token-removed"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_zeroRouterAndTokenCannotBeAllowlisted() public {
        vm.startPrank(admin);
        vm.expectRevert(InvalidAddress.selector);
        tradingExecutor.setRouterAllowed(address(0), true);
        vm.expectRevert(InvalidAddress.selector);
        tradingExecutor.setTokenAllowed(address(0), true);
        vm.stopPrank();
    }
}

contract ValidationTest is ExecutorFixture {
    function test_zeroAmountInReverts() public {
        vm.prank(executorCaller);
        vm.expectRevert(InvalidAmount.selector);
        tradingExecutor.executeTrade(
            keccak256("zero-in"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            0,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_zeroMinAmountOutReverts() public {
        vm.prank(executorCaller);
        vm.expectRevert(InvalidAmount.selector);
        tradingExecutor.executeTrade(
            keccak256("zero-min"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            0,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_validAmountSucceeds() public {
        _prepare(25, 25);
        uint256 amountOut = _execute(keccak256("valid-amount"), 25, 20, block.timestamp + 1 hours);
        assertEq(amountOut, 25);
    }

    function test_deadlineEqualToTimestampSucceeds() public {
        vm.warp(1_000);
        _prepare(10, 10);
        uint256 amountOut = _execute(keccak256("deadline-eq"), 10, 10, 1_000);
        assertEq(amountOut, 10);
    }

    function test_futureDeadlineSucceeds() public {
        _prepare(10, 10);
        uint256 amountOut = _execute(keccak256("deadline-future"), 10, 10, block.timestamp + 1 days);
        assertEq(amountOut, 10);
    }

    function test_expiredDeadlineReverts() public {
        vm.warp(500);
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(DeadlineExpired.selector, 499, 500));
        tradingExecutor.executeTrade(
            keccak256("expired"), address(router), address(tokenIn), address(tokenOut), 1, 1, 499, recipient
        );
    }

    function test_zeroRecipientReverts() public {
        vm.prank(executorCaller);
        vm.expectRevert(InvalidRecipient.selector);
        tradingExecutor.executeTrade(
            keccak256("recipient"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            address(0)
        );
    }

    function test_identicalTokensRevert() public {
        vm.prank(executorCaller);
        vm.expectRevert(IdenticalTokens.selector);
        tradingExecutor.executeTrade(
            keccak256("same-token"),
            address(router),
            address(tokenIn),
            address(tokenIn),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_zeroOperationIdReverts() public {
        vm.prank(executorCaller);
        vm.expectRevert(InvalidOperationId.selector);
        tradingExecutor.executeTrade(
            bytes32(0), address(router), address(tokenIn), address(tokenOut), 1, 1, block.timestamp + 1 hours, recipient
        );
    }

    function test_successfulOperationIdCannotBeReplayed() public {
        _prepare(40, 40);
        bytes32 operationId = keccak256("once");
        _execute(operationId, 20, 20, block.timestamp + 1 hours);

        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), 20);
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(OperationAlreadyUsed.selector, operationId));
        tradingExecutor.executeTrade(
            operationId,
            address(router),
            address(tokenIn),
            address(tokenOut),
            20,
            20,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_revertedTradeDoesNotConsumeOperationId() public {
        _prepare(100, 90);
        bytes32 operationId = keccak256("retry");

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSignature("InsufficientOutput(uint256,uint256)", 90, 95));
        tradingExecutor.executeTrade(
            operationId,
            address(router),
            address(tokenIn),
            address(tokenOut),
            100,
            95,
            block.timestamp + 1 hours,
            recipient
        );
        assertFalse(tradingExecutor.usedOperationIds(operationId));

        router.setAmountOut(100);
        tokenOut.mint(address(router), 100);
        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), 100);
        uint256 amountOut = _execute(operationId, 100, 95, block.timestamp + 1 hours);
        assertEq(amountOut, 100);
        assertTrue(tradingExecutor.usedOperationIds(operationId));
    }
}
