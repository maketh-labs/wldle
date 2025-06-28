// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Royale} from "../src/Royale.sol";

contract UpgradeRoyale is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS"); // Set this to your deployed proxy address

        // Permit2 contract address (same on all chains)
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        Royale newImplementation = new Royale(permit2);
        console.log("New Royale implementation deployed at:", address(newImplementation));

        // Get the proxy contract
        Royale proxy = Royale(proxyAddress);

        // Upgrade to the new implementation
        // This calls the upgradeTo function on the proxy, which internally calls _authorizeUpgrade
        proxy.upgradeToAndCall(address(newImplementation), "");

        console.log("Royale proxy upgraded successfully");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", address(newImplementation));

        vm.stopBroadcast();
    }
}
