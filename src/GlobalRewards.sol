// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GlobalRewards — Central weight registry + ETH mint fee distribution hub
/// @author Whirlpool Team
/// @notice Manages weighted ETH distribution to all staking contracts (CardStaking, WethPool, etc.)
/// @dev MasterChef-style O(1) accumulator. Staking contracts register/remove weight on behalf of users.
///      Any new staking type can plug in by being registered as an operator.
contract GlobalRewards {
    uint256 private constant ACC_PRECISION = 1e18;

    // ─── State ──────────────────────────────────────────────────
    uint256 public accEthPerWeight;
    uint256 public totalGlobalWeight;
    mapping(address => uint256) public userGlobalWeight;
    mapping(address => uint256) public userGlobalDebt;

    // ─── Auth ───────────────────────────────────────────────────
    address public immutable deployer;
    mapping(address => bool) public isOperator;

    // ─── Events ─────────────────────────────────────────────────
    event MintFeeDistributed(uint256 amount);
    event OperatorRegistered(address indexed operator);

    constructor() {
        deployer = msg.sender;
    }

    /// @notice Register a staking contract as an operator (one-time setup by deployer)
    function registerOperator(address operator) external {
        require(msg.sender == deployer, "Only deployer");
        isOperator[operator] = true;
        emit OperatorRegistered(operator);
    }

    modifier onlyOperator() {
        require(isOperator[msg.sender], "Not operator");
        _;
    }

    // ═══════════════════════════════════════════════════════════
    //                    OPERATOR FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// @notice Add global weight for a user (called by staking contracts on stake)
    /// @param user Address to add weight for
    /// @param weight Amount of weight to add
    function addWeight(address user, uint256 weight) external onlyOperator {
        userGlobalWeight[user] += weight;
        totalGlobalWeight += weight;
        userGlobalDebt[user] = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION;
    }

    /// @notice Remove global weight for a user (called by staking contracts on unstake)
    /// @param user Address to remove weight from
    /// @param weight Amount of weight to remove
    function removeWeight(address user, uint256 weight) external onlyOperator {
        userGlobalWeight[user] -= weight;
        totalGlobalWeight -= weight;
        userGlobalDebt[user] = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION;
    }

    /// @notice Harvest pending ETH rewards for a user (called by staking contracts before weight changes)
    /// @param user Address to harvest for
    function harvestGlobal(address user) external onlyOperator {
        _harvest(user);
    }

    // ═══════════════════════════════════════════════════════════
    //                    FEE DISTRIBUTION
    // ═══════════════════════════════════════════════════════════

    /// @notice Distribute ETH mint fee to all stakers weighted by global weight
    /// @dev Called by WhirlpoolRouter when a card is minted (sends ETH with call)
    function distributeMintFee() external payable {
        if (totalGlobalWeight > 0 && msg.value > 0) {
            accEthPerWeight += msg.value * ACC_PRECISION / totalGlobalWeight;
        }
        emit MintFeeDistributed(msg.value);
    }

    // ═══════════════════════════════════════════════════════════
    //                    VIEWS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get pending ETH rewards from global mint fee distribution
    /// @param user Address to query
    /// @return Pending ETH reward amount
    function pendingGlobalRewards(address user) external view returns (uint256) {
        if (userGlobalWeight[user] == 0) return 0;
        return userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION - userGlobalDebt[user];
    }

    // ═══════════════════════════════════════════════════════════
    //                    INTERNAL
    // ═══════════════════════════════════════════════════════════

    function _harvest(address user) internal {
        if (userGlobalWeight[user] > 0) {
            uint256 pending = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION - userGlobalDebt[user];
            if (pending > 0) {
                (bool ok,) = user.call{value: pending}("");
                require(ok, "ETH transfer failed");
            }
            userGlobalDebt[user] = userGlobalWeight[user] * accEthPerWeight / ACC_PRECISION;
        }
    }

    // Allow receiving ETH
    receive() external payable {}
}
