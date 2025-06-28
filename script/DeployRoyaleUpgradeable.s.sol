// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Royale} from "../src/Royale.sol";

contract DeployRoyaleUpgradeable is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Permit2 contract address (same on all chains)
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract
        Royale implementation = new Royale(permit2);
        console.log("Royale implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            Royale.initialize.selector,
            deployer // owner
        );

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Royale proxy deployed at:", address(proxy));

        // The proxy address is the actual contract address users will interact with
        Royale royale = Royale(address(proxy));
        console.log("Royale contract ready at:", address(royale));
        console.log("Owner:", royale.owner());

        vm.stopBroadcast();
    }
}
