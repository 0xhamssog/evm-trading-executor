// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TradingExecutor} from "../src/TradingExecutor.sol";

/// @notice Deploy `TradingExecutor`.
/// @dev Foundry supplies the signer at broadcast time. This script does not read or store a key.
contract Deploy is Script {
    function run() external returns (TradingExecutor tradingExecutor) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address executorCaller = vm.envAddress("EXECUTOR_CALLER");

        vm.startBroadcast();
        tradingExecutor = new TradingExecutor(admin, executorCaller);
        vm.stopBroadcast();

        console2.log("TradingExecutor", address(tradingExecutor));
    }
}
