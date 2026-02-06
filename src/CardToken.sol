// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title CardToken — Fixed-supply ERC-20 minted once by Whirlpool
contract CardToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        address mintTo,
        uint256 supply
    ) ERC20(name_, symbol_) {
        _mint(mintTo, supply);
    }
}
