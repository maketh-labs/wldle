// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import {Reward} from "../src/Reward.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";

contract RewardTest is Test {
    ISignatureTransfer public constant PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IWorldID public constant WORLD_ID = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);

    Reward public reward;
    ERC20Mock public dlyToken;
    ERC20Mock public wordToken;

    address public owner = address(1);
    uint256 public ownerPrivateKey;
    address public user = address(2);
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        (owner, ownerPrivateKey) = makeAddrAndKey("owner");
        vm.startPrank(owner);
        dlyToken = new ERC20Mock();
        wordToken = new ERC20Mock();

        reward = new Reward(address(dlyToken), address(wordToken), WORLD_ID, "app_id", "action_id", address(PERMIT2));

        // Mint initial tokens
        dlyToken.mint(user, INITIAL_BALANCE);
        wordToken.mint(address(reward), INITIAL_BALANCE);
        vm.stopPrank();

        // Approve Permit2 contract for permit joins
        vm.prank(user);
        dlyToken.approve(address(PERMIT2), type(uint256).max);
    }

    function test_Migrate() public {
        uint256 amount = 100 ether;
        vm.startPrank(user);

        // Approve DLY tokens
        dlyToken.approve(address(reward), amount);

        // Migrate DLY to WORD
        reward.migrate(amount);

        // Check balances
        assertEq(dlyToken.balanceOf(user), INITIAL_BALANCE - amount);
        assertEq(wordToken.balanceOf(user), amount);
        assertEq(dlyToken.balanceOf(address(reward)), amount);
        vm.stopPrank();
    }

    function test_ClaimWithSignature() public {
        uint256 amount = 100 ether;
        uint256 category = 1;
        vm.startPrank(owner);

        // Create signature
        bytes32 messageHash = keccak256(abi.encode(user, amount, category));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.stopPrank();
        vm.startPrank(user);

        // Claim with signature
        reward.claim(amount, category, signature);

        // Check balance
        assertEq(wordToken.balanceOf(user), amount);

        // Try to use same signature again (should fail)
        vm.expectRevert(Reward.InvalidSignature.selector);
        reward.claim(amount, category, signature);
        vm.stopPrank();
    }

    function test_ClaimWithInvalidSignature() public {
        uint256 amount = 100 ether;
        uint256 category = 1;
        vm.startPrank(user);

        // Create invalid signature
        bytes memory invalidSignature = new bytes(65);

        // Try to claim with invalid signature (should fail)
        vm.expectRevert(Reward.InvalidSignature.selector);
        reward.claim(amount, category, invalidSignature);
        vm.stopPrank();
    }

    function test_ClaimWithWrongCategory() public {
        uint256 amount = 100 ether;
        uint256 category = 1;
        uint256 wrongCategory = 2;
        vm.startPrank(owner);

        // Create signature for category 1
        bytes32 messageHash = keccak256(abi.encode(user, amount, category));
        bytes32 signedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, signedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.stopPrank();
        vm.startPrank(user);

        // Try to claim with wrong category (should fail)
        vm.expectRevert(Reward.InvalidSignature.selector);
        reward.claim(amount, wrongCategory, signature);
        vm.stopPrank();
    }

    function test_MigrateWithPermit_RevertInvalidDestination() public {
        uint256 amount = 100 ether;

        // Create permit data
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(dlyToken), amount: amount}),
            nonce: 0,
            deadline: block.timestamp + 1
        });

        // Create transfer details with wrong destination (user instead of contract)
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: user, requestedAmount: amount});

        // Create signature (not actually used since we expect a revert before signature verification)
        bytes memory signature = new bytes(65);

        // Attempt to migrate with wrong destination
        vm.startPrank(user);
        vm.expectRevert(Reward.InvalidPermitTransfer.selector);
        reward.migrateWithPermit(permit, transferDetails, signature);
        vm.stopPrank();
    }
}
