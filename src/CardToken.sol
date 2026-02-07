// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title CardToken — Fixed-supply ERC-20 minted once by WhirlpoolRouter
/// @author Whirlpool Team
/// @notice Each card in the Whirlpool system has its own CardToken (10M supply).
///         The entire supply is minted to the Router at creation, then distributed:
///         75% → AMM pool, 20% → auto-staked for minter, 5% → protocol treasury.
/// @dev No mint/burn functions beyond constructor. Standard ERC-20 with fixed supply.
contract CardToken is ERC20 {
    /// @notice Deploy a new card token with fixed supply
    /// @param name_ Token name (e.g., "Fire Dragon")
    /// @param symbol_ Token symbol (e.g., "FDRAGON")
    /// @param mintTo Address receiving entire supply (WhirlpoolRouter)
    /// @param supply Total token supply (typically 10,000,000 ether)
    constructor(
        string memory name_,
        string memory symbol_,
        address mintTo,
        uint256 supply
    ) ERC20(name_, symbol_) {
        _mint(mintTo, supply);
    }
}
