// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TradingExecutor} from "../../src/TradingExecutor.sol";
import {TradingExecutorHandler} from "./Handler.sol";

/// @notice System properties: a pause blocks fills, and only the admin can change allowlists.
contract TradingExecutorInvariantTest is Test {
    TradingExecutor internal tradingExecutor;
    TradingExecutorHandler internal handler;

    function setUp() public {
        address admin = makeAddr("admin");
        address executorCaller = makeAddr("executor");
        tradingExecutor = new TradingExecutor(admin, executorCaller);
        handler = new TradingExecutorHandler(tradingExecutor, admin, executorCaller);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.executeWhilePaused.selector;
        selectors[1] = handler.setRouter.selector;
        selectors[2] = handler.setToken.selector;
        selectors[3] = handler.executorAttemptsSetExecutor.selector;
        selectors[4] = handler.attemptUnpause.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

        handler.executeWhilePaused(keccak256("seed"), makeAddr("router"), 1);
        handler.setRouter(makeAddr("stranger"), makeAddr("router"), true);
        handler.setToken(makeAddr("stranger"), makeAddr("token"), true);
        handler.executorAttemptsSetExecutor(makeAddr("replacement"));
        handler.attemptUnpause(executorCaller);
    }

    function invariant_pausedBlocksExecution() public view {
        assertTrue(tradingExecutor.paused());
        assertEq(handler.tradesWhilePaused(), 0);
    }

    function invariant_nonAdminCannotChangeRouterAllowlist() public view {
        assertEq(handler.unauthorizedRouterWrites(), 0);
    }

    function invariant_nonAdminCannotChangeTokenAllowlist() public view {
        assertEq(handler.unauthorizedTokenWrites(), 0);
    }

    function invariant_executorCannotChangeAuthorization() public view {
        assertEq(tradingExecutor.executor(), handler.executorCaller());
        assertEq(handler.unauthorizedExecutorUpdates(), 0);
        assertEq(handler.unauthorizedUnpauses(), 0);
    }
}
