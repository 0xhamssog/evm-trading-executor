// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {TradingExecutor} from "../../src/TradingExecutor.sol";

/// @notice Calls the executor in ways an unauthorized user might. Successful mutations are counted.
contract TradingExecutorHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    TradingExecutor public immutable tradingExecutor;
    address public immutable admin;
    address public immutable executorCaller;

    uint256 public tradesWhilePaused;
    uint256 public unauthorizedRouterWrites;
    uint256 public unauthorizedTokenWrites;
    uint256 public unauthorizedExecutorUpdates;
    uint256 public unauthorizedUnpauses;

    constructor(TradingExecutor tradingExecutor_, address admin_, address executorCaller_) {
        tradingExecutor = tradingExecutor_;
        admin = admin_;
        executorCaller = executorCaller_;
    }

    function executeWhilePaused(bytes32 operationId, address router, uint256 amountIn) external {
        if (!tradingExecutor.paused()) {
            vm.prank(admin);
            (bool pausedOk,) = address(tradingExecutor).call(abi.encodeCall(TradingExecutor.pause, ()));
            require(pausedOk, "pause");
        }

        vm.prank(executorCaller);
        (bool success,) = address(tradingExecutor)
            .call(
                abi.encodeCall(
                    TradingExecutor.executeTrade,
                    (operationId, router, address(1), address(2), amountIn, 1, type(uint256).max, address(3))
                )
            );
        if (success) tradesWhilePaused++;
    }

    function setRouter(address caller, address router, bool allowed) external {
        if (caller == address(0) || caller == admin || router == address(0)) return;
        bool before = tradingExecutor.allowedRouters(router);
        vm.prank(caller);
        (bool success,) =
            address(tradingExecutor).call(abi.encodeCall(TradingExecutor.setRouterAllowed, (router, allowed)));
        if (success || tradingExecutor.allowedRouters(router) != before) unauthorizedRouterWrites++;
    }

    function setToken(address caller, address token, bool allowed) external {
        if (caller == address(0) || caller == admin || token == address(0)) return;
        bool before = tradingExecutor.allowedTokens(token);
        vm.prank(caller);
        (bool success,) =
            address(tradingExecutor).call(abi.encodeCall(TradingExecutor.setTokenAllowed, (token, allowed)));
        if (success || tradingExecutor.allowedTokens(token) != before) unauthorizedTokenWrites++;
    }

    function executorAttemptsSetExecutor(address newExecutor) external {
        if (newExecutor == address(0)) return;
        address before = tradingExecutor.executor();
        vm.prank(executorCaller);
        (bool success,) = address(tradingExecutor).call(abi.encodeCall(TradingExecutor.setExecutor, (newExecutor)));
        if (success || tradingExecutor.executor() != before) unauthorizedExecutorUpdates++;
    }

    function attemptUnpause(address caller) external {
        if (caller == address(0) || caller == admin) return;
        bool before = tradingExecutor.paused();
        vm.prank(caller);
        (bool success,) = address(tradingExecutor).call(abi.encodeCall(TradingExecutor.unpause, ()));
        if (success || tradingExecutor.paused() != before) unauthorizedUnpauses++;
    }
}
