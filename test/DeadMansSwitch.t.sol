// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { DeadMansSwitch } from "../src/DeadMansSwitch.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Stand-in for Reactive's system contract at its real address
/// (0x8888888888888888888888888888888888888888). It records every callback
/// the switch requests as an EVENT, so the tests can prove the trigger logic
/// without a live network. Deployed with vm.etch in setUp().
/// @dev Why events, not state: vm.etch copies the mock's CODE to the system
/// address, but the code then writes to the SYSTEM address's storage, not
/// the mock's. Events land in the transaction receipt either way, so they
/// are the reliable observation channel.
contract MockSystem {
    event CallbackRequested(
        uint256 chainId,
        address recipient,
        uint64 gasLimit,
        bytes payload
    );

    function subscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {}

    function unsubscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {}

    function requestCallbackV_1_0(
        ISystemContract.CallbackConfiguration_V_1_0 memory config_
    ) external {
        emit CallbackRequested(
            config_.chainId,
            config_.recipient,
            config_.gasLimit,
            config_.payload
        );
    }
}

/// @notice Local proof of the reactive trigger logic. The switch is tested
/// against the mock system contract, with vm.warp standing in for days
/// passing on the clock.
contract DeadMansSwitchTest is Test {
    address internal constant SYSTEM_ADDR =
        0x8888888888888888888888888888888888888888;

    bytes32 internal constant CALLBACK_REQUESTED_TOPIC =
        keccak256("CallbackRequested(uint256,address,uint64,bytes)");

    address internal vault = address(0xCAFE);
    uint256 internal constant PERIOD_DAYS = 30;

    MockSystem internal mock;
    DeadMansSwitch internal sw;

    function setUp() public {
        mock = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        sw = new DeadMansSwitch(
            vault,
            PERIOD_DAYS,
            // Cron1000 topic from the docs (same value as
            // DeadMansSwitch.CRON1000_TOPIC_0; the constant is read back
            // from the deployed instance in the tests below).
            0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4
        );
    }

    /// @dev Builds a LogRecord the way the system contract would deliver it.
    function _log(
        uint256 chainId_,
        address contract_,
        uint256 topic0_
    ) internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: chainId_,
                contractAddress: contract_,
                topic0: topic0_,
                topic1: 0,
                topic2: 0,
                topic3: 0,
                data: "",
                blockNumber: block.number,
                opCode: 1,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function _cronLog() internal view returns (IReactive.LogRecord memory) {
        return _log(block.chainid, address(0), sw.cronTopic());
    }

    function _vaultLog(
        uint256 topic0_
    ) internal view returns (IReactive.LogRecord memory) {
        return _log(sw.BASE_SEPOLIA_CHAIN_ID(), vault, topic0_);
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR);
        sw.react(log_);
    }

    /// @dev Counts CallbackRequested events emitted since vm.recordLogs().
    function _callbackRequests()
        internal
        view
        returns (Vm.Log[] memory requests)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == CALLBACK_REQUESTED_TOPIC) count++;
        }
        requests = new Vm.Log[](count);
        uint256 j;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == CALLBACK_REQUESTED_TOPIC) {
                requests[j++] = logs[i];
            }
        }
    }

    function testReactRevertsForNonSystem() public {
        // Build the log BEFORE expectRevert: _cronLog() itself makes an
        // external call (sw.cronTopic()), which would consume the expectation.
        IReactive.LogRecord memory log_ = _cronLog();
        vm.expectRevert();
        sw.react(log_);
    }

    function testVaultEventUpdatesLastActivity() public {
        uint256 t = block.timestamp + 5 days;
        vm.warp(t);
        _react(_vaultLog(uint256(keccak256("ActivityPinged(uint256)"))));
        assertEq(sw.lastActivity(), t);
    }

    function testCronBeforePeriodRequestsNothing() public {
        vm.recordLogs();
        vm.warp(block.timestamp + 29 days);
        _react(_cronLog());
        assertEq(_callbackRequests().length, 0);
        assertFalse(sw.released());
    }

    function testCronAfterPeriodRequestsCallback() public {
        vm.recordLogs();
        vm.warp(block.timestamp + 31 days);
        _react(_cronLog());
        Vm.Log[] memory requests = _callbackRequests();
        assertEq(requests.length, 1);
        (uint256 chainId, address recipient, , bytes memory payload) = abi
            .decode(
                requests[0].data,
                (uint256, address, uint64, bytes)
            );
        assertEq(chainId, 84532);
        assertEq(recipient, vault);
        // Payload must call releaseToHeir(address) with the placeholder.
        bytes4 selector = bytes4(payload);
        assertEq(selector, bytes4(keccak256("releaseToHeir(address)")));
        // Not confirmed yet: the vault's Released event hasn't arrived.
        assertFalse(sw.released());
    }

    function testReleasedEventConfirmsAndStopsRetries() public {
        vm.recordLogs();
        vm.warp(block.timestamp + 31 days);
        _react(_cronLog());
        // The vault's Released event arrives back on Lasna.
        _react(_vaultLog(uint256(sw.RELEASED_TOPIC_0())));
        assertTrue(sw.released());

        // A further tick must not request again: exactly one callback
        // request in total across the whole test.
        vm.warp(block.timestamp + 1 days);
        _react(_cronLog());
        assertEq(_callbackRequests().length, 1);
    }

    function testLateActivityCancelsTrigger() public {
        // 31 days pass, but the owner pings just before the tick.
        vm.recordLogs();
        vm.warp(block.timestamp + 31 days);
        _react(_vaultLog(uint256(keccak256("ActivityPinged(uint256)"))));
        _react(_cronLog());
        assertEq(_callbackRequests().length, 0);
        assertFalse(sw.released());
    }

    function testSetVaultOnlyOwner() public {
        // The test contract deployed the switch, so IT is the owner.
        // A stranger must be rejected.
        vm.expectRevert(DeadMansSwitch.NotOwner.selector);
        vm.prank(address(0x1234));
        sw.setVault(address(0xBEEF));
    }
}
