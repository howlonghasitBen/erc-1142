// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISurfSwap.sol";
import "./interfaces/IGlobalRewards.sol";

/// @title WethPool — WETH LP staking with share-based proportional withdrawal
/// @author Whirlpool Team
/// @notice Stake WETH as liquidity for the WAVES ↔ WETH pool. Earn swap fees + 1.5x boosted mint fees.
/// @dev Share-based: unstaking returns proportional WETH + WAVES from both sides of the pool.
///      This is standard Uniswap-style dual-token LP withdrawal.
contract WethPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant WETH_BOOST = 15; // 1.5x = 15/10
    uint256 private constant ACC_PRECISION = 1e18;

    // ─── Immutable refs ─────────────────────────────────────────
    address public immutable waves;
    address public immutable weth;
    address public immutable surfSwap;
    IGlobalRewards public immutable globalRewards;

    // ─── WETH staking (share-based) ────────────────────────────
    uint256 public totalWethShares;
    uint256 public totalWethDeposited;
    uint256 public accWavesPerWethShare;
    mapping(address => uint256) public userWethShares;
    mapping(address => uint256) public userWethDebt;

    // ─── Events ─────────────────────────────────────────────────
    event WETHStaked(address indexed user, uint256 amount);
    event WETHUnstaked(address indexed user, uint256 wethAmount);

    constructor(address _waves, address _weth, address _surfSwap, address _globalRewards) {
        waves = _waves;
        weth = _weth;
        surfSwap = _surfSwap;
        globalRewards = IGlobalRewards(_globalRewards);
    }

    // ═══════════════════════════════════════════════════════════
    //                    STAKING
    // ═══════════════════════════════════════════════════════════

    /// @notice Stake WETH to earn swap fees and 1.5x boosted global mint fee rewards
    /// @param amount WETH to stake (must approve WethPool first)
    function stakeWETH(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        IERC20(weth).safeTransferFrom(msg.sender, address(this), amount);

        // Harvest WETH swap rewards
        if (userWethShares[msg.sender] > 0) {
            uint256 pending = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
            if (pending > 0) {
                IERC20(waves).safeTransfer(msg.sender, pending);
            }
        }

        // Harvest global
        globalRewards.harvestGlobal(msg.sender);

        // Calculate shares proportional to pool value
        uint256 actualWeth = _poolWethBalance();
        uint256 sharesToMint;
        if (totalWethShares == 0 || actualWeth == 0) {
            sharesToMint = amount;
        } else {
            sharesToMint = amount * totalWethShares / actualWeth;
        }
        require(sharesToMint > 0, "Zero shares");

        userWethShares[msg.sender] += sharesToMint;
        totalWethShares += sharesToMint;
        totalWethDeposited += amount;

        // WETH stakers get 1.5x global weight
        uint256 weightAdded = sharesToMint * WETH_BOOST / 10;
        globalRewards.addWeight(msg.sender, weightAdded);

        // Transfer WETH to SurfSwap for actual liquidity
        IERC20(weth).approve(surfSwap, amount);
        IERC20(weth).safeTransfer(surfSwap, amount);
        ISurfSwap(surfSwap).addToWethReserve(amount);

        userWethDebt[msg.sender] = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION;

        emit WETHStaked(msg.sender, amount);
    }

    /// @notice Unstake WETH shares and withdraw proportional WETH + WAVES from the pool
    /// @param shares Number of shares to unstake
    function unstakeWETH(uint256 shares) external nonReentrant {
        require(shares > 0, "Zero shares");
        require(userWethShares[msg.sender] >= shares, "Insufficient shares");

        // Harvest WETH swap rewards
        uint256 pending = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }

        // Harvest global
        globalRewards.harvestGlobal(msg.sender);

        // Calculate proportional share of BOTH sides of the pool
        (uint256 wavesReserve, uint256 wethReserve) = ISurfSwap(surfSwap).getWethReserves();
        uint256 wethOut = shares * wethReserve / totalWethShares;
        uint256 wavesOut = shares * wavesReserve / totalWethShares;

        userWethShares[msg.sender] -= shares;
        totalWethShares -= shares;

        // Remove 1.5x global weight
        uint256 weightRemoved = shares * WETH_BOOST / 10;
        globalRewards.removeWeight(msg.sender, weightRemoved);

        // Pull both tokens from SurfSwap
        if (wethOut > 0) {
            ISurfSwap(surfSwap).removeFromWethReserve(wethOut);
        }
        if (wavesOut > 0) {
            ISurfSwap(surfSwap).removeFromWavesWethReserve(wavesOut);
        }

        userWethDebt[msg.sender] = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION;

        // Transfer both tokens to user
        if (wethOut > 0) {
            IERC20(weth).safeTransfer(msg.sender, wethOut);
        }
        if (wavesOut > 0) {
            IERC20(waves).safeTransfer(msg.sender, wavesOut);
        }

        emit WETHUnstaked(msg.sender, wethOut);
    }

    // ═══════════════════════════════════════════════════════════
    //                    REWARDS
    // ═══════════════════════════════════════════════════════════

    /// @notice Claim pending WAVES rewards from WETH swap fees and global mint fees
    function claimWETHRewards() external nonReentrant {
        uint256 pending = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION - userWethDebt[msg.sender];
        if (pending > 0) {
            IERC20(waves).safeTransfer(msg.sender, pending);
        }
        userWethDebt[msg.sender] = userWethShares[msg.sender] * accWavesPerWethShare / ACC_PRECISION;

        // Also harvest global
        globalRewards.harvestGlobal(msg.sender);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════

    /// @notice Distribute WAVES swap fees to WETH stakers
    function distributeWethSwapFees(uint256 wavesFee) external {
        require(msg.sender == surfSwap, "Only SurfSwap");
        if (totalWethShares > 0 && wavesFee > 0) {
            accWavesPerWethShare += wavesFee * ACC_PRECISION / totalWethShares;
        }
    }

    // ═══════════════════════════════════════════════════════════
    //                    VIEWS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get the actual WETH a user could withdraw based on their shares
    function claimableWeth(address user) external view returns (uint256) {
        if (totalWethShares == 0 || userWethShares[user] == 0) return 0;
        return userWethShares[user] * _poolWethBalance() / totalWethShares;
    }

    /// @notice Get both claimable WETH and WAVES for a user's shares
    function claimableWethPool(address user) external view returns (uint256 wethAmount, uint256 wavesAmount) {
        if (totalWethShares == 0 || userWethShares[user] == 0) return (0, 0);
        (uint256 wavesR, uint256 wethR) = ISurfSwap(surfSwap).getWethReserves();
        wethAmount = userWethShares[user] * wethR / totalWethShares;
        wavesAmount = userWethShares[user] * wavesR / totalWethShares;
    }

    /// @notice Backward-compatible alias: returns user's shares
    function userWethStake(address user) external view returns (uint256) {
        return userWethShares[user];
    }

    function _poolWethBalance() internal view returns (uint256) {
        return IERC20(weth).balanceOf(surfSwap);
    }
}
