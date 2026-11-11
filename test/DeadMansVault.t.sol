// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { DeadMansVault } from "../src/DeadMansVault.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice Local proof of the vault logic. No testnet, no real funds:
/// Foundry's vm.warp fast-forwards block.timestamp so "30 days of silence"
/// can be tested in milliseconds.
contract DeadMansVaultTest is Test {
    // The real Base Sepolia callback proxy from the docs is
    // 0x476F44b11F5C942c58f4c8E3d0300E5710743585. Locally we stand in
    // fake addresses for the proxy and the reactive contract.
    address payable internal constant PROXY = payable(address(0xBEEF));
    address internal constant REACTIVE = address(0xCAFE);

    address internal owner = makeAddr("owner");
    address internal heir = makeAddr("heir");
    uint256 internal constant PERIOD_DAYS = 30;

    DeadMansVault internal vault;

    function setUp() public {
        vm.prank(owner);
        vault = new DeadMansVault(
            IPayable(PROXY),
            REACTIVE,
            owner,
            heir,
            PERIOD_DAYS
        );
        vm.deal(owner, 10 ether);
    }

    function testDepositRecordsActivityAndBalance() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        assertEq(address(vault).balance, 1 ether);
        assertEq(vault.lastActive(), block.timestamp);
    }

    function testPlainTransferCountsAsActivity() public {
        vm.warp(block.timestamp + 5 days);
        vm.prank(owner);
        (bool ok, ) = address(vault).call{ value: 0.5 ether }("");
        assertTrue(ok);
        assertEq(vault.lastActive(), block.timestamp);
    }

    function testPingResetsClock() public {
        uint256 start = vault.lastActive();
        vm.warp(start + 10 days);
        vm.prank(owner);
        vault.ping();
        assertEq(vault.lastActive(), start + 10 days);
        assertFalse(vault.isInactive());
    }

    function testPingOnlyOwner() public {
        vm.expectRevert(DeadMansVault.NotOwner.selector);
        vault.ping();
    }

    function testReleaseRevertsBeforePeriod() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 29 days);
        // expectRevert FIRST: vm.prank only covers the next call, and
        // expectRevert is itself a call, so prank must come after it.
        vm.expectRevert(
            abi.encodeWithSelector(
                DeadMansVault.NotInactiveYet.selector,
                vault.lastActive(),
                block.timestamp,
                vault.inactivityPeriod()
            )
        );
        vm.prank(PROXY);
        vault.releaseToHeir(REACTIVE);
    }

    function testReleaseRevertsForNonProxy() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 31 days);
        // Called by the test contract itself, not the callback proxy.
        vm.expectRevert();
        vault.releaseToHeir(REACTIVE);
    }

    function testReleaseRevertsForWrongReactiveSender() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 31 days);
        // The proxy is right, but the injected sender is not our switch.
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector,
                address(0xDEAD),
                REACTIVE
            )
        );
        vm.prank(PROXY);
        vault.releaseToHeir(address(0xDEAD));
    }

    function testReleaseSucceedsAfterPeriod() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 31 days);
        assertTrue(vault.isInactive());

        uint256 heirBefore = heir.balance;
        vm.prank(PROXY);
        vault.releaseToHeir(REACTIVE);

        assertTrue(vault.released());
        assertEq(address(vault).balance, 0);
        assertEq(heir.balance, heirBefore + 1 ether);
    }

    function testReleaseOnlyOnce() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 31 days);
        vm.prank(PROXY);
        vault.releaseToHeir(REACTIVE);

        vm.prank(PROXY);
        vm.expectRevert(DeadMansVault.AlreadyReleased.selector);
        vault.releaseToHeir(REACTIVE);
    }

    function testPingAfterReleaseReverts() public {
        vm.prank(owner);
        vault.deposit{ value: 1 ether }();
        vm.warp(block.timestamp + 31 days);
        vm.prank(PROXY);
        vault.releaseToHeir(REACTIVE);

        vm.prank(owner);
        vm.expectRevert(DeadMansVault.AlreadyReleased.selector);
        vault.ping();
    }

    function testSetHeirAndPeriod() public {
        address newHeir = makeAddr("newHeir");
        vm.prank(owner);
        vault.setHeir(newHeir);
        assertEq(vault.heir(), newHeir);

        vm.prank(owner);
        vault.setInactivityPeriod(60 days);
        assertEq(vault.inactivityPeriod(), 60 days);
    }
}
