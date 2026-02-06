// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title WAVES — Hub token for Whirlpool AMM
/// @notice 10M max supply, only mintable by the WhirlpoolRouter contract
contract WAVES is ERC20 {
    uint256 public constant MAX_SUPPLY = 10_000_000 ether;
    address public immutable router;

    error OnlyRouter();
    error ExceedsMaxSupply();

    constructor(address router_) ERC20("WAVES", "WAVES") {
        router = router_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != router) revert OnlyRouter();
        if (totalSupply() + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        _mint(to, amount);
    }
}
