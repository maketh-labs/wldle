// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Duel
/// @notice A duel between two players resolved by a third party resolver.
contract Duel {
    using SafeERC20 for IERC20;

    struct Game {
        address player1;
        address player2;
        address resolver;
        uint256 amount;
        uint256 fee;
        address token;
        bool settled;
    }

    uint256 public currentGameId;
    mapping(bytes32 gameKey => uint256 gameId) public lobby;
    mapping(uint256 gameId => Game game) public games;

    event Created(uint256 gameId, address player1, address resolver, address token, uint256 amount, uint256 fee);
    event Joined(uint256 gameId, address player2);

    error InvalidResolver();
    error InsufficientValue();

    /// @notice Join a game or create a new one
    /// @param resolver The backend signer that will resolve the game
    /// @param token The ERC20 token to be used
    /// @param amount Amount of tokens to bet
    /// @param fee Fee taken by the protocol
    function join(address resolver, address token, uint256 amount, uint256 fee) public returns (uint256) {
        if (resolver == address(0)) revert InvalidResolver();
        if (amount <= fee) revert InsufficientValue();

        // Safe transfer tokens from player to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Key for finding matching games
        bytes32 gameKey = keccak256(abi.encodePacked(resolver, token, amount, fee));
        uint256 existingGameId = lobby[gameKey];

        // If there's an available game, join it
        Game storage game = games[existingGameId];
        if (game.player1 != address(0) && game.player2 == address(0)) {
            game.player2 = msg.sender;
            emit Joined(existingGameId, msg.sender);
            return existingGameId;
        }

        // Create new game with incremented ID
        uint256 gameId = ++currentGameId;
        lobby[gameKey] = gameId;

        // Create a new game
        games[gameId] = Game({
            player1: msg.sender,
            player2: address(0),
            resolver: resolver,
            amount: amount,
            fee: fee,
            token: token,
            settled: false
        });

        emit Created(gameId, msg.sender, resolver, token, amount, fee);
        return gameId;
    }

    /// @notice Resolve a game with the winner
    /// @param gameId The id of the game
    /// @param winner The winner of the game, address(0) if draw
    /// @param signature The signature of the resolver
    function resolve(uint256 gameId, address winner, bytes calldata signature) public {}

    /// @notice Cancel a game
    /// @param gameId The id of the game
    /// @param signature The signature from the resolver permitting the cancellation
    function cancel(uint256 gameId, bytes calldata signature) public {}

    /// @notice Cancel a game directly by the resolver
    /// @param gameId The id of the game
    function forceCancel(uint256 gameId) public {}
}
