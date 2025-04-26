// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Royale} from "../src/Royale.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

contract RoyaleTest is Test {
    Royale public royale;
    ERC20Mock public token;

    address public player1;
    address public player2;
    address public player3;
    address public resolver;
    uint256 public resolverPrivateKey;

    uint256 public constant AMOUNT = 1000;
    uint128 public constant CAPACITY = 3;

    event Created(bytes32 gameId, address player, address resolver, address token, uint256 amount, uint128 capacity);
    event Joined(bytes32 gameId, address player, uint128 players);
    event Resolved(bytes32 gameId, address[] winners, uint256[] amounts);

    function setUp() public {
        // Deploy contracts
        royale = new Royale(address(0));
        token = new ERC20Mock();

        // Setup accounts
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        (resolver, resolverPrivateKey) = makeAddrAndKey("resolver");

        // Fund players
        token.mint(player1, AMOUNT * 10);
        token.mint(player2, AMOUNT * 10);
        token.mint(player3, AMOUNT * 10);

        // Approve tokens for all players
        vm.prank(player1);
        token.approve(address(royale), type(uint256).max);

        vm.prank(player2);
        token.approve(address(royale), type(uint256).max);

        vm.prank(player3);
        token.approve(address(royale), type(uint256).max);
    }

    function getLobbyId(address resolver, address token, uint256 amount, uint128 capacity)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(resolver, token, amount, capacity));
    }

    function getGameId(bytes32 lobbyId, uint256 count) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lobbyId, count));
    }

    /*//////////////////////////////////////////////////////////////
                                JOIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_join_CreateNewGame() public {
        vm.startPrank(player1);

        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 expectedGameId = getGameId(lobbyId, 1);

        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        assertEq(gameId, expectedGameId, "Game ID should match expected");

        // Check lobby count
        uint256 count = royale.lobby(lobbyId);
        assertEq(count, 1, "Count should be 1");

        (
            uint128 players,
            uint128 capacity,
            address game_resolver,
            uint256 game_amount,
            address game_token,
            bool game_settled
        ) = royale.games(gameId);

        assertEq(players, 1, "Players should be 1");
        assertEq(capacity, CAPACITY, "Capacity should match");
        assertEq(game_resolver, resolver, "Resolver should be set");
        assertEq(game_amount, AMOUNT, "Amount should be set");
        assertEq(game_token, address(token), "Token should be set");
        assertEq(game_settled, false, "Game should not be settled");

        // Verify player joined
        bytes32 playerGameKey = keccak256(abi.encodePacked(player1, gameId));
        assertTrue(royale.joined(playerGameKey), "Player should be marked as joined");

        assertEq(token.balanceOf(address(royale)), AMOUNT, "Contract should hold tokens");
        vm.stopPrank();
    }

    function test_join_JoinExistingGame() public {
        // Create game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Join game
        vm.prank(player2);
        vm.expectEmit(true, true, true, true);
        emit Joined(gameId, player2, 2);
        bytes32 joinedGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        assertEq(joinedGameId, gameId, "Should join existing game");

        (uint128 players,,,,,) = royale.games(gameId);
        assertEq(players, 2, "Players should be 2");

        // Verify both players joined
        bytes32 player1GameKey = keccak256(abi.encodePacked(player1, gameId));
        bytes32 player2GameKey = keccak256(abi.encodePacked(player2, gameId));
        assertTrue(royale.joined(player1GameKey), "Player1 should be marked as joined");
        assertTrue(royale.joined(player2GameKey), "Player2 should be marked as joined");

        assertEq(token.balanceOf(address(royale)), AMOUNT * 2, "Contract should hold both players' tokens");
    }

    function test_join_JoinFullGame() public {
        // Create and fill game
        vm.prank(player1);
        bytes32 firstGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Get lobby ID for next game
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        uint256 count = royale.lobby(lobbyId);
        bytes32 expectedNewGameId = getGameId(lobbyId, count + 1);

        // Join when game is full - should create new game
        address player4 = makeAddr("player4");
        token.mint(player4, AMOUNT * 10);
        vm.prank(player4);
        token.approve(address(royale), type(uint256).max);
        vm.prank(player4);
        bytes32 newGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify new game was created
        assertEq(newGameId, expectedNewGameId, "Should create new game when full");
        assertEq(royale.lobby(lobbyId), count + 1, "Lobby count should increment");

        // Verify new game state
        (uint128 players, uint128 capacity, address game_resolver, uint256 game_amount, address game_token, bool game_settled) = 
            royale.games(newGameId);
        assertEq(players, 1, "New game should have 1 player");
        assertEq(capacity, CAPACITY, "New game capacity should match");
        assertEq(game_resolver, resolver, "New game resolver should match");
        assertEq(game_amount, AMOUNT, "New game amount should match");
        assertEq(game_token, address(token), "New game token should match");
        assertEq(game_settled, false, "New game should not be settled");

        // Verify player4 joined new game
        bytes32 player4GameKey = keccak256(abi.encodePacked(player4, newGameId));
        assertTrue(royale.joined(player4GameKey), "Player4 should be marked as joined in new game");

        // Verify first game is still full
        (players,,,,,) = royale.games(firstGameId);
        assertEq(players, CAPACITY, "First game should remain full");
    }

    function test_join_PlayerAlreadyJoined() public {
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify player is marked as joined
        bytes32 playerGameKey = keccak256(abi.encodePacked(player1, gameId));
        assertTrue(royale.joined(playerGameKey), "Player should be marked as joined");

        vm.prank(player1);
        vm.expectRevert(Royale.PlayerAlreadyJoined.selector);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
    }

    function test_join_RevertInvalidResolver() public {
        vm.startPrank(player1);
        vm.expectRevert(Royale.InvalidResolver.selector);
        royale.join(address(0), address(token), AMOUNT, CAPACITY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             RESOLVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_resolve_SingleWinner() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify all players joined
        bytes32 player1GameKey = keccak256(abi.encodePacked(player1, gameId));
        bytes32 player2GameKey = keccak256(abi.encodePacked(player2, gameId));
        bytes32 player3GameKey = keccak256(abi.encodePacked(player3, gameId));
        assertTrue(royale.joined(player1GameKey), "Player1 should be marked as joined");
        assertTrue(royale.joined(player2GameKey), "Player2 should be marked as joined");
        assertTrue(royale.joined(player3GameKey), "Player3 should be marked as joined");

        // Create signature
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 3;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Add event expectation before resolve
        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId, winners, amounts);

        // Resolve game
        royale.resolve(gameId, winners, amounts, signature);

        // Check balances
        assertEq(token.balanceOf(player1), (AMOUNT * 10) - AMOUNT + (AMOUNT * 3), "Winner should receive prize");
        assertEq(token.balanceOf(player2), (AMOUNT * 10) - AMOUNT, "Loser should lose stake");
        assertEq(token.balanceOf(player3), (AMOUNT * 10) - AMOUNT, "Loser should lose stake");

        // Verify game is settled
        (,,,,, bool settled) = royale.games(gameId);
        assertTrue(settled, "Game should be settled");
    }

    function test_resolve_MultipleWinners() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Create signature
        address[] memory winners = new address[](2);
        winners[0] = player1;
        winners[1] = player2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT * 2;
        amounts[1] = AMOUNT;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Add event expectation before resolve
        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId, winners, amounts);

        // Resolve game
        royale.resolve(gameId, winners, amounts, signature);

        // Check balances
        assertEq(token.balanceOf(player1), (AMOUNT * 10) - AMOUNT + (AMOUNT * 2), "Winner1 should receive prize");
        assertEq(token.balanceOf(player2), (AMOUNT * 10) - AMOUNT + AMOUNT, "Winner2 should receive prize");
        assertEq(token.balanceOf(player3), (AMOUNT * 10) - AMOUNT, "Loser should lose stake");

        // Verify game is settled
        (,,,,, bool settled) = royale.games(gameId);
        assertTrue(settled, "Game should be settled");
    }

    function test_resolve_RevertAlreadySettled() public {
        // Setup and resolve game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 2;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        royale.resolve(gameId, winners, amounts, signature);

        // Try to resolve again
        vm.expectRevert(Royale.AlreadySettled.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidWinner() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        address[] memory winners = new address[](1);
        winners[0] = makeAddr("invalid");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 2;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidWinner.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidPayouts() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 3; // More than total pot

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidPayouts.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getPlayerCount() public {
        vm.prank(player1);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        uint256 count = royale.getPlayerCount(resolver, address(token), AMOUNT, CAPACITY);
        assertEq(count, 2, "Should return correct player count");
    }

    function test_isPlayerInGame() public {
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify player is in game
        assertTrue(royale.isPlayerInGame(gameId, player1), "Player1 should be in game");
        assertFalse(royale.isPlayerInGame(gameId, player2), "Player2 should not be in game");
    }

    function test_getPlayerGame() public {
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        bytes32 playerGame = royale.getPlayerGame(player1, resolver, address(token), AMOUNT, CAPACITY);
        assertEq(playerGame, gameId, "Should return correct game ID");

        bytes32 noGame = royale.getPlayerGame(player2, resolver, address(token), AMOUNT, CAPACITY);
        assertEq(noGame, bytes32(0), "Should return 0 for player not in game");
    }
}
