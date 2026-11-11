// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DeadMansSwitch } from "../src/DeadMansSwitch.sol";

/// @notice Points the Lasna switch at the deployed vault (owner only).
/// @dev Run: forge script script/SetVault.s.sol --rpc-url lasna --broadcast
/// Env: PRIVATE_KEY (must be the switch owner's key),
/// SWITCH_ADDRESS, VAULT_ADDRESS.
contract SetVault is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address payable swAddr = payable(vm.envAddress("SWITCH_ADDRESS"));
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(deployerKey);
        DeadMansSwitch(swAddr).setVault(vaultAddr);
        vm.stopBroadcast();

        console.log("Switch now watches vault:", vaultAddr);
    }
}
