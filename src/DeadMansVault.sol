// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title Dead Man's Switch Vault (destination chain: Base Sepolia)
/// @notice Holds the owner's ETH. While the owner is alive they call ping()
/// (or just deposit) to prove activity. If the owner goes quiet for the whole
/// inactivity period, the Reactive contract on Lasna testnet asks this vault
/// — through Reactive's official callback proxy — to send everything to the
/// heir. Only the proxy, carrying the authorized reactive contract's address,
/// can trigger the release. The vault itself re-checks the timestamps, so a
/// mistaken or stale trigger can never move funds early.
/// @dev Follows the Callback Contracts pattern from dev.reactive.network:
/// inherit AbstractCallback, guard the callback with both onlyServiceProvider
/// (is the caller the proxy?) and onlyCallbackSender (did the call really
/// come from our reactive contract?). The first payload argument is always
/// the reactive contract's address, injected by the proxy.
contract DeadMansVault is AbstractCallback {
    address public immutable owner;
    address public heir;
    /// @notice Inactivity period in seconds. Set from whole days at deploy.
    uint256 public inactivityPeriod;
    /// @notice block.timestamp of the last ping or deposit. TIMESTAMPS, not
    /// block numbers — Base Sepolia block times are not fixed, so only wall
    /// clock time measures "N days of silence" fairly.
    uint256 public lastActive;
    bool public released;

    event Deposited(address indexed from, uint256 amount, uint256 lastActive);
    event ActivityPinged(uint256 lastActive);
    event HeirSet(address indexed heir);
    event InactivityPeriodSet(uint256 inactivityPeriod);
    event Released(address indexed heir, uint256 amount, uint256 releasedAt);

    error NotOwner();
    error AlreadyReleased();
    error NotInactiveYet(uint256 lastActive, uint256 now_, uint256 inactivityPeriod);
    error ZeroAddress();
    error ZeroPeriod();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param callbackProxy_ The Reactive callback proxy on this chain
    /// (Base Sepolia: 0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param callbackSender_ The DeadMansSwitch reactive contract on Lasna.
    /// @param owner_ The person whose funds these are.
    /// @param heir_ Who receives the funds if the owner goes quiet.
    /// @param inactivityDays_ Whole days of silence before release is allowed.
    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        address owner_,
        address heir_,
        uint256 inactivityDays_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        if (owner_ == address(0) || heir_ == address(0)) revert ZeroAddress();
        if (inactivityDays_ == 0) revert ZeroPeriod();
        owner = owner_;
        heir = heir_;
        inactivityPeriod = inactivityDays_ * 1 days;
        lastActive = block.timestamp;
    }

    /// @notice Plain ETH transfers count as activity too.
    receive() external payable override {
        if (released) revert AlreadyReleased();
        lastActive = block.timestamp;
        emit Deposited(msg.sender, msg.value, lastActive);
    }

    /// @notice Deposit ETH into the vault. Counts as activity.
    function deposit() external payable {
        if (released) revert AlreadyReleased();
        lastActive = block.timestamp;
        emit Deposited(msg.sender, msg.value, lastActive);
    }

    /// @notice "I'm alive." Resets the inactivity clock to now.
    function ping() external onlyOwner {
        if (released) revert AlreadyReleased();
        lastActive = block.timestamp;
        emit ActivityPinged(lastActive);
    }

    function setHeir(address heir_) external onlyOwner {
        if (released) revert AlreadyReleased();
        if (heir_ == address(0)) revert ZeroAddress();
        heir = heir_;
        emit HeirSet(heir_);
    }

    /// @notice Change the inactivity period (seconds). The owner can only
    /// do this before a release. The matching period on the reactive
    /// contract must be updated to the same value.
    function setInactivityPeriod(uint256 inactivityPeriod_) external onlyOwner {
        if (released) revert AlreadyReleased();
        if (inactivityPeriod_ == 0) revert ZeroPeriod();
        inactivityPeriod = inactivityPeriod_;
        emit InactivityPeriodSet(inactivityPeriod_);
    }

    /// @notice True once the owner has been silent for the full period.
    function isInactive() public view returns (bool) {
        return block.timestamp - lastActive >= inactivityPeriod;
    }

    /// @notice Sends the whole balance to the heir. Callable ONLY through
    /// the Reactive callback proxy, and only when the timestamps prove the
    /// owner has been silent for the full inactivity period.
    /// @param reactive_ Injected by the proxy: the reactive contract that
    /// requested this callback. Must be our authorized DeadMansSwitch.
    function releaseToHeir(address reactive_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (released) revert AlreadyReleased();
        if (!isInactive()) {
            revert NotInactiveYet(lastActive, block.timestamp, inactivityPeriod);
        }
        released = true;
        uint256 amount = address(this).balance;
        emit Released(heir, amount, block.timestamp);
        (bool ok, ) = payable(heir).call{ value: amount }("");
        require(ok, "heir transfer failed");
    }

    /// @notice Settles outstanding callback debt from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }
}
