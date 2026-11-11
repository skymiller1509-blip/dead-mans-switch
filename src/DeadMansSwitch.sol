// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title Dead Man's Switch (reactive contract, Lasna testnet)
/// @notice Watches one vault on Base Sepolia. Two subscriptions feed the
/// same react():
///  - a CRON tick from Reactive's own clock (the legacy system contract
///    emits Cron events at fixed block intervals), and
///  - every event from the vault contract (a ping or a deposit proves the
///    owner is alive).
/// On each tick the contract checks, in plain timestamps, whether the owner
/// has been silent for the full inactivity period. If so, it asks the system
/// contract to deliver a callback to the vault's releaseToHeir(). The vault
/// re-checks the timestamps itself before moving anything, so a mistaken
/// trigger is harmless. The switch only considers the job done once it sees
/// the vault's Released event, so a failed callback is retried on the next
/// tick instead of being forgotten.
/// @dev Follows the Reactive Contracts + CRON patterns from
/// dev.reactive.network (Omni): inherit AbstractReactive, guard react()
/// with onlySystem, subscribe through SYSTEM, request callbacks with
/// SYSTEM.requestCallbackV_1_0. The callback payload's first argument is
/// always an address placeholder (address(0)); the proxy overwrites it
/// with this contract's address so the vault can authenticate the sender.
contract DeadMansSwitch is AbstractReactive {
    /// @notice The legacy system contract that emits the Cron events.
    /// (dev.reactive.network/reactive-contracts, "Subscribing To CRON Events")
    address internal constant LEGACY_SYSTEM_ADDR =
        0x0000000000000000000000000000000000fffFfF;

    /// @notice CRON event topic0 values from the official docs.
    /// Cron100 ticks about every 100 blocks (~2 minutes on Lasna);
    /// Cron1000 about every 1000 blocks (~17 minutes);
    /// Cron10000 about every 10,000 blocks (~3 hours).
    uint256 public constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint256 public constant CRON1000_TOPIC_0 =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;
    uint256 public constant CRON10000_TOPIC_0 =
        0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56;

    /// @notice Topic0 of the vault's Released(address,uint256,uint256) event.
    bytes32 public constant RELEASED_TOPIC_0 =
        keccak256("Released(address,uint256,uint256)");

    /// @notice Base Sepolia chain ID (dev.reactive.network/origins-and-destinations).
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public owner;
    address public vault;
    /// @notice Inactivity period in seconds. Must match the vault's period.
    uint256 public inactivityPeriod;
    uint256 public cronTopic;
    /// @notice Lasna block.timestamp of the last vault event observed.
    /// Lasna and Base Sepolia timestamps are both Unix wall-clock time,
    /// so a few seconds of drift between chains is meaningless at the
    /// scale of days of silence.
    uint256 public lastActivity;
    /// @notice True once the vault's Released event has been observed.
    bool public released;

    event ActivityObserved(uint256 indexed topic0, uint256 at);
    event CronChecked(uint256 at, uint256 inactiveFor, bool triggered);
    event ReleaseRequested(address indexed vault, uint256 at);
    event ReleaseConfirmed(address indexed vault, uint256 at);
    event VaultSet(address indexed vault);
    event InactivityPeriodSet(uint256 inactivityPeriod);

    error NotOwner();
    error VaultNotSet();
    error ZeroAddress();
    error ZeroPeriod();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param vault_ The DeadMansVault on Base Sepolia (address(0) is
    /// allowed here so the reactive contract can be deployed first; set
    /// the vault afterwards with setVault()).
    /// @param inactivityDays_ Whole days of silence before release.
    /// @param cronTopic_ Which CRON tick to listen to (see constants above).
    constructor(address vault_, uint256 inactivityDays_, uint256 cronTopic_)
        payable
    {
        if (inactivityDays_ == 0) revert ZeroPeriod();
        owner = msg.sender;
        vault = vault_;
        inactivityPeriod = inactivityDays_ * 1 days;
        cronTopic = cronTopic_;
        // Deploying counts as activity: the clock starts now.
        lastActivity = block.timestamp;
        _subscribeToCron();
        if (vault_ != address(0)) {
            _subscribeToVault();
        }
    }

    function _subscribeToCron() internal {
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            cronTopic,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    function _subscribeToVault() internal {
        // Every event from this one contract (topic0 left open).
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            vault,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Point the switch at the vault (deploy order: reactive first,
    /// then vault, then setVault). Unsubscribes from the old vault first.
    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        if (vault != address(0)) {
            SYSTEM.unsubscribe(
                BASE_SEPOLIA_CHAIN_ID,
                vault,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
        vault = vault_;
        _subscribeToVault();
        emit VaultSet(vault_);
    }

    /// @notice Change the inactivity period (seconds). Keep the vault's
    /// period set to the same value.
    function setInactivityPeriod(uint256 inactivityPeriod_) external onlyOwner {
        if (inactivityPeriod_ == 0) revert ZeroPeriod();
        inactivityPeriod = inactivityPeriod_;
        emit InactivityPeriodSet(inactivityPeriod_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.chainId == block.chainid && log_.topic0 == cronTopic) {
            _onCronTick();
        } else if (
            log_.chainId == BASE_SEPOLIA_CHAIN_ID &&
            log_.contractAddress == vault
        ) {
            // Any event from the vault proves the owner is alive.
            lastActivity = block.timestamp;
            emit ActivityObserved(log_.topic0, block.timestamp);
            if (log_.topic0 == uint256(RELEASED_TOPIC_0)) {
                released = true;
                emit ReleaseConfirmed(vault, block.timestamp);
            }
        }
        // Anything else falls through silently. Reverting as a filter
        // would still cost gas, per the docs.
    }

    function _onCronTick() internal {
        uint256 inactiveFor = block.timestamp - lastActivity;
        bool trigger = !released &&
            vault != address(0) &&
            inactiveFor >= inactivityPeriod;
        emit CronChecked(block.timestamp, inactiveFor, trigger);
        if (!trigger) {
            return;
        }
        bytes memory payload = abi.encodeWithSignature(
            "releaseToHeir(address)",
            address(0) // placeholder: the proxy injects this contract's address
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        emit ReleaseRequested(vault, block.timestamp);
    }

    /// @notice Settles outstanding debt from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}
