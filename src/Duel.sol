// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Duel
/// @notice A duel between two players resolved by a third party resolver.
contract Duel is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Game {
        address player1;
        address player2;
        address resolver;
        uint256 amount;
        uint256 fee;
        address token;
        bool settled;
    }

    struct Count {
        uint128 created;
        uint128 played;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 lobbyId => Count count) public lobby;
    mapping(bytes32 gameId => Game game) public games;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Created(bytes32 gameId, address player1, address resolver, address token, uint256 amount, uint256 fee);
    event Joined(bytes32 gameId, address player2);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidResolver();
    error InsufficientValue();
    error AlreadySettled();
    error NotStarted();
    error InvalidWinner();
    error InvalidSignature();
    error NotResolver();
    error AlreadyResolved();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                               GAME LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Join a game or create a new one
    /// @param resolver The backend signer that will resolve the game
    /// @param token The ERC20 token to be used
    /// @param amount Amount of tokens to bet
    /// @param fee Fee taken by the protocol
    function join(address resolver, address token, uint256 amount, uint256 fee) public returns (bytes32) {
        if (resolver == address(0)) revert InvalidResolver();
        if (amount <= fee) revert InsufficientValue();

        // Safe transfer tokens from player to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Key for finding matching games
        bytes32 lobbyId = keccak256(abi.encodePacked(resolver, token, amount, fee));
        Count storage count = lobby[lobbyId];

        // Get the next game to be played
        bytes32 nextGameId = keccak256(abi.encodePacked(lobbyId, count.played));
        Game storage game = games[nextGameId];

        // If there's an available game
        if (game.player1 != address(0) && game.player2 == address(0)) {
            // If trying to join own game, create new one instead
            if (game.player1 == msg.sender) {
                bytes32 newGameId = keccak256(abi.encodePacked(lobbyId, count.created));
                count.created++;

                games[newGameId] = Game({
                    player1: msg.sender,
                    player2: address(0),
                    resolver: resolver,
                    amount: amount,
                    fee: fee,
                    token: token,
                    settled: false
                });

                emit Created(newGameId, msg.sender, resolver, token, amount, fee);
                return newGameId;
            }

            // Join existing game
            game.player2 = msg.sender;
            count.played++;
            emit Joined(nextGameId, msg.sender);
            return nextGameId;
        }

        // Create first game or new game after previous one is filled
        bytes32 gameId = keccak256(abi.encodePacked(lobbyId, count.created));
        count.created++;

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
    function resolve(bytes32 gameId, address winner, bytes calldata signature) public {
        Game storage game = games[gameId];

        // Verify game state
        if (game.settled) revert AlreadySettled();
        if (game.player2 == address(0)) revert NotStarted();

        // Verify winner is valid
        if (winner != address(0) && winner != game.player1 && winner != game.player2) revert InvalidWinner();

        // Verify resolver signature
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winner));
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

        // Verify signature is from resolver
        if (ecrecover(signedHash, v, r, s) != game.resolver) revert InvalidSignature();

        // Mark game as settled
        game.settled = true;

        IERC20 token = IERC20(game.token);

        if (winner == address(0)) {
            // Draw - return full amount to both players
            token.safeTransfer(game.player1, game.amount);
            token.safeTransfer(game.player2, game.amount);
        } else {
            // Winner takes prize pool (total amount minus fee)
            token.safeTransfer(winner, game.amount * 2 - game.fee);
            // Transfer fees to protocol owner
            token.safeTransfer(owner(), game.fee);
        }
    }

    /// @notice Cancel a game with resolver signature
    /// @param gameId The id of the game
    /// @param signature The signature from the resolver permitting the cancellation
    function cancel(bytes32 gameId, bytes calldata signature) public {
        Game storage game = games[gameId];

        // Verify game state
        if (game.settled) revert AlreadyResolved();

        // Verify resolver signature for cancellation
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, "CANCEL"));
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

        // Verify signature is from resolver
        if (ecrecover(signedHash, v, r, s) != game.resolver) revert InvalidSignature();

        // Mark game as settled
        game.settled = true;

        // Return tokens to players
        IERC20 token = IERC20(game.token);
        if (game.player1 != address(0)) {
            token.safeTransfer(game.player1, game.amount);
        }
        if (game.player2 != address(0)) {
            token.safeTransfer(game.player2, game.amount);
        }
    }

    /// @notice Cancel a game directly by the resolver
    /// @param gameId The id of the game
    function forceCancel(bytes32 gameId) public {
        Game storage game = games[gameId];

        // Only resolver can force cancel
        if (msg.sender != game.resolver) revert NotResolver();

        // Verify game state
        if (game.settled) revert AlreadyResolved();

        // Mark game as settled
        game.settled = true;

        // Return tokens to players
        IERC20 token = IERC20(game.token);
        if (game.player1 != address(0)) {
            token.safeTransfer(game.player1, game.amount);
        }
        if (game.player2 != address(0)) {
            token.safeTransfer(game.player2, game.amount);
        }
    }
}
