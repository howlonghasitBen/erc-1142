// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IWhirlpool — Interface for WhirlpoolStaking (LP staking, ownership, fees)
/// @notice Defines staking, fee distribution, and ownership query functions
interface IWhirlpool {
    /// @notice Stake card tokens to earn fees and compete for NFT ownership
    /// @param cardId Card identifier
    /// @param amount Card tokens to stake
    function stake(uint256 cardId, uint256 amount) external;

    /// @notice Unstake LP shares and withdraw proportional card tokens
    /// @param cardId Card identifier
    /// @param amount LP shares to burn
    function unstake(uint256 cardId, uint256 amount) external;

    /// @notice Stake WETH for 1.5x boosted rewards
    /// @param amount WETH to stake
    function stakeWETH(uint256 amount) external;

    /// @notice Unstake WETH
    /// @param amount WETH to unstake
    function unstakeWETH(uint256 amount) external;

    /// @notice Distribute ETH mint fee to all stakers (called by Router)
    function distributeMintFee() external payable;

    /// @notice Distribute WAVES swap fees to card stakers (called by SurfSwap)
    /// @param cardId Card identifier
    /// @param wavesFee WAVES fee amount
    function distributeSwapFees(uint256 cardId, uint256 wavesFee) external;

    /// @notice Distribute WAVES swap fees to WETH stakers (called by SurfSwap)
    /// @param wavesFee WAVES fee amount
    function distributeWethSwapFees(uint256 wavesFee) external;

    /// @notice Register a new card token (called by Router during creation)
    /// @param cardId Card identifier
    /// @param token Card token address
    function registerCard(uint256 cardId, address token) external;

    /// @notice Auto-stake tokens for user during card creation (called by Router)
    /// @param cardId Card identifier
    /// @param user Address receiving LP shares
    /// @param amount Tokens to auto-stake
    function autoStake(uint256 cardId, address user, uint256 amount) external;

    /// @notice Get the current NFT owner (biggest LP shareholder)
    /// @param cardId Card identifier
    /// @return Owner address
    function ownerOfCard(uint256 cardId) external view returns (address);

    /// @notice Get user's LP shares for a card
    /// @param cardId Card identifier
    /// @param user Address to query
    /// @return Share count
    function stakeOf(uint256 cardId, address user) external view returns (uint256);

    /// @notice Get pending WAVES rewards from card swap fees
    /// @param cardId Card identifier
    /// @param user Address to query
    /// @return Pending reward amount
    function pendingRewards(uint256 cardId, address user) external view returns (uint256);

    /// @notice Get pending ETH rewards from global mint fee distribution
    /// @param user Address to query
    /// @return Pending reward amount
    function pendingGlobalRewards(address user) external view returns (uint256);
}
