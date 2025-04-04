// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./helpers/ByteHasher.sol";

contract Daily {
    using ByteHasher for bytes;

    /// @notice World ID instance that will verify the proofs
    IWorldID internal immutable worldId;

    /// @notice DLY token contract
    IERC20 public immutable dlyToken;

    /// @notice Daily claim amount (100 DLY = 100 * 1e18)
    uint256 public constant DAILY_AMOUNT = 100 ether;

    /// @notice The World ID group ID (1)
    uint256 internal immutable groupId = 1;

    /// @notice The World ID Action ID
    uint256 internal immutable actionId;

    /// @notice Map to track claims for each day for each user
    mapping(address => uint256) public lastClaimDay;

    /// @notice Map to track if an address has been nullified
    mapping(uint256 => bool) internal nullifierHashes;

    /// @notice Emitted when a user claims their daily tokens
    event DailyClaimed(address indexed user, uint256 amount, uint256 day);

    error InvalidNullifier();
    error AlreadyClaimedToday();
    error InsufficientContractBalance();

    constructor(IWorldID _worldId, address _dlyToken, string memory _actionId) {
        worldId = _worldId;
        dlyToken = IERC20(_dlyToken);
        actionId = abi.encodePacked(_actionId).hashToField();
    }

    /// @notice Get the current day number (timestamp / 1 day)
    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function claimDaily(address receiver, uint256 root, uint256 nullifierHash, uint256[8] calldata proof) public {
        // Check contract has enough balance
        require(dlyToken.balanceOf(address(this)) >= DAILY_AMOUNT, "Insufficient contract balance");

        uint256 currentDay = getCurrentDay();

        // Check if user has already claimed today
        require(lastClaimDay[receiver] < currentDay, "Already claimed today");

        // Verify the World ID proof
        if (nullifierHashes[nullifierHash]) revert InvalidNullifier();
        worldId.verifyProof(root, groupId, abi.encodePacked(receiver).hashToField(), nullifierHash, actionId, proof);

        // Mark this nullifier as used
        nullifierHashes[nullifierHash] = true;

        // Update last claim day
        lastClaimDay[receiver] = currentDay;

        // Transfer 100 DLY tokens to the receiver
        require(dlyToken.transfer(receiver, DAILY_AMOUNT), "Transfer failed");

        // Emit claim event
        emit DailyClaimed(receiver, DAILY_AMOUNT, currentDay);
    }

    function canClaimToday(address user) public view returns (bool) {
        return lastClaimDay[user] < getCurrentDay();
    }

    function timeUntilNextClaim() public view returns (uint256) {
        // Calculate time until next day starts
        uint256 nextDay = (getCurrentDay() + 1) * 1 days;
        return nextDay - block.timestamp;
    }
}
