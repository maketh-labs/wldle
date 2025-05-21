// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Royale} from "../src/Royale.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

contract RoyaleTest is Test {
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    Royale public royale;
    ERC20Mock public token;

    address public player1;
    uint256 public player1PrivateKey;
    address public player2;
    uint256 public player2PrivateKey;
    address public player3;
    uint256 public player3PrivateKey;
    address public player4;
    uint256 public player4PrivateKey;
    address public resolver;
    uint256 public resolverPrivateKey;

    uint256 public constant AMOUNT = 1 ether;
    uint128 public constant CAPACITY = 3;

    event Created(bytes32 gameId, address player, address resolver, address token, uint256 amount, uint128 capacity);
    event Joined(bytes32 gameId, address creator, address player, uint128 players);
    event Resolved(bytes32 gameId, address[] winners, uint256[] amounts);

    function setUp() public {
        // Deploy contracts
        royale = new Royale(address(PERMIT2));
        token = new ERC20Mock();

        // Setup accounts
        (player1, player1PrivateKey) = makeAddrAndKey("player1");
        (player2, player2PrivateKey) = makeAddrAndKey("player2");
        (player3, player3PrivateKey) = makeAddrAndKey("player3");
        (player4, player4PrivateKey) = makeAddrAndKey("player4");
        (resolver, resolverPrivateKey) = makeAddrAndKey("resolver");

        // Fund players
        token.mint(player1, AMOUNT * 10);
        token.mint(player2, AMOUNT * 10);
        token.mint(player3, AMOUNT * 10);
        token.mint(player4, AMOUNT * 10);

        // Approve Royale contract for standard joins
        vm.prank(player1);
        token.approve(address(royale), type(uint256).max);
        vm.prank(player2);
        token.approve(address(royale), type(uint256).max);
        vm.prank(player3);
        token.approve(address(royale), type(uint256).max);
        vm.prank(player4);
        token.approve(address(royale), type(uint256).max);

        // Approve Permit2 contract for permit joins
        vm.prank(player1);
        token.approve(address(PERMIT2), type(uint256).max);
        vm.prank(player2);
        token.approve(address(PERMIT2), type(uint256).max);
        vm.prank(player3);
        token.approve(address(PERMIT2), type(uint256).max);
        vm.prank(player4);
        token.approve(address(PERMIT2), type(uint256).max);
    }

    function getLobbyId(address _resolver, address _token, uint256 _amount, uint128 _capacity)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_resolver, _token, _amount, _capacity));
    }

    function getPlayerLobbyKey(address player, bytes32 lobbyId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, lobbyId));
    }

    function getPlayerGameKey(address player, bytes32 gameId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(player, gameId));
    }

    /*//////////////////////////////////////////////////////////////
                                JOIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_join_CreateFirstGame() public {
        vm.startPrank(player1);

        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 player1LobbyKey = getPlayerLobbyKey(player1, lobbyId);

        // Expected state before join
        assertEq(royale.lobby(lobbyId), 0, "Initial lobby count should be 0");
        assertEq(royale.countOf(player1LobbyKey), 0, "Initial player countOf should be 0");

        // Expected gameId for the first game (index 1)
        bytes32 expectedGameId = keccak256(abi.encodePacked(lobbyId, uint256(1)));

        vm.expectEmit(true, true, true, true);
        emit Created(expectedGameId, player1, resolver, address(token), AMOUNT, CAPACITY);

        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        assertEq(gameId, expectedGameId, "Game ID should match expected index 1");

        // Check state after join
        assertEq(royale.lobby(lobbyId), 0, "Lobby count should remain 0 (game not full)");
        assertEq(royale.countOf(player1LobbyKey), 1, "Player countOf should be 1");

        (uint128 players,,,,,,) = royale.games(gameId);
        assertEq(players, 1, "Players should be 1");

        // Verify player joined mapping
        bytes32 playerGameKey = getPlayerGameKey(player1, gameId);
        assertTrue(royale.joined(playerGameKey), "Player should be marked as joined");

        assertEq(token.balanceOf(address(royale)), AMOUNT, "Contract should hold tokens");
        vm.stopPrank();
    }

    function test_join_JoinExisting_NotFull() public {
        // Player 1 creates game (index 1)
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 player1LobbyKey = getPlayerLobbyKey(player1, lobbyId);
        bytes32 player2LobbyKey = getPlayerLobbyKey(player2, lobbyId);

        // State after P1 joins
        assertEq(royale.lobby(lobbyId), 0);
        assertEq(royale.countOf(player1LobbyKey), 1);
        assertEq(royale.countOf(player2LobbyKey), 0);
        (uint128 playersBefore,,,,,,) = royale.games(gameId);
        assertEq(playersBefore, 1);

        // Player 2 joins the *same* game (index 1)
        vm.startPrank(player2);
        vm.expectEmit(true, true, true, true);
        emit Joined(gameId, player1, player2, 2); // Expect 2 players now
        bytes32 joinedGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        assertEq(joinedGameId, gameId, "Should join existing game (index 1)");

        // Check state after P2 joins
        assertEq(royale.lobby(lobbyId), 0, "Lobby count should remain 0 (game not full)");
        assertEq(royale.countOf(player1LobbyKey), 1, "P1 countOf should be unchanged");
        assertEq(royale.countOf(player2LobbyKey), 1, "P2 countOf should be 1");

        (uint128 playersAfter,,,,,,) = royale.games(gameId);
        assertEq(playersAfter, 2, "Players should be 2");

        // Verify both players joined mapping
        bytes32 player1GameKey = getPlayerGameKey(player1, gameId);
        bytes32 player2GameKey = getPlayerGameKey(player2, gameId);
        assertTrue(royale.joined(player1GameKey), "Player1 should be marked as joined");
        assertTrue(royale.joined(player2GameKey), "Player2 should be marked as joined");

        assertEq(token.balanceOf(address(royale)), AMOUNT * 2, "Contract should hold both players' tokens");
        vm.stopPrank();
    }

    function test_join_CreateNew_WhenGameFull() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 player1LobbyKey = getPlayerLobbyKey(player1, lobbyId);
        bytes32 player2LobbyKey = getPlayerLobbyKey(player2, lobbyId);
        bytes32 player3LobbyKey = getPlayerLobbyKey(player3, lobbyId);
        bytes32 player4LobbyKey = getPlayerLobbyKey(player4, lobbyId);

        // Create and fill game 1 (index 1)
        vm.prank(player1);
        bytes32 firstGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY); // game index 1
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY); // joins game index 1
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY); // joins game index 1, makes it full

        // Check state after game 1 is full
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should be 1 (game 1 full)");
        assertEq(royale.countOf(player1LobbyKey), 1);
        assertEq(royale.countOf(player2LobbyKey), 1);
        assertEq(royale.countOf(player3LobbyKey), 1);
        (uint128 playersGame1,,,,,,) = royale.games(firstGameId);
        assertEq(playersGame1, CAPACITY, "First game should be full");

        // Player 4 joins when game 1 is full - should create game 2 (index 2)
        // nextCount = max(lobby[lobbyId], countOf[p4]) + 1 = max(1, 0) + 1 = 2
        bytes32 expectedNewGameId = keccak256(abi.encodePacked(lobbyId, uint256(2)));

        vm.startPrank(player4);
        vm.expectEmit(true, true, true, true);
        emit Created(expectedNewGameId, player4, resolver, address(token), AMOUNT, CAPACITY);
        bytes32 newGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify new game was created
        assertEq(newGameId, expectedNewGameId, "Should create new game (index 2)");

        // Verify state after P4 joins
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should remain 1");
        assertEq(royale.countOf(player4LobbyKey), 2, "Player4 countOf should be 2");

        // Verify new game state
        (uint128 playersGame2,,,,,,) = royale.games(newGameId);
        assertEq(playersGame2, 1, "New game should have 1 player");

        // Verify player4 joined mapping for new game
        bytes32 player4GameKey = getPlayerGameKey(player4, newGameId);
        assertTrue(royale.joined(player4GameKey), "Player4 should be marked as joined in new game");

        // Verify first game is still full
        (playersGame1,,,,,,) = royale.games(firstGameId);
        assertEq(playersGame1, CAPACITY, "First game should remain full");

        assertEq(token.balanceOf(address(royale)), AMOUNT * 4, "Contract balance check");
        vm.stopPrank();
    }

    function test_join_RejoinLobbyAfterGameFull() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 player1LobbyKey = getPlayerLobbyKey(player1, lobbyId);

        // Create and fill game 1 (index 1) with player1
        vm.prank(player1);
        bytes32 firstGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY); // P1 joins game 1
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY); // P2 joins game 1
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY); // P3 joins game 1, makes it full

        // Verify game 1 is full and state
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should be 1");
        assertEq(royale.countOf(player1LobbyKey), 1, "P1 countOf should be 1");
        (uint128 playersGame1,,,,,,) = royale.games(firstGameId);
        assertEq(playersGame1, CAPACITY, "Game 1 should be full");
        bytes32 player1Game1Key = getPlayerGameKey(player1, firstGameId);
        assertTrue(royale.joined(player1Game1Key), "Player1 should be joined in game 1");

        // Player1 tries to join the lobby again
        // closedCount = lobby[lobbyId] = 1
        // lastJoinedCount = countOf[player1LobbyKey] = 1
        // nextCount = max(1, 1) + 1 = 2
        bytes32 expectedNewGameId = keccak256(abi.encodePacked(lobbyId, uint256(2)));

        vm.startPrank(player1);
        vm.expectEmit(true, true, true, true);
        emit Created(expectedNewGameId, player1, resolver, address(token), AMOUNT, CAPACITY);
        bytes32 newGameId = royale.join(resolver, address(token), AMOUNT, CAPACITY); // P1 should create game 2

        // Verify new game (index 2) was created
        assertEq(newGameId, expectedNewGameId, "Should create new game (index 2)");

        // Verify state after P1 rejoins
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should remain 1");
        assertEq(royale.countOf(player1LobbyKey), 2, "P1 countOf should now be 2");

        // Verify new game state
        (uint128 playersGame2,,,,,,) = royale.games(newGameId);
        assertEq(playersGame2, 1, "New game (index 2) should have 1 player (P1)");

        // Verify player1 is marked as joined in new game
        bytes32 player1Game2Key = getPlayerGameKey(player1, newGameId);
        assertTrue(royale.joined(player1Game2Key), "Player1 should be marked as joined in new game (index 2)");

        // Verify first game is still full and unchanged
        (playersGame1,,,,,,) = royale.games(firstGameId);
        assertEq(playersGame1, CAPACITY, "First game should remain full");
        vm.stopPrank();
    }

    function test_join_RevertInvalidResolver() public {
        vm.startPrank(player1);
        vm.expectRevert(Royale.InvalidResolver.selector);
        royale.join(address(0), address(token), AMOUNT, CAPACITY);
        vm.stopPrank();
    }

    function test_join_RevertInvalidCapacity() public {
        vm.startPrank(player1);
        vm.expectRevert(Royale.InvalidCapacity.selector);
        royale.join(resolver, address(token), AMOUNT, 1); // Capacity must be >= 2
        vm.stopPrank();
    }

    function test_joinWithPermit_RevertInvalidDestination() public {
        // Create permit data
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token), amount: AMOUNT}),
            nonce: 0,
            deadline: block.timestamp + 1
        });

        // Create transfer details with wrong destination (player2 instead of contract)
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: player2, requestedAmount: AMOUNT});

        // Create signature (not actually used since we expect a revert before signature verification)
        bytes memory signature = new bytes(65);

        // Attempt to join with wrong destination
        vm.startPrank(player1);
        vm.expectRevert(Royale.InvalidPermitTransfer.selector);
        royale.joinWithPermit(resolver, address(token), CAPACITY, permit, transferDetails, signature);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             RESOLVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_resolve_FullGame_SingleWinner() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // Setup and fill game (index 1)
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify game is full and lobby count updated
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should be 1 after game is full");
        (uint128 players,,,,,,) = royale.games(gameId);
        assertEq(players, CAPACITY, "Game should be full");

        // Prepare signature
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * CAPACITY; // Player 1 wins the pot

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId, winners, amounts);

        // Resolve the full game
        royale.resolve(gameId, winners, amounts, signature);

        // Check balances
        uint256 initialBalance = AMOUNT * 10;
        assertEq(token.balanceOf(player1), initialBalance - AMOUNT + (AMOUNT * CAPACITY), "Winner balance incorrect");
        assertEq(token.balanceOf(player2), initialBalance - AMOUNT, "Loser 2 balance incorrect");
        assertEq(token.balanceOf(player3), initialBalance - AMOUNT, "Loser 3 balance incorrect");
        assertEq(token.balanceOf(resolver), 0, "Resolver should have 0 (no remaining amount)");

        // Verify game is settled
        (,,,,,, bool settled) = royale.games(gameId);
        assertTrue(settled, "Game should be settled");

        // Verify lobby count remains 1 (was already incremented when game filled)
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should remain 1 after resolving full game");
    }

    function test_resolve_FullGame_MultipleWinners_WithRemainder() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // Setup and fill game (index 1)
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        assertEq(royale.lobby(lobbyId), 1); // Game is full

        // Prepare signature - P1 gets 1.5x, P2 gets 1x, remainder to resolver
        address[] memory winners = new address[](2);
        winners[0] = player1;
        winners[1] = player2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = AMOUNT + AMOUNT / 2; // 1500
        amounts[1] = AMOUNT; // 1000
        // Total Payout = 2500. Total Pot = 3000. Remainder = 500.

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId, winners, amounts);

        // Resolve the full game
        royale.resolve(gameId, winners, amounts, signature);

        // Check balances
        uint256 initialBalance = AMOUNT * 10;
        uint256 expectedRemainder = (AMOUNT * CAPACITY) - amounts[0] - amounts[1]; // 3000 - 1500 - 1000 = 500
        assertEq(token.balanceOf(player1), initialBalance - AMOUNT + amounts[0], "Winner 1 balance incorrect");
        assertEq(token.balanceOf(player2), initialBalance - AMOUNT + amounts[1], "Winner 2 balance incorrect");
        assertEq(token.balanceOf(player3), initialBalance - AMOUNT, "Loser 3 balance incorrect");
        assertEq(token.balanceOf(resolver), expectedRemainder, "Resolver should have remainder");

        (,,,,,, bool settled) = royale.games(gameId);
        assertTrue(settled, "Game should be settled");
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should remain 1");
    }

    function test_resolve_NotFullGame_Success() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // Setup game with 2 players (index 1), Capacity 3
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify game is not full and lobby count is 0
        assertEq(royale.lobby(lobbyId), 0, "Lobby count should be 0 before resolve");
        (uint128 players,,,,,,) = royale.games(gameId);
        assertEq(players, 2, "Game should have 2 players");

        // Prepare signature for resolution (P1 wins pot of 2 players)
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 2; // P1 wins the pot of 2 players

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId, winners, amounts);

        // Resolve the not-full game (should succeed as it's the oldest open game: index 1 = lobby[id]+1 = 0+1)
        royale.resolve(gameId, winners, amounts, signature);

        // Check balances
        uint256 initialBalance = AMOUNT * 10;
        assertEq(token.balanceOf(player1), initialBalance - AMOUNT + (AMOUNT * 2), "Winner balance incorrect");
        assertEq(token.balanceOf(player2), initialBalance - AMOUNT, "Loser balance incorrect");
        assertEq(token.balanceOf(resolver), 0, "Resolver should have 0");

        (,,,,,, bool settled) = royale.games(gameId);
        assertTrue(settled, "Game should be settled");

        // Verify lobby count increments because an under-capacity game was resolved
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should increment after resolving not-full game");
    }

    // Test resolving the actual oldest open game when it's not full
    function test_resolve_OldestOpenGame_NotFull_Success() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // P1 creates game 1 (index 1)
        vm.prank(player1);
        bytes32 gameId1 = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        // P2 joins game 1
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // State check: lobby count is 0, game 1 is oldest open (index 0+1=1)
        assertEq(royale.lobby(lobbyId), 0);
        (uint128 players1,,,,,,) = royale.games(gameId1);
        assertEq(players1, 2);

        // Prepare to resolve game 1
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 2; // P1 wins the pot of 2 players

        bytes32 messageHash = keccak256(abi.encodePacked(gameId1, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectEmit(true, true, true, true);
        emit Resolved(gameId1, winners, amounts);

        // Action: Resolve game 1 (should succeed)
        royale.resolve(gameId1, winners, amounts, signature);

        // Assertions
        assertEq(token.balanceOf(player1), (AMOUNT * 10) - AMOUNT + (AMOUNT * 2), "Winner balance incorrect"); // Balance updated
        (,,,,,, bool settled) = royale.games(gameId1);
        assertTrue(settled, "Game 1 should be settled");
        assertEq(royale.lobby(lobbyId), 1, "Lobby count should increment to 1");
    }

    // Test resolving the second oldest open game only *after* the oldest has been resolved
    function test_resolve_SecondOldestOpenGame_NotFull_SuccessAfterOldestResolved() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // P1 creates game 1 (index 1)
        vm.prank(player1);
        bytes32 gameId1 = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        // P1 creates game 2 (index 2)
        vm.prank(player1);
        bytes32 gameId2 = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Resolve game 1 first
        {
            address[] memory winners = new address[](1);
            winners[0] = player1;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = AMOUNT;
            bytes32 mh = keccak256(abi.encodePacked(gameId1, winners, amounts));
            bytes32 sh = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", mh));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, sh);
            bytes memory sig = abi.encodePacked(r, s, v);
            royale.resolve(gameId1, winners, amounts, sig);
        }

        // State check: lobby count is 1, game 2 is now oldest open (index 1+1=2)
        assertEq(royale.lobby(lobbyId), 1);
        (uint128 players,,,,,,) = royale.games(gameId2);
        assertEq(players, 1);

        // Prepare to resolve game 2
        {
            address[] memory winners = new address[](1);
            winners[0] = player1;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = AMOUNT * 1;
            bytes32 mh = keccak256(abi.encodePacked(gameId2, winners, amounts));
            bytes32 sh = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", mh));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, sh);
            bytes memory sig = abi.encodePacked(r, s, v);

            vm.expectEmit(true, true, true, true);
            emit Resolved(gameId2, winners, amounts);

            // Action: Resolve game 2 (should succeed)
            royale.resolve(gameId2, winners, amounts, sig);
        }

        // Assertions
        assertEq(token.balanceOf(player1), AMOUNT * 10, "Winner balance incorrect"); // Got stake back
        (,,,,,, bool settled) = royale.games(gameId2);
        assertTrue(settled, "Game 2 should be settled");
        assertEq(royale.lobby(lobbyId), 2, "Lobby count should increment to 2");
    }

    // Test reverting when trying to resolve an open game that isn't the oldest
    function test_resolve_NotOldestOpenGame_NotFull_Revert() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);

        // P1 creates game 1 (index 1)
        vm.prank(player1);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        // P1 creates game 2 (index 2)
        vm.prank(player1);
        bytes32 gameId2 = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // State check: lobby count is 0, oldest open game is index 1
        assertEq(royale.lobby(lobbyId), 0);

        // Prepare to resolve game 2 (incorrectly)
        address[] memory winners = new address[](1);
        winners[0] = player2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 1;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId2, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Action: Attempt to resolve game 2
        vm.expectRevert(Royale.NotOldestOpenGame.selector);
        royale.resolve(gameId2, winners, amounts, signature);
    }

    function test_resolve_RevertAlreadySettled() public {
        // Setup and fill game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player3);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Prepare signature & resolve once
        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 3;
        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        royale.resolve(gameId, winners, amounts, signature);

        // Try to resolve again
        vm.expectRevert(Royale.AlreadySettled.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertNotStarted() public {
        bytes32 lobbyId = getLobbyId(resolver, address(token), AMOUNT, CAPACITY);
        bytes32 nonExistentGameId = keccak256(abi.encodePacked(lobbyId, uint256(99))); // Assume index 99 doesn't exist

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;
        bytes32 messageHash = keccak256(abi.encodePacked(nonExistentGameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.NotStarted.selector);
        royale.resolve(nonExistentGameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidWinner() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Try to resolve with an invalid winner (player4 not in game)
        address[] memory winners = new address[](1);
        winners[0] = player4; // Invalid winner
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 2;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidWinner.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidPayouts_LengthMismatch() public {
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY);

        address[] memory winners = new address[](1); // 1 winner
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](2); // 2 amounts
        amounts[0] = AMOUNT;
        amounts[1] = AMOUNT;

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidPayouts.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidPayouts_ExceedsPot() public {
        // Setup game
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);
        vm.prank(player2);
        royale.join(resolver, address(token), AMOUNT, CAPACITY); // Pot = 2000

        address[] memory winners = new address[](1);
        winners[0] = player1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT * 3; // Payout 3000 > Pot 2000

        bytes32 messageHash = keccak256(abi.encodePacked(gameId, winners, amounts));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(resolverPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidPayouts.selector);
        royale.resolve(gameId, winners, amounts, signature);
    }

    function test_resolve_RevertInvalidSignature() public {
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

        // Sign with wrong key (player1's key instead of resolver's)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(player1PrivateKey, signedHash);
        bytes memory badSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(Royale.InvalidSignature.selector);
        royale.resolve(gameId, winners, amounts, badSignature);
    }

    // /*//////////////////////////////////////////////////////////////
    //                          VIEW TESTS
    // //////////////////////////////////////////////////////////////*/

    function test_isPlayerInGame() public {
        vm.prank(player1);
        bytes32 gameId = royale.join(resolver, address(token), AMOUNT, CAPACITY);

        // Verify player is in game using the view function
        assertTrue(royale.isPlayerInGame(gameId, player1), "isPlayerInGame(P1) should be true");
        assertFalse(royale.isPlayerInGame(gameId, player2), "isPlayerInGame(P2) should be false");

        // Verify using direct mapping access as well
        bytes32 player1GameKey = getPlayerGameKey(player1, gameId);
        bytes32 player2GameKey = getPlayerGameKey(player2, gameId);
        assertTrue(royale.joined(player1GameKey), "joined[P1] should be true");
        assertFalse(royale.joined(player2GameKey), "joined[P2] should be false"); // Check it's not accidentally true
    }
}
