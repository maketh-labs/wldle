// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Duel} from "../src/Duel.sol";

contract DuelTest is Test {
    Duel public duel;

    function setUp() public {
        // duel = new Duel();
        console.log("set up");
    }

    function test_Duel() public {
        console.log("test duel");
    }
}
