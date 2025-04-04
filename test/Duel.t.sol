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

    event Created(uint256 gameId, address player1, address resolver, address token, uint256 amount, uint256 fee);
    event Joined(uint256 gameId, address player2);

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

    /*//////////////////////////////////////////////////////////////
                                JOIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_join_CreateNewGame() public {
        vm.startPrank(player1);
        
        vm.expectEmit(true, true, true, true);
        emit Created(1, player1, resolver, address(token), AMOUNT, FEE);
        
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        
        assertEq(gameId, 1, "Game ID should be 1");
        
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
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        
        // Join game
        vm.startPrank(player2);
        vm.expectEmit(true, true, true, true);
        emit Joined(gameId, player2);
        
        uint256 joinedGameId = duel.join(resolver, address(token), AMOUNT, FEE);
        
        assertEq(joinedGameId, gameId, "Should join existing game");
        
        (
            address game_player1,
            address game_player2,
            ,,,,
        ) = duel.games(gameId);
        
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
        // Setup game
        vm.prank(player1);
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
        vm.prank(player2);
        duel.join(resolver, address(token), AMOUNT, FEE);

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
    }

    function test_resolve_Draw() public {
        // Setup game
        vm.prank(player1);
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
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
    }

    function test_resolve_RevertAlreadySettled() public {
        // Setup and resolve game
        vm.prank(player1);
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
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
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);

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
        uint256 gameId = duel.join(resolver, address(token), AMOUNT, FEE);
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
}
