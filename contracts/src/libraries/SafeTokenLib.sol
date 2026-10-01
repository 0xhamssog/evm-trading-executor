// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../interfaces/IERC20Minimal.sol";
import {TokenCallFailed, UnexpectedBalance} from "../errors/TradingErrors.sol";

/// @notice ERC-20 helpers that tolerate missing boolean return data.
/// @dev Allowance changes follow OpenZeppelin `SafeERC20.forceApprove`: try the desired
///      approval, and if that fails reset to zero before retrying. That supports tokens
///      that revert when a non-zero allowance is overwritten.
library SafeTokenLib {
    /// @notice Read `account`'s balance of `token`.
    function balanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC20Minimal.balanceOf, (account)));
        if (!success || data.length < 32) revert TokenCallFailed();
        return abi.decode(data, (uint256));
    }

    /// @notice Transfer `amount` and require a successful ERC-20 response.
    function safeTransfer(address token, address to, uint256 amount) internal {
        _callAndCheck(token, abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
    }

    /// @notice Pull `amount` of `token` from `from` to `to`.
    /// @return received Actual balance increase of `to`. Fee-on-transfer tokens therefore
    ///         cannot silently deliver a smaller amount.
    function safeTransferFrom(address token, address from, address to, uint256 amount)
        internal
        returns (uint256 received)
    {
        uint256 beforeBalance = balanceOf(token, to);
        _callAndCheck(token, abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        uint256 afterBalance = balanceOf(token, to);
        if (afterBalance < beforeBalance) revert UnexpectedBalance();
        received = afterBalance - beforeBalance;
    }

    /// @notice Set `spender` allowance to `amount`, including the zero-reset fallback.
    function forceApprove(address token, address spender, uint256 amount) internal {
        bytes memory desired = abi.encodeCall(IERC20Minimal.approve, (spender, amount));
        if (_returnedTrue(token, desired)) return;

        if (amount != 0 && _returnedTrue(token, abi.encodeCall(IERC20Minimal.approve, (spender, 0)))) {
            _callAndCheck(token, desired);
            return;
        }

        revert TokenCallFailed();
    }

    function _callAndCheck(address token, bytes memory data) private {
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) _bubble(returndata);
        if (!_boolResult(returndata)) revert TokenCallFailed();
    }

    /// @dev Returns false when the call reverts or the token returns false. Used by the
    ///      approval fallback, where the first failure is an expected token quirk.
    function _returnedTrue(address token, bytes memory data) private returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        return success && _boolResult(returndata);
    }

    /// @dev Empty return data is treated as success. A short or `false` payload is failure.
    function _boolResult(bytes memory returndata) private pure returns (bool) {
        if (returndata.length == 0) return true;
        if (returndata.length < 32) return false;
        return abi.decode(returndata, (bool));
    }

    /// @dev Re-raise the token's revert payload. Assembly is used only because Solidity has
    ///      no high-level statement that reverts with an existing returndata buffer.
    function _bubble(bytes memory returndata) private pure {
        if (returndata.length == 0) revert TokenCallFailed();
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returndata, 32), mload(returndata))
        }
    }
}
