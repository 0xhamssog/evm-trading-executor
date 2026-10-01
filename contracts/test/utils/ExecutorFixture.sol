// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TradingExecutor} from "../../src/TradingExecutor.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockTradingRouter} from "../mocks/MockTradingRouter.sol";

/// @notice Shared deployment for executor tests.
abstract contract ExecutorFixture is Test {
    TradingExecutor internal tradingExecutor;
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockTradingRouter internal router;

    address internal admin;
    address internal executorCaller;
    address internal stranger;
    address internal recipient;

    event TradeExecuted(
        bytes32 indexed operationId,
        address indexed router,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    function setUp() public virtual {
        admin = makeAddr("admin");
        executorCaller = makeAddr("executor");
        stranger = makeAddr("stranger");
        recipient = makeAddr("recipient");

        tradingExecutor = new TradingExecutor(admin, executorCaller);
        tokenIn = new MockERC20("Mock Token In", "TIN", 18);
        tokenOut = new MockERC20("Mock Token Out", "TOUT", 18);
        router = new MockTradingRouter();

        vm.startPrank(admin);
        tradingExecutor.setRouterAllowed(address(router), true);
        tradingExecutor.setTokenAllowed(address(tokenIn), true);
        tradingExecutor.setTokenAllowed(address(tokenOut), true);
        vm.stopPrank();
    }

    function _prepare(uint256 amountIn, uint256 amountOut) internal {
        tokenIn.mint(executorCaller, amountIn);
        if (amountOut != 0) tokenOut.mint(address(router), amountOut);
        router.setAmountOut(amountOut);
        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), amountIn);
    }

    function _execute(bytes32 operationId, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        internal
        returns (uint256)
    {
        vm.prank(executorCaller);
        return tradingExecutor.executeTrade(
            operationId,
            address(router),
            address(tokenIn),
            address(tokenOut),
            amountIn,
            minAmountOut,
            deadline,
            recipient
        );
    }
}
