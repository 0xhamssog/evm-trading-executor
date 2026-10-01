// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TradingExecutor} from "../../src/TradingExecutor.sol";
import {ExecutorFixture} from "../utils/ExecutorFixture.sol";
import {AlreadyPaused, InvalidAddress, NotPaused, Unauthorized} from "../../src/errors/TradingErrors.sol";

contract AuthorizationTest is ExecutorFixture {
    function test_authorizedExecutorCanTrade() public {
        _prepare(100, 100);
        uint256 amountOut = _execute(keccak256("auth-ok"), 100, 95, block.timestamp + 1 hours);
        assertEq(amountOut, 100);
    }

    function test_unauthorizedCallerReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, stranger));
        tradingExecutor.executeTrade(
            keccak256("auth-no"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_executorCannotSetRouter() public {
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.setRouterAllowed(makeAddr("other-router"), true);
    }

    function test_executorCannotSetToken() public {
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.setTokenAllowed(makeAddr("other-token"), true);
    }

    function test_executorCannotPause() public {
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.pause();
    }

    function test_executorCannotReplaceItself() public {
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.setExecutor(stranger);
        assertEq(tradingExecutor.executor(), executorCaller);
    }

    function test_executorCannotProposeAdmin() public {
        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.proposeAdmin(stranger);
    }

    function test_adminCanRotateExecutor() public {
        address nextExecutor = makeAddr("next-executor");
        vm.prank(admin);
        tradingExecutor.setExecutor(nextExecutor);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.executeTrade(
            keccak256("old-executor"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );

        tokenIn.mint(nextExecutor, 100);
        tokenOut.mint(address(router), 100);
        router.setAmountOut(100);
        vm.startPrank(nextExecutor);
        tokenIn.approve(address(tradingExecutor), 100);
        uint256 amountOut = tradingExecutor.executeTrade(
            keccak256("new-executor"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            100,
            95,
            block.timestamp + 1 hours,
            recipient
        );
        vm.stopPrank();
        assertEq(amountOut, 100);
    }

    function test_adminTransferRequiresAcceptance() public {
        address nextAdmin = makeAddr("next-admin");
        vm.prank(admin);
        tradingExecutor.proposeAdmin(nextAdmin);
        assertEq(tradingExecutor.admin(), admin);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, stranger));
        tradingExecutor.acceptAdmin();

        vm.prank(nextAdmin);
        tradingExecutor.acceptAdmin();
        assertEq(tradingExecutor.admin(), nextAdmin);
        assertEq(tradingExecutor.pendingAdmin(), address(0));
    }

    function test_zeroAdminAndExecutorRejected() public {
        vm.expectRevert(InvalidAddress.selector);
        new TradingExecutor(address(0), executorCaller);

        vm.expectRevert(InvalidAddress.selector);
        new TradingExecutor(admin, address(0));
    }

    function test_zeroExecutorUpdateRejected() public {
        vm.prank(admin);
        vm.expectRevert(InvalidAddress.selector);
        tradingExecutor.setExecutor(address(0));
    }
}

contract PauseTest is ExecutorFixture {
    event PauseStateChanged(address indexed account, bool paused);

    function test_pauseBlocksExecutionAndUnpauseRestoresIt() public {
        vm.prank(admin);
        tradingExecutor.pause();

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSignature("ContractPaused()"));
        tradingExecutor.executeTrade(
            keccak256("paused"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );

        vm.prank(admin);
        tradingExecutor.unpause();

        _prepare(100, 100);
        uint256 amountOut = _execute(keccak256("resumed"), 100, 95, block.timestamp + 1 hours);
        assertEq(amountOut, 100);
    }

    function test_pauseAndUnpauseEmitEvents() public {
        vm.expectEmit(true, false, false, true, address(tradingExecutor));
        emit PauseStateChanged(admin, true);
        vm.prank(admin);
        tradingExecutor.pause();

        vm.expectEmit(true, false, false, true, address(tradingExecutor));
        emit PauseStateChanged(admin, false);
        vm.prank(admin);
        tradingExecutor.unpause();
    }

    function test_executorCannotUnpause() public {
        vm.prank(admin);
        tradingExecutor.pause();

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, executorCaller));
        tradingExecutor.unpause();
    }

    function test_doublePauseAndUnpauseReverts() public {
        vm.prank(admin);
        vm.expectRevert(NotPaused.selector);
        tradingExecutor.unpause();

        vm.startPrank(admin);
        tradingExecutor.pause();
        vm.expectRevert(AlreadyPaused.selector);
        tradingExecutor.pause();
        vm.stopPrank();
    }

    function test_adminWhoIsAlsoExecutorCannotTradeWhilePaused() public {
        vm.prank(admin);
        tradingExecutor.setExecutor(admin);
        vm.prank(admin);
        tradingExecutor.pause();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ContractPaused()"));
        tradingExecutor.executeTrade(
            keccak256("admin-paused"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_unauthorizedCallerStillUnauthorizedWhilePaused() public {
        vm.prank(admin);
        tradingExecutor.pause();

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, stranger));
        tradingExecutor.executeTrade(
            keccak256("paused-stranger"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            1,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }
}
