// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DeadMansVault } from "../src/DeadMansVault.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice Deploys the vault on Base Sepolia (chain 84532) and deposits the
/// inheritance amount in the same transaction.
/// @dev Run: forge script script/DeployVault.s.sol --rpc-url base-sepolia --broadcast
/// Env: PRIVATE_KEY, REACTIVE_ADDRESS (the Lasna DeadMansSwitch),
/// HEIR_ADDRESS, INACTIVITY_DAYS (default 30), DEPOSIT_ETH (default 0.01).
/// The deployer becomes the vault owner. Keep a little extra ETH in the
/// vault: the release callback is billed to the vault in ETH.
contract DeployVault is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address reactive = vm.envAddress("REACTIVE_ADDRESS");
        address heir = vm.envAddress("HEIR_ADDRESS");
        uint256 inactivityDays = vm.envOr("INACTIVITY_DAYS", uint256(30));
        uint256 deposit = vm.envOr("DEPOSIT_ETH", uint256(0.01 ether));

        // Base Sepolia callback proxy, from dev.reactive.network.
        IPayable proxy = IPayable(
            payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585)
        );

        vm.startBroadcast(deployerKey);
        DeadMansVault vault = new DeadMansVault{ value: deposit }(
            proxy,
            reactive,
            vm.addr(deployerKey),
            heir,
            inactivityDays
        );
        vm.stopBroadcast();

        console.log("DeadMansVault (Base Sepolia):", address(vault));
        console.log("inactivityDays:", inactivityDays);
        console.log("depositWei:", deposit);
    }
}
