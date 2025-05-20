// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./helpers/ByteHasher.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

/// @title Reward
/// @notice Contract for distributing WORD tokens with multiple claim methods
contract Reward is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ByteHasher for bytes;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensClaimed(address indexed user, uint256 amount, string method);
    event TokensConverted(address indexed user, uint256 dlyAmount, uint256 wordAmount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSignature();
    error InvalidWorldIDProof();
    error InsufficientBalance(uint256 required, uint256 available);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice DLY token contract
    IERC20 public immutable dlyToken;

    /// @notice WORD token contract
    IERC20 public immutable wordToken;

    /// @notice World ID instance for verification
    IWorldID public immutable worldId;

    /// @notice The World ID group ID (always 1)
    uint256 internal immutable groupId = 1;

    /// @notice The contract's external nullifier hash
    uint256 internal immutable externalNullifier;

    /// @notice Map to track used signatures
    mapping(bytes => bool) public usedSignatures;

    /// @notice The Permit2 contract address
    ISignatureTransfer public immutable permit2;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with token and World ID settings
    /// @param _dlyToken The DLY token contract address
    /// @param _wordToken The WORD token contract address
    /// @param _worldId The WorldID router address
    /// @param _appId The World ID app ID
    /// @param _actionId The World ID action ID
    /// @param _permit2 The Permit2 contract address
    constructor(
        address _dlyToken,
        address _wordToken,
        IWorldID _worldId,
        string memory _appId,
        string memory _actionId,
        address _permit2
    ) Ownable(msg.sender) {
        dlyToken = IERC20(_dlyToken);
        wordToken = IERC20(_wordToken);
        worldId = _worldId;
        externalNullifier = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
        permit2 = ISignatureTransfer(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                              CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Migrate DLY tokens to WORD tokens at 1:1 ratio using standard ERC20 approval
    /// @param amount Amount of DLY tokens to migrate
    function migrate(uint256 amount) external nonReentrant {
        // Transfer DLY tokens from user
        dlyToken.safeTransferFrom(msg.sender, address(this), amount);

        // Transfer WORD tokens to user
        wordToken.safeTransfer(msg.sender, amount);

        emit TokensConverted(msg.sender, amount, amount);
    }

    /// @notice Migrate DLY tokens to WORD tokens at 1:1 ratio using Permit2
    /// @param permit The permit data
    /// @param transferDetails The transfer details
    /// @param signature The signature for the permit
    function migrateWithPermit(
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external nonReentrant {
        // Transfer tokens using Permit2's SignatureTransfer
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, signature);

        // Transfer WORD tokens to user
        wordToken.safeTransfer(msg.sender, transferDetails.requestedAmount);

        emit TokensConverted(msg.sender, transferDetails.requestedAmount, transferDetails.requestedAmount);
    }

    /// @notice Claim WORD tokens using owner's signature
    /// @param amount Amount of WORD tokens to claim
    /// @param category The category of claim (can be used as an enum)
    /// @param signature Signature from owner authorizing the claim
    function claim(uint256 amount, uint256 category, bytes calldata signature) external nonReentrant {
        // Check if signature has been used
        if (usedSignatures[signature]) revert InvalidSignature();

        // Create message hash
        bytes32 messageHash = keccak256(abi.encode(msg.sender, amount, category));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Verify signature
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        address signer = ecrecover(signedHash, v, r, s);
        if (signer != owner()) revert InvalidSignature();

        // Mark signature as used
        usedSignatures[signature] = true;

        // Transfer tokens
        wordToken.safeTransfer(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount, "signature");
    }

    /// @notice Claim WORD tokens using owner's signature and World ID verification
    /// @param amount Amount of WORD tokens to claim
    /// @param category The category of claim (can be used as an enum)
    /// @param signature Signature from owner authorizing the claim
    /// @param root The root of the Merkle tree
    /// @param nullifierHash The nullifier hash for this proof
    /// @param proof The zero-knowledge proof
    function claimWithWorldID(
        uint256 amount,
        uint256 category,
        bytes calldata signature,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    ) external nonReentrant {
        // Verify World ID proof
        worldId.verifyProof(
            root, groupId, abi.encodePacked(msg.sender).hashToField(), nullifierHash, externalNullifier, proof
        );

        // Check if signature has been used
        if (usedSignatures[signature]) revert InvalidSignature();

        // Create message hash
        bytes32 messageHash = keccak256(abi.encode(msg.sender, amount, category));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Verify signature
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        address signer = ecrecover(signedHash, v, r, s);
        if (signer != owner()) revert InvalidSignature();

        // Mark signature as used
        usedSignatures[signature] = true;

        // Transfer tokens
        wordToken.safeTransfer(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount, "signature_and_worldid");
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Split signature into r, s, v components
    /// @param signature The signature to split
    function _splitSignature(bytes calldata signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "Invalid signature length");
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
    }
}
