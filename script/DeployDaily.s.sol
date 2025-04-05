// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Daily} from "../src/Daily.sol";
import {DLY} from "../src/DLY.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";

contract DeployDailyScript is Script {
    Daily public daily;
    DLY public dlyToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        dlyToken = new DLY();

        address worldId = 0x17B354dD2595411ff79041f930e491A4Df39A278;
        string memory appId = "app_c895e94c9c7d2ab9899b6083ad95e31d";
        string memory actionId = "claim-daily";

        daily = new Daily(IWorldID(worldId), address(dlyToken), appId, actionId);

        dlyToken.transfer(address(daily), 10_000_000_000 ether);

        vm.stopBroadcast();

        console.log("Daily contract address:", address(daily));
        console.log("DLY token address:", address(dlyToken));
    }
}
