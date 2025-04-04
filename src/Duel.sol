// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Duel
/// @notice A duel between two players resolved by a third party resolver.
contract Duel {
    struct Game {
        address player1;
        address player2;
        address resolver;
        uint256 amount;
        uint256 fee;
        address token;
        bool settled;
    }

    /// @notice Join a game or create a new one
    /// @param resolver The backend signer that will resolve the game
    /// @param token The ERC20 token to be used
    /// @param amount Amount of tokens to bet
    /// @param fee Fee taken by the protocol
    function join(address resolver, address token, uint256 amount, uint256 fee) public {}


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
