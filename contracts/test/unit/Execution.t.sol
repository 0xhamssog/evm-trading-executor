// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ExecutorFixture} from "../utils/ExecutorFixture.sol";
import {TradingExecutor} from "../../src/TradingExecutor.sol";
import {DishonestRouter} from "../mocks/DishonestRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {InsufficientOutput, Reentrancy, UnexpectedBalance} from "../../src/errors/TradingErrors.sol";

contract SlippageAndEventTest is ExecutorFixture {
    function test_outputAboveMinimumSucceeds() public {
        _prepare(100, 100);
        uint256 amountOut = _execute(keccak256("slip-ok"), 100, 95, block.timestamp + 1 hours);
        assertEq(amountOut, 100);
        assertEq(tokenOut.balanceOf(recipient), 100);
    }

    function test_outputEqualToMinimumSucceeds() public {
        _prepare(100, 95);
        uint256 amountOut = _execute(keccak256("slip-eq"), 100, 95, block.timestamp + 1 hours);
        assertEq(amountOut, 95);
    }

    function test_outputBelowMinimumReverts() public {
        _prepare(100, 90);
        uint256 callerBefore = tokenIn.balanceOf(executorCaller);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSelector(InsufficientOutput.selector, 90, 95));
        tradingExecutor.executeTrade(
            keccak256("slip-bad"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            100,
            95,
            block.timestamp + 1 hours,
            recipient
        );

        assertEq(tokenIn.balanceOf(executorCaller), callerBefore);
        assertEq(tokenOut.balanceOf(recipient), 0);
        assertEq(tokenIn.balanceOf(address(tradingExecutor)), 0);
    }

    function test_tradeExecutedEventMatchesFill() public {
        uint256 amountIn = 100;
        uint256 amountOut = 100;
        bytes32 operationId = keccak256("event");
        _prepare(amountIn, amountOut);

        vm.expectEmit(true, true, true, true, address(tradingExecutor));
        emit TradeExecuted(
            operationId, address(router), address(tokenIn), address(tokenOut), amountIn, amountOut, recipient
        );
        _execute(operationId, amountIn, 95, block.timestamp + 1 hours);
    }
}

/// @notice Calls back into the executor while the first trade is still open.
contract ReentrantTrader {
    TradingExecutor public tradingExecutor;
    address public router;
    address public tokenIn;
    address public tokenOut;
    address public recipient;
    bytes32 public operationId;
    uint256 public amountIn;
    uint256 public minAmountOut;
    uint256 public deadline;

    function configure(
        TradingExecutor tradingExecutor_,
        address router_,
        address tokenIn_,
        address tokenOut_,
        address recipient_,
        bytes32 operationId_,
        uint256 amountIn_,
        uint256 minAmountOut_,
        uint256 deadline_
    ) external {
        tradingExecutor = tradingExecutor_;
        router = router_;
        tokenIn = tokenIn_;
        tokenOut = tokenOut_;
        recipient = recipient_;
        operationId = operationId_;
        amountIn = amountIn_;
        minAmountOut = minAmountOut_;
        deadline = deadline_;
    }

    function attackTrade() external {
        tradingExecutor.executeTrade(
            operationId, router, tokenIn, tokenOut, amountIn, minAmountOut, deadline, recipient
        );
    }
}

/// @notice Router test double that re-enters the authorized executor during `swap`.
contract ReenteringRouter {
    ReentrantTrader public trader;
    bool public attempted;

    constructor(ReentrantTrader trader_) {
        trader = trader_;
    }

    function swap(address, address, uint256, uint256, address) external returns (uint256) {
        if (!attempted) {
            attempted = true;
            trader.attackTrade();
        }
        return 0;
    }
}

contract FailurePathTest is ExecutorFixture {
    function test_routerRevertBubbles() public {
        _prepare(50, 50);
        router.setShouldRevert(true);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSignature("RouterSwapFailed()"));
        tradingExecutor.executeTrade(
            keccak256("router-revert"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            50,
            50,
            block.timestamp + 1 hours,
            recipient
        );

        assertEq(tokenIn.balanceOf(executorCaller), 50);
        assertFalse(tradingExecutor.usedOperationIds(keccak256("router-revert")));
    }

    function test_dishonestRouterReportReverts() public {
        DishonestRouter dishonest = new DishonestRouter();
        dishonest.configure(90, 100);
        tokenOut.mint(address(dishonest), 90);
        tokenIn.mint(executorCaller, 100);

        vm.prank(admin);
        tradingExecutor.setRouterAllowed(address(dishonest), true);
        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), 100);

        vm.prank(executorCaller);
        vm.expectRevert(UnexpectedBalance.selector);
        tradingExecutor.executeTrade(
            keccak256("dishonest"),
            address(dishonest),
            address(tokenIn),
            address(tokenOut),
            100,
            95,
            block.timestamp + 1 hours,
            recipient
        );
        assertEq(tokenOut.balanceOf(recipient), 0);
    }

    function test_reentrancyReverts() public {
        ReentrantTrader trader = new ReentrantTrader();
        ReenteringRouter attackingRouter = new ReenteringRouter(trader);
        MockERC20 inToken = new MockERC20("Reentrant In", "RIN", 18);
        MockERC20 outToken = new MockERC20("Reentrant Out", "ROUT", 18);

        vm.startPrank(admin);
        tradingExecutor.setExecutor(address(trader));
        tradingExecutor.setRouterAllowed(address(attackingRouter), true);
        tradingExecutor.setTokenAllowed(address(inToken), true);
        tradingExecutor.setTokenAllowed(address(outToken), true);
        vm.stopPrank();

        inToken.mint(address(trader), 10);
        vm.prank(address(trader));
        inToken.approve(address(tradingExecutor), 10);

        trader.configure(
            tradingExecutor,
            address(attackingRouter),
            address(inToken),
            address(outToken),
            recipient,
            keccak256("reenter"),
            10,
            1,
            block.timestamp + 1 hours
        );

        vm.expectRevert(Reentrancy.selector);
        trader.attackTrade();
        assertEq(inToken.balanceOf(address(trader)), 10);
        assertEq(outToken.balanceOf(recipient), 0);
    }

    function test_nonStandardTokenWithoutReturnDataSucceeds() public {
        _prepare(30, 30);
        tokenIn.setOmitReturnData(true);
        tokenOut.setOmitReturnData(true);

        uint256 amountOut = _execute(keccak256("no-return"), 30, 30, block.timestamp + 1 hours);
        assertEq(amountOut, 30);
        assertEq(tokenOut.balanceOf(recipient), 30);
    }

    function test_tokenReturningFalseReverts() public {
        tokenIn.mint(executorCaller, 15);
        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), 15);
        tokenIn.setReturnFalse(true);
        router.setAmountOut(15);

        vm.prank(executorCaller);
        vm.expectRevert(abi.encodeWithSignature("TokenCallFailed()"));
        tradingExecutor.executeTrade(
            keccak256("false-return"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            15,
            1,
            block.timestamp + 1 hours,
            recipient
        );
        assertEq(tokenIn.balanceOf(executorCaller), 15);
    }

    function test_approvalResetFallbackStillTrades() public {
        _prepare(20, 20);
        tokenIn.setRejectNonZeroOverwrite(true);
        tokenIn.forceAllowance(address(tradingExecutor), address(router), 1);

        uint256 amountOut = _execute(keccak256("approve-reset"), 20, 20, block.timestamp + 1 hours);
        assertEq(amountOut, 20);
        assertEq(tokenIn.allowance(address(tradingExecutor), address(router)), 0);
    }

    function test_tokenRevertReasonBubbles() public {
        vm.prank(executorCaller);
        tokenIn.approve(address(tradingExecutor), 10);

        vm.prank(executorCaller);
        vm.expectRevert(MockERC20.InsufficientBalance.selector);
        tradingExecutor.executeTrade(
            keccak256("bubble"),
            address(router),
            address(tokenIn),
            address(tokenOut),
            10,
            1,
            block.timestamp + 1 hours,
            recipient
        );
    }

    function test_allowanceIsExactDuringSwapAndClearedAfter() public {
        _prepare(80, 80);
        _execute(keccak256("allowance"), 80, 80, block.timestamp + 1 hours);

        assertEq(router.payerAtSwap(), address(tradingExecutor));
        assertEq(router.allowanceAtSwap(), 80);
        assertEq(tokenIn.allowance(address(tradingExecutor), address(router)), 0);
        assertEq(tokenIn.balanceOf(address(tradingExecutor)), 0);
        assertEq(tokenOut.balanceOf(address(tradingExecutor)), 0);
    }
}
