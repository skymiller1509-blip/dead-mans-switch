// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { DeadMansSwitch } from "../src/DeadMansSwitch.sol";

/// @notice Deploys the reactive contract on Lasna testnet (chain 5318007).
/// @dev Run: forge script script/DeploySwitch.s.sol --rpc-url lasna --broadcast
/// Env: VAULT_ADDRESS (optional, 0x0 to deploy first and set it later),
/// INACTIVITY_DAYS (default 30), CRON_TOPIC (0 = Cron1000 ~17 min).
/// After this, deploy the vault on Base Sepolia (DeployVault.s.sol), then
/// point this contract at it with SetVault.s.sol.
contract DeploySwitch is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address vault = vm.envOr("VAULT_ADDRESS", address(0));
        uint256 inactivityDays = vm.envOr("INACTIVITY_DAYS", uint256(30));
        uint256 cronTopic = vm.envOr(
            "CRON_TOPIC",
            // Cron1000 topic from the docs (same value as the contract's
            // CRON1000_TOPIC_0 constant).
            uint256(
                0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4
            )
        );

        vm.startBroadcast(deployerKey);
        DeadMansSwitch sw = new DeadMansSwitch(vault, inactivityDays, cronTopic);
        vm.stopBroadcast();

        // Fund the switch with lREACT so it can pay for its subscriptions
        // and callbacks (Reactive bills reactive contracts for their work).
        // Send a small amount to the contract address after deploy.
        console.log("DeadMansSwitch (Lasna):", address(sw));
        console.log("inactivityDays:", inactivityDays);
        console.log("cronTopic:", cronTopic);
    }
}
