// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Duel} from "../src/Duel.sol";

contract DuelTest is Test {
    Duel public duel;
    ERC20Mock public token;

    address public player1;
    address public player2;
    address public resolver;
    uint256 public resolverPrivateKey;

    uint256 public constant AMOUNT = 1000;
    uint256 public constant FEE = 100;

    event Created(bytes32 gameId, address player1, address resolver, address token, uint256 amount, uint256 fee);
    event Joined(bytes32 gameId, address player2);

    function setUp() public {
        // Deploy contracts
        duel = new Duel();
        token = new ERC20Mock();

        // Setup accounts
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        (resolver, resolverPrivateKey) = makeAddrAndKey("resolver");

        // Fund players
        token.mint(player1, AMOUNT * 10);
        token.mint(player2, AMOUNT * 10);

        vm.startPrank(player1);
        token.approve(address(duel), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(player2);
        token.approve(address(duel), type(uint256).max);
        vm.stopPrank();
    }

    function getLobbyId(address resolver, address token, uint256 amount, uint256 fee) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(resolver, token, amount, fee));
    }

    function getGameId(bytes32 lobbyId, uint256 count) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(lobbyId, count));
    }

    /*//////////////////////////////////////////////////////////////
                                JOIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_join_CreateNewGame() public {
        vm.startPrank(player1);

        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);
        // Use count.created (which will be 0) for the first game
        bytes32 expectedGameId = getGameId(lobbyId, 0);

        // vm.expectEmit(true, true, true, true);
        // emit Created(expectedGameId, player1, resolver, address(token), AMOUNT, FEE);

        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        assertEq(gameId, expectedGameId, "Game ID should match expected");

        // Check lobby count
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should be 1");
        assertEq(played, 0, "Played count should be 0");

        (
            address game_player1,
            address game_player2,
            address game_resolver,
            uint256 game_amount,
            uint256 game_fee,
            address game_token,
            bool game_settled
        ) = duel.games(gameId);

        assertEq(game_player1, player1, "Player1 should be set");
        assertEq(game_player2, address(0), "Player2 should be empty");
        assertEq(game_resolver, resolver, "Resolver should be set");
        assertEq(game_amount, AMOUNT, "Amount should be set");
        assertEq(game_fee, FEE, "Fee should be set");
        assertEq(game_token, address(token), "Token should be set");
        assertEq(game_settled, false, "Game should not be settled");

        assertEq(token.balanceOf(address(duel)), AMOUNT, "Contract should hold tokens");
        vm.stopPrank();
    }

    function test_join_JoinExistingGame() public {
        // Create game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        // Join game
        vm.startPrank(player2);
        vm.expectEmit(true, true, true, true);
        emit Joined(gameId, player2);

        bytes32 joinedGameId = duel.join(resolver, address(token), AMOUNT, FEE);

        assertEq(joinedGameId, gameId, "Should join existing game");

        (address game_player1, address game_player2,,,,,) = duel.games(gameId);

        assertEq(game_player1, player1, "Player1 should remain");
        assertEq(game_player2, player2, "Player2 should be set");

        assertEq(token.balanceOf(address(duel)), AMOUNT * 2, "Contract should hold both players' tokens");
        vm.stopPrank();
    }

    function test_join_RevertInvalidResolver() public {
        vm.startPrank(player1);
        vm.expectRevert(Duel.InvalidResolver.selector);
        duel.join(address(0), address(token), AMOUNT, FEE);
        vm.stopPrank();
    }

    function test_join_RevertInsufficientValue() public {
        vm.startPrank(player1);
        vm.expectRevert(Duel.InsufficientValue.selector);
        duel.join(resolver, address(token), FEE, FEE);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             RESOLVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_resolve_Winner() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Setup game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Check lobby count before resolve
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should be 1");
        assertEq(played, 1, "Played count should be 1");

        // Create signature
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, player1));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Resolve game
        duel.resolve(gameId, player1, signature);

        // Check balances
        uint256 expectedWinnerPrize = (AMOUNT * 2) - FEE;
        assertEq(token.balanceOf(player1), (AMOUNT * 10) - AMOUNT + expectedWinnerPrize, "Winner should receive prize");
        assertEq(token.balanceOf(player2), (AMOUNT * 10) - AMOUNT, "Loser should lose stake");
        assertEq(token.balanceOf(duel.owner()), FEE, "Owner should receive fee");

        // Verify game is settled
        (,,,,,, bool settled) = duel.games(gameId);
        assertTrue(settled, "Game should be settled");
    }

    function test_resolve_Draw() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Setup game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Create signature for draw (address(0))
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, address(0)));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Resolve game
        duel.resolve(gameId, address(0), signature);

        // Check balances - both players should get their stakes back
        assertEq(token.balanceOf(player1), (AMOUNT * 10), "Player1 should get stake back");
        assertEq(token.balanceOf(player2), (AMOUNT * 10), "Player2 should get stake back");
        assertEq(token.balanceOf(duel.owner()), 0, "Owner should not receive fee on draw");

        // Verify game is settled
        (,,,,,, bool settled) = duel.games(gameId);
        assertTrue(settled, "Game should be settled");

        // Check lobby count remains unchanged
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should remain 1");
        assertEq(played, 1, "Played count should remain 1");
    }

    function test_resolve_RevertAlreadySettled() public {
        // Setup and resolve game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, player1));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        duel.resolve(gameId, player1, signature);

        // Try to resolve again
        vm.expectRevert(Duel.AlreadySettled.selector);
        duel.resolve(gameId, player1, signature);
    }

    function test_resolve_RevertNotStarted() public {
        // Create game but don't join
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, player1));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Duel.NotStarted.selector);
        duel.resolve(gameId, player1, signature);
    }

    function test_resolve_RevertInvalidWinner() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        address invalidWinner = makeAddr("invalid");
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, invalidWinner));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Duel.InvalidWinner.selector);
        duel.resolve(gameId, invalidWinner, signature);
    }

    /*//////////////////////////////////////////////////////////////
                             CANCEL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancel_BeforeJoin() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Create game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        // Create cancel signature
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, "CANCEL"));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Cancel game
        duel.cancel(gameId, signature);

        // Check balances
        assertEq(token.balanceOf(player1), AMOUNT * 10, "Player1 should get stake back");
        assertEq(token.balanceOf(address(duel)), 0, "Contract should have no tokens");

        // Verify game state
        (,,,,,, bool settled) = duel.games(gameId);
        assertTrue(settled, "Game should be settled");

        // Check lobby count remains unchanged
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should remain 1");
        assertEq(played, 0, "Played count should remain 0");
    }

    function test_cancel_AfterJoin() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Setup full game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Create cancel signature
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, "CANCEL"));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Cancel game
        duel.cancel(gameId, signature);

        // Check balances
        assertEq(token.balanceOf(player1), AMOUNT * 10, "Player1 should get stake back");
        assertEq(token.balanceOf(player2), AMOUNT * 10, "Player2 should get stake back");
        assertEq(token.balanceOf(address(duel)), 0, "Contract should have no tokens");

        // Check lobby count remains unchanged
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should remain 1");
        assertEq(played, 1, "Played count should remain 1");
    }

    function test_cancel_RevertAlreadyResolved() public {
        // Setup and resolve game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Resolve game first
        bytes32 resolveHash = keccak256(abi.encodePacked(gameId, player1));
        bytes32 resolveSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", resolveHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, resolveSignedHash);
        bytes memory resolveSignature = abi.encodePacked(r, s, v);
        duel.resolve(gameId, player1, resolveSignature);

        // Try to cancel
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, "CANCEL"));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (v, r, s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Duel.AlreadyResolved.selector);
        duel.cancel(gameId, signature);
    }

    function test_cancel_RevertInvalidSignature() public {
        // Create game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        // Create invalid signature (using different private key)
        (address badResolver, uint256 badResolverKey) = makeAddrAndKey("badResolver");
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, "CANCEL"));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(badResolverKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Duel.InvalidSignature.selector);
        duel.cancel(gameId, signature);
    }

    /*//////////////////////////////////////////////////////////////
                          FORCE CANCEL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_forceCancel_BeforeJoin() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Create game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        // Force cancel as resolver
        vm.prank(resolver);
        duel.forceCancel(gameId);

        // Check balances
        assertEq(token.balanceOf(player1), AMOUNT * 10, "Player1 should get stake back");
        assertEq(token.balanceOf(address(duel)), 0, "Contract should have no tokens");

        // Verify game state
        (,,,,,, bool settled) = duel.games(gameId);
        assertTrue(settled, "Game should be settled");

        // Check lobby count remains unchanged
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should remain 1");
        assertEq(played, 0, "Played count should remain 0");
    }

    function test_forceCancel_AfterJoin() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, FEE);

        // Setup full game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Force cancel as resolver
        vm.prank(resolver);
        duel.forceCancel(gameId);

        // Check balances
        assertEq(token.balanceOf(player1), AMOUNT * 10, "Player1 should get stake back");
        assertEq(token.balanceOf(player2), AMOUNT * 10, "Player2 should get stake back");
        assertEq(token.balanceOf(address(duel)), 0, "Contract should have no tokens");

        // Check lobby count remains unchanged
        (uint128 created, uint128 played) = duel.lobby(lobbyId);
        assertEq(created, 1, "Created count should remain 1");
        assertEq(played, 1, "Played count should remain 1");
    }

    function test_forceCancel_RevertNotResolver() public {
        // Create game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

        // Try to force cancel as non-resolver
        vm.prank(player1);
        vm.expectRevert(Duel.NotResolver.selector);
        duel.forceCancel(gameId);
    }

    function test_forceCancel_RevertAlreadyResolved() public {
        // Setup and resolve game
        vm.prank(player1);
        bytes32 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

        // Resolve game first
        bytes32 resolveHash = keccak256(abi.encodePacked(gameId, player1));
        bytes32 resolveSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", resolveHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, resolveSignedHash);
        bytes memory resolveSignature = abi.encodePacked(r, s, v);
        duel.resolve(gameId, player1, resolveSignature);

        // Try to force cancel
        vm.prank(resolver);
        vm.expectRevert(Duel.AlreadyResolved.selector);
        duel.forceCancel(gameId);
    }
}
