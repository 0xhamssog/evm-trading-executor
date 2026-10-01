// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITradingRouter} from "./interfaces/ITradingRouter.sol";
import {SafeTokenLib} from "./libraries/SafeTokenLib.sol";
import {ValidationLib} from "./libraries/ValidationLib.sol";
import {
    AlreadyPaused,
    ContractPaused,
    InsufficientOutput,
    InvalidAddress,
    InvalidOperationId,
    NotPaused,
    OperationAlreadyUsed,
    Reentrancy,
    RouterNotAllowed,
    TokenNotAllowed,
    Unauthorized,
    UnexpectedBalance
} from "./errors/TradingErrors.sol";

/// @title TradingExecutor
/// @notice Constrained execution layer for an EVM trading application.
/// @dev This contract does not choose trades. A caller submits an already validated request.
///      The only external protocol call is `ITradingRouter.swap` on an allowlisted router.
///
///      Approval model:
///      1. The authorized executor must approve this contract for `amountIn`.
///      2. This contract pulls that exact amount and approves the allowlisted router.
///      3. The router allowance is reset to zero before the call returns.
///
///      Tokens that move a different amount than requested (fee-on-transfer) are rejected.
///      The recipient's `tokenOut` balance increase is the canonical output. It must equal
///      the router report and be at least `minAmountOut`.
contract TradingExecutor {
    using SafeTokenLib for address;

    /// @notice Account that can configure allowlists, pause, and rotate roles.
    address public admin;

    /// @notice Proposed admin. Becomes admin only after `acceptAdmin`.
    address public pendingAdmin;

    /// @notice Sole account allowed to call `executeTrade`.
    address public executor;

    /// @notice When true, `executeTrade` reverts.
    bool public paused;

    /// @notice Routers this contract may call.
    mapping(address router => bool allowed) public allowedRouters;

    /// @notice Tokens that may be used as `tokenIn` or `tokenOut`.
    mapping(address token => bool allowed) public allowedTokens;

    /// @notice Operation ids consumed by a successful trade.
    mapping(bytes32 operationId => bool used) public usedOperationIds;

    bool private _locked;

    /// @notice Emitted when a trade has been delivered to `recipient`.
    event TradeExecuted(
        bytes32 indexed operationId,
        address indexed router,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    /// @notice Emitted when trading is paused or unpaused.
    event PauseStateChanged(address indexed account, bool paused);

    /// @notice Emitted when a router is added to or removed from the allowlist.
    event RouterAllowlistUpdated(address indexed router, bool allowed);

    /// @notice Emitted when a token is added to or removed from the allowlist.
    event TokenAllowlistUpdated(address indexed token, bool allowed);

    /// @notice Emitted when the authorized executor changes.
    event ExecutorUpdated(address indexed previousExecutor, address indexed newExecutor);

    /// @notice Emitted when an admin handoff is proposed.
    event AdminProposed(address indexed currentAdmin, address indexed pendingAdmin);

    /// @notice Emitted when the proposed admin accepts the role.
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor) revert Unauthorized(msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    /// @param initialAdmin Account that will configure the contract.
    /// @param initialExecutor Account that will be allowed to execute trades.
    constructor(address initialAdmin, address initialExecutor) {
        if (initialAdmin == address(0) || initialExecutor == address(0)) revert InvalidAddress();
        admin = initialAdmin;
        executor = initialExecutor;
        emit AdminUpdated(address(0), initialAdmin);
        emit ExecutorUpdated(address(0), initialExecutor);
    }

    /// @notice Start a two-step admin transfer.
    /// @param newAdmin Account that must call `acceptAdmin`.
    function proposeAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        pendingAdmin = newAdmin;
        emit AdminProposed(admin, newAdmin);
    }

    /// @notice Accept an admin transfer. Callable only by `pendingAdmin`.
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert Unauthorized(msg.sender);
        address previous = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminUpdated(previous, msg.sender);
    }

    /// @notice Replace the account allowed to execute trades.
    /// @param newExecutor Next executor. The previous executor loses execution rights immediately.
    function setExecutor(address newExecutor) external onlyAdmin {
        if (newExecutor == address(0)) revert InvalidAddress();
        address previous = executor;
        executor = newExecutor;
        emit ExecutorUpdated(previous, newExecutor);
    }

    /// @notice Add or remove a router.
    /// @param router Router that implements `ITradingRouter`.
    /// @param allowed True to allow calls to `router`.
    function setRouterAllowed(address router, bool allowed) external onlyAdmin {
        if (router == address(0)) revert InvalidAddress();
        allowedRouters[router] = allowed;
        emit RouterAllowlistUpdated(router, allowed);
    }

    /// @notice Add or remove a token.
    /// @param token ERC-20 address. Symbols are never used as identifiers.
    /// @param allowed True to allow the token as input or output.
    function setTokenAllowed(address token, bool allowed) external onlyAdmin {
        if (token == address(0)) revert InvalidAddress();
        allowedTokens[token] = allowed;
        emit TokenAllowlistUpdated(token, allowed);
    }

    /// @notice Pause trading. Admin configuration remains available.
    function pause() external onlyAdmin {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit PauseStateChanged(msg.sender, true);
    }

    /// @notice Resume trading.
    function unpause() external onlyAdmin {
        if (!paused) revert NotPaused();
        paused = false;
        emit PauseStateChanged(msg.sender, false);
    }

    /// @notice Pull `tokenIn` from the caller, swap it through an allowlisted router, and pay `recipient`.
    /// @param operationId Deterministic id generated offchain. Consumed only if this call succeeds.
    /// @param router Allowlisted `ITradingRouter`.
    /// @param tokenIn Allowlisted input token. The caller must have approved this contract.
    /// @param tokenOut Allowlisted output token.
    /// @param amountIn Exact input amount. Must be non-zero and must arrive in full.
    /// @param minAmountOut Minimum `tokenOut` the recipient must receive. Must be non-zero.
    /// @param deadline Unix timestamp. The trade reverts when `block.timestamp` is greater.
    /// @param recipient Account that receives `tokenOut`. Must not be the zero address.
    /// @return amountOut Canonical `tokenOut` received by `recipient`.
    function executeTrade(
        bytes32 operationId,
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address recipient
    ) external nonReentrant onlyExecutor whenNotPaused returns (uint256 amountOut) {
        if (operationId == bytes32(0)) revert InvalidOperationId();
        if (usedOperationIds[operationId]) revert OperationAlreadyUsed(operationId);
        if (!allowedRouters[router]) revert RouterNotAllowed(router);
        if (!allowedTokens[tokenIn]) revert TokenNotAllowed(tokenIn);
        if (!allowedTokens[tokenOut]) revert TokenNotAllowed(tokenOut);
        ValidationLib.validateTradeInputs(tokenIn, tokenOut, amountIn, minAmountOut, deadline, recipient);

        usedOperationIds[operationId] = true;

        uint256 received = tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        if (received != amountIn) revert UnexpectedBalance();

        // Exact allowance for this call. Cleared before the function returns.
        tokenIn.forceApprove(router, amountIn);

        uint256 recipientBefore = tokenOut.balanceOf(recipient);
        uint256 reported = ITradingRouter(router).swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient);
        uint256 recipientAfter = tokenOut.balanceOf(recipient);

        tokenIn.forceApprove(router, 0);

        uint256 leftover = tokenIn.balanceOf(address(this));
        if (leftover != 0) tokenIn.safeTransfer(msg.sender, leftover);

        if (recipientAfter < recipientBefore) revert UnexpectedBalance();
        amountOut = recipientAfter - recipientBefore;
        if (reported != amountOut) revert UnexpectedBalance();
        if (amountOut < minAmountOut) revert InsufficientOutput(amountOut, minAmountOut);

        emit TradeExecuted(operationId, router, tokenIn, tokenOut, amountIn, amountOut, recipient);
    }
}
