// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title WAVES — Hub token for the Whirlpool AMM ecosystem
/// @author Whirlpool Team
/// @notice ERC-20 token with 10M max supply, exclusively mintable by the WhirlpoolRouter.
///         WAVES serves as the routing hub: all card ↔ card swaps pass through WAVES.
///         2,000 WAVES are minted per card creation (500 to AMM, 1500 to minter).
/// @dev No burn function. No admin. Supply capped at MAX_SUPPLY via mint() check.
contract WAVES is ERC20 {
    /// @notice Maximum total supply (10 million tokens with 18 decimals)
    uint256 public constant MAX_SUPPLY = 10_000_000 ether;

    /// @notice WhirlpoolRouter address (only address allowed to mint)
    address public immutable router;

    /// @notice Thrown when a non-router address attempts to mint
    error OnlyRouter();
    /// @notice Thrown when mint would exceed MAX_SUPPLY
    error ExceedsMaxSupply();

    /// @param router_ WhirlpoolRouter contract address (set at deployment, immutable)
    constructor(address router_) ERC20("WAVES", "WAVES") {
        router = router_;
    }

    /// @notice Mint new WAVES tokens (only callable by Router during card creation)
    /// @dev Reverts with OnlyRouter if caller is not the router.
    ///      Reverts with ExceedsMaxSupply if totalSupply + amount > MAX_SUPPLY.
    /// @param to Recipient address
    /// @param amount Number of tokens to mint (18 decimals)
    function mint(address to, uint256 amount) external {
        if (msg.sender != router) revert OnlyRouter();
        if (totalSupply() + amount > MAX_SUPPLY) revert ExceedsMaxSupply();
        _mint(to, amount);
    }
}
