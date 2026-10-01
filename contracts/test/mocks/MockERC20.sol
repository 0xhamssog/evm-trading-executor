// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockERC20
/// @notice Test double for an ERC-20. Not a production token.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    /// @notice When true, transfer and approve return no boolean. Used to test safe token calls.
    bool public omitReturnData;

    /// @notice When true, transfer and approve return false after performing the state change.
    bool public returnFalse;

    /// @notice When true, a non-zero allowance cannot be changed to another non-zero value.
    bool public rejectNonZeroOverwrite;

    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();
    error NonZeroApproval();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @notice Mint `amount` to `to`. Open on purpose: this contract is only deployed in tests.
    function mint(address to, uint256 amount) external {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function setOmitReturnData(bool enabled) external {
        omitReturnData = enabled;
    }

    function setReturnFalse(bool enabled) external {
        returnFalse = enabled;
    }

    function setRejectNonZeroOverwrite(bool enabled) external {
        rejectNonZeroOverwrite = enabled;
    }

    /// @notice Test-only allowance write. Production tokens do not expose this.
    function forceAllowance(address owner, address spender, uint256 amount) external {
        allowance[owner][spender] = amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        uint256 current = allowance[msg.sender][spender];
        if (rejectNonZeroOverwrite && current != 0 && amount != 0) revert NonZeroApproval();
        allowance[msg.sender][spender] = amount;
        return _finish();
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return _finish();
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        return _finish();
    }

    function _move(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();
        balanceOf[from] = balance - amount;
        balanceOf[to] += amount;
    }

    function _finish() private view returns (bool) {
        if (omitReturnData) {
            assembly {
                return(0, 0)
            }
        }
        if (returnFalse) return false;
        return true;
    }
}
