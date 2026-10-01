// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// @notice Opt-in fork harness.
/// @dev No protocol address is hardcoded. A fork is created only when `FORK_RPC_URL` is set
///      to an endpoint the operator controls. This file does not claim a live integration.
contract ForkFrameworkTest is Test {
    function test_forkIsOptIn() public {
        string memory rpcUrl = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            assertEq(bytes(rpcUrl).length, 0);
            return;
        }

        vm.createSelectFork(rpcUrl);
        assertGt(block.chainid, 0);
        assertGt(block.number, 0);
    }
}
