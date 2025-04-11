// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./helpers/ByteHasher.sol";

/// @title Daily Token Distribution with World ID Verification
/// @notice A contract that distributes daily tokens to unique humans verified by World ID
contract Daily {
    using ByteHasher for bytes;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims their daily tokens
    event DailyClaimed(address indexed user, uint256 amount, uint256 day, uint256 streak);
    /// @notice Emitted when a user successfully verifies their identity
    event IdentityVerified(address indexed user, uint256 nullifierHash);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to reuse a nullifier
    error DuplicateNullifier(uint256 nullifierHash);
    /// @notice Thrown when user has already claimed today
    error AlreadyClaimed(uint256 day);
    /// @notice Thrown when contract doesn't have enough tokens
    error InsufficientBalance(uint256 required, uint256 available);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice World ID instance that will verify the proofs
    IWorldID internal immutable worldId;

    /// @notice DLY token contract used for distributions
    IERC20 public immutable dlyToken;

    /// @notice Base daily claim amount (1 DLY = 1 * 1e18)
    uint256 public constant BASE_AMOUNT = 1 ether;

    /// @notice Maximum streak reward (20 DLY = 20 * 1e18)
    uint256 public constant MAX_STREAK = 20;

    /// @notice The World ID group ID (always 1)
    uint256 internal immutable groupId = 1;

    /// @notice The contract's external nullifier hash
    uint256 internal immutable externalNullifier;

    /// @notice Map to track claims for each day for each user
    mapping(address => uint256) public lastClaimDay;

    /// @notice Map to track current streak for each user
    mapping(address => uint256) public currentStreak;

    /// @notice Map to track if a nullifier hash has been used
    mapping(uint256 => bool) internal nullifierHashes;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with World ID and token settings
    /// @param _worldId The WorldID router that will verify the proofs
    /// @param _dlyToken The ERC20 token used for daily distributions
    /// @param _appId The World ID app ID
    /// @param _actionId The World ID action ID
    constructor(IWorldID _worldId, address _dlyToken, string memory _appId, string memory _actionId) {
        worldId = _worldId;
        dlyToken = IERC20(_dlyToken);
        externalNullifier = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
    }

    /*//////////////////////////////////////////////////////////////
                              CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claims daily tokens after verifying World ID proof
    /// @param receiver The address receiving the tokens
    /// @param root The root of the Merkle tree
    /// @param nullifierHash The nullifier hash for this proof
    /// @param proof The zero-knowledge proof that demonstrates the claimer is registered with World ID
    function claimDaily(address receiver, uint256 root, uint256 nullifierHash, uint256[8] calldata proof) public {
        // Verify World ID proof
        verifyIdentity(receiver, root, nullifierHash, proof);
        
        uint256 currentDay = getCurrentDay();
        uint256 lastClaim = lastClaimDay[receiver];

        // Check if already claimed today
        if (lastClaim >= currentDay) {
            revert AlreadyClaimed(currentDay);
        }

        uint256 streak;
        if (lastClaim < currentDay - 1) {
            // Reset streak if missed a day or is the first time claiming
            streak = 1;
        } else {
            // Increment streak if claimed the day before
            streak = currentStreak[receiver] + 1;
        }
        currentStreak[receiver] = streak;

        // Calculate reward amount (streak) * 1 DLY, capped at MAX_STREAK
        uint256 rewardAmount = streak > MAX_STREAK ? MAX_STREAK * BASE_AMOUNT : streak * BASE_AMOUNT;

        // Update state
        lastClaimDay[receiver] = currentDay;

        // Transfer tokens
        dlyToken.safeTransfer(receiver, rewardAmount);

        emit DailyClaimed(receiver, rewardAmount, currentDay, streak);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies the World ID proof
    /// @param signal The user's address
    /// @param root The root of the Merkle tree
    /// @param nullifierHash The nullifier hash for this proof
    /// @param proof The zero-knowledge proof
    function verifyIdentity(address signal, uint256 root, uint256 nullifierHash, uint256[8] calldata proof) internal {
        // Verify nullifier is not used
        if (nullifierHashes[nullifierHash]) {
            revert DuplicateNullifier(nullifierHash);
        }

        // Verify the provided proof
        worldId.verifyProof(
            root, groupId, abi.encodePacked(signal).hashToField(), nullifierHash, externalNullifier, proof
        );

        // Mark nullifier as used
        nullifierHashes[nullifierHash] = true;

        emit IdentityVerified(signal, nullifierHash);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current day number (timestamp / 1 day)
    /// @return The current day number
    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice Check if an address can claim tokens today
    /// @param user The address to check
    /// @return Whether the user can claim today
    function canClaimToday(address user) public view returns (bool) {
        return lastClaimDay[user] < getCurrentDay();
    }

    /// @notice Get time remaining until next claim is available
    /// @return Time in seconds until next claim
    function timeUntilNextClaim() public view returns (uint256) {
        uint256 nextDay = (getCurrentDay() + 1) * 1 days;
        return nextDay - block.timestamp;
    }
}
