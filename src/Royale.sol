// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

/// @title Royale
/// @notice Battle Royale between N players.
contract Royale is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Game {
        uint128 players;
        uint128 capacity;
        address resolver;
        address creator;
        uint256 amount;
        address token;
        bool settled;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev lobbyId is created by keccak256(abi.encodePacked(resolver, token, amount, capacity))
    mapping(bytes32 lobbyId => uint256 count) public lobby;

    /// @dev playerLobbyKey is created by keccak256(abi.encodePacked(player, lobbyId))
    mapping(bytes32 playerLobbyKey => uint256 count) public countOf;

    /// @dev gameId is created by keccak256(abi.encodePacked(lobbyId, count))
    mapping(bytes32 gameId => Game game) public games;

    /// @dev Maps hash of player address and gameId to a boolean indicating if they joined
    /// @dev playerGameKey is created by keccak256(abi.encodePacked(player, gameId))
    mapping(bytes32 playerGameKey => bool joined) public joined;

    /// @dev The Permit2 contract address
    ISignatureTransfer public immutable permit2;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Created(bytes32 gameId, address player, address resolver, address token, uint256 amount, uint128 capacity);
    event Joined(bytes32 gameId, address creator, address player, uint128 players);
    event Resolved(bytes32 gameId, address[] winners, uint256[] amounts);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidResolver();
    error AlreadySettled();
    error InvalidWinner();
    error InvalidSignature();
    error PlayerAlreadyJoined();
    error InvalidPayouts();
    error InvalidCapacity();
    error InvalidPermitTransfer();
    error NotStarted();
    error NotOldestOpenGame();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @param _permit2 0x000000000022D473030F116dDEE9F6B43aC78BA3
    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                               GAME LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Join a game or create a new one using standard ERC20 approval
    function join(address resolver, address token, uint256 amount, uint128 capacity)
        public
        nonReentrant
        returns (bytes32)
    {
        // Safe transfer tokens from player to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        return _join(resolver, token, amount, capacity);
    }

    /// @notice Join a game or create a new one using Permit2
    function joinWithPermit(
        address resolver,
        address token,
        uint128 capacity,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) public nonReentrant returns (bytes32) {
        // Ensure the tokens are sent to this contract
        if (transferDetails.to != address(this)) revert InvalidPermitTransfer();
        // Transfer tokens using Permit2's SignatureTransfer
        permit2.permitTransferFrom(permit, transferDetails, msg.sender, signature);
        // Use the amount from the permit details
        return _join(resolver, token, transferDetails.requestedAmount, capacity);
    }

    /// @notice Internal join function
    /// @param resolver The backend signer that will resolve the game
    /// @param token The ERC20 token to be used
    /// @param amount Amount of tokens to bet
    /// @param capacity Maximum number of players in the game
    function _join(address resolver, address token, uint256 amount, uint128 capacity) internal returns (bytes32) {
        if (resolver == address(0)) revert InvalidResolver();
        if (capacity < 2) revert InvalidCapacity();

        // Key for finding matching games
        bytes32 lobbyId = keccak256(abi.encodePacked(resolver, token, amount, capacity));
        uint256 count = lobby[lobbyId];

        bytes32 playerLobbyKey = keccak256(abi.encodePacked(msg.sender, lobbyId));
        uint256 lastJoinedCount = countOf[playerLobbyKey];

        uint256 nextCount = count > lastJoinedCount ? count + 1 : lastJoinedCount + 1;

        // Get the next game
        bytes32 nextGameId = keccak256(abi.encodePacked(lobbyId, nextCount));
        Game storage game = games[nextGameId];
        bytes32 playerGameKey = keccak256(abi.encodePacked(msg.sender, nextGameId));

        joined[playerGameKey] = true;
        countOf[playerLobbyKey] = nextCount;

        // Check if we need to create a new game
        if (game.players == 0) {
            // Create new game
            games[nextGameId] = Game({
                players: 1,
                capacity: capacity,
                resolver: resolver,
                creator: msg.sender,
                amount: amount,
                token: token,
                settled: false
            });

            emit Created(nextGameId, msg.sender, resolver, token, amount, capacity);
        } else {
            // Join existing game
            game.players++;

            if (game.players == game.capacity) {
                lobby[lobbyId]++;
            }

            emit Joined(nextGameId, game.creator, msg.sender, game.players);
        }

        return nextGameId;
    }

    /// @notice Internal function to verify resolver signature
    /// @param signer The address that should have signed the message
    /// @param messageHash The hash of the message to verify
    /// @param signature The signature to verify
    function _verifySignature(address signer, bytes32 messageHash, bytes calldata signature) internal pure {
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        // Extract signature components
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        // Verify signature is from signer
        if (ecrecover(signedHash, v, r, s) != signer) revert InvalidSignature();
    }

    /// @notice Resolve a game with multiple winners and their payouts
    /// @param gameId The id of the game
    /// @param winners List of winners
    /// @param amounts Amount to pay each winner
    /// @param signature The signature of the resolver
    function resolve(bytes32 gameId, address[] calldata winners, uint256[] calldata amounts, bytes calldata signature)
        public
        nonReentrant
    {
        Game storage game = games[gameId];

        bytes32 lobbyId = keccak256(abi.encodePacked(game.resolver, game.token, game.amount, game.capacity));
        uint256 count = lobby[lobbyId];

        // Verify game state
        if (game.settled) revert AlreadySettled();
        if (game.players == 0) revert NotStarted();
        // Resolving games that are not full should only be possible for the oldest open game
        if (game.players < game.capacity) {
            bytes32 oldestOpenGameId = keccak256(abi.encodePacked(lobbyId, count + 1));
            if (oldestOpenGameId != gameId) revert NotOldestOpenGame();
        }

        // Verify winners and amounts
        if (winners.length != amounts.length) revert InvalidPayouts();
        uint256 totalPayout;
        for (uint256 i = 0; i < winners.length; i++) {
            // Verify winner is a player
            bytes32 playerGameKey = keccak256(abi.encodePacked(winners[i], gameId));
            if (!joined[playerGameKey]) revert InvalidWinner();
            totalPayout += amounts[i];
        }

        // Verify total payout doesn't exceed total pot
        uint256 totalPot = game.amount * game.players;
        if (totalPayout > totalPot) revert InvalidPayouts();

        // Verify resolver signature
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        _verifySignature(game.resolver, messageHash, signature);

        // Mark game as settled
        game.settled = true;

        if (game.players < game.capacity) {
            lobby[lobbyId]++;
        }

        // Distribute payouts
        IERC20 token = IERC20(game.token);
        for (uint256 i = 0; i < winners.length; i++) {
            token.safeTransfer(winners[i], amounts[i]);
        }

        // Send remaining tokens to resolver
        uint256 remaining = totalPot - totalPayout;
        if (remaining > 0) {
            token.safeTransfer(game.resolver, remaining);
        }

        emit Resolved(gameId, winners, amounts);
    }

    /// @notice Check if a player is in a game
    /// @param gameId The id of the game
    /// @param player The address of the player to check
    function isPlayerInGame(bytes32 gameId, address player) public view returns (bool) {
        bytes32 playerGameKey = keccak256(abi.encodePacked(player, gameId));
        return joined[playerGameKey];
    }

    /// @notice Get the number of players in the current game for a lobby
    /// @notice Specifically, this returns the player count of the oldest open game.
    /// @param resolver The resolver of the lobby
    /// @param token The token of the lobby
    /// @param amount The amount of the lobby
    /// @param capacity The capacity of the lobby
    function getPlayerCount(address resolver, address token, uint256 amount, uint128 capacity)
        public
        view
        returns (uint128)
    {
        bytes32 lobbyId = keccak256(abi.encodePacked(resolver, token, amount, capacity));
        uint256 oldestOpenGameIndex = lobby[lobbyId] + 1;
        bytes32 gameId = keccak256(abi.encodePacked(lobbyId, oldestOpenGameIndex));
        // Returns 0 if the game doesn't exist or hasn't been created yet
        return games[gameId].players;
    }
}
