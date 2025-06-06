// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract DLY is ERC20, ERC20Permit {
    constructor() ERC20("Worldle", "DLY") ERC20Permit("Worldle") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}
