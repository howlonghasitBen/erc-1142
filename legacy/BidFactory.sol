// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BidNFT.sol";
import "./BidToken.sol";
import "./interfaces/IBidFactory.sol";

/// @title BidFactory
/// @notice Deploys BidToken + creates Uniswap V3 pools for ERC-1142 cards
contract BidFactory is IBidFactory {
    BidNFT public immutable bidNFT_;
    address public immutable override wavesToken;
    
    /// @notice Get the BidNFT contract address
    function bidNFT() external view override returns (address) {
        return address(bidNFT_);
    }
    address public immutable uniswapFactory;
    address public immutable positionManager;
    
    uint24 public constant FEE_TIER = 3000; // 0.30%
    int24 public constant MIN_TICK = -887220;
    int24 public constant MAX_TICK = 887220;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    mapping(uint256 => address) public pools;
    mapping(uint256 => address) public bidTokens;

    constructor(
        address bidNFTAddr_,
        address wavesToken_,
        address uniswapFactory_,
        address positionManager_
    ) {
        bidNFT_ = BidNFT(bidNFTAddr_);
        wavesToken = wavesToken_;
        uniswapFactory = uniswapFactory_;
        positionManager = positionManager_;
    }

    /// @notice Create a new card with paired token and Uniswap liquidity
    function createCard(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        string calldata tokenURI
    ) external payable override returns (
        uint256 tokenId,
        address bidTokenAddr,
        address pool
    ) {
        require(msg.value > 0, "Must send ETH for liquidity");

        // 1. Get next token ID
        tokenId = bidNFT_.nextTokenId();

        // 2. Deploy BidToken
        BidToken newToken = new BidToken(
            name,
            symbol,
            address(bidNFT_),
            tokenId,
            totalSupply,
            address(this),  // Mint to factory first
            msg.sender      // Creator is initial topHolder
        );
        bidTokenAddr = address(newToken);
        bidTokens[tokenId] = bidTokenAddr;

        // 3. Mint NFT entry
        bidNFT_.mint(msg.sender, bidTokenAddr, tokenURI);

        // 4. Create and seed Uniswap V3 pool
        pool = _createAndSeedPool(bidTokenAddr, totalSupply, msg.value);
        pools[tokenId] = pool;

        emit CardCreated(tokenId, bidTokenAddr, pool, msg.sender);
    }

    /// @notice Create Uniswap V3 pool and add liquidity
    function _createAndSeedPool(
        address bidTokenAddr,
        uint256 tokenAmount,
        uint256 wavesAmount
    ) internal returns (address pool) {
        // Sort tokens
        (address token0, address token1) = wavesToken < bidTokenAddr 
            ? (wavesToken, bidTokenAddr) 
            : (bidTokenAddr, wavesToken);
        
        bool wavesIsToken0 = token0 == wavesToken;
        
        // Create pool
        pool = IUniswapV3Factory(uniswapFactory).createPool(token0, token1, FEE_TIER);
        
        // Calculate initial sqrt price
        uint160 sqrtPriceX96 = _calculateSqrtPrice(wavesAmount, tokenAmount, wavesIsToken0);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        // Approve tokens
        IERC20(wavesToken).approve(positionManager, wavesAmount);
        IERC20(bidTokenAddr).approve(positionManager, tokenAmount);

        // Add full-range liquidity
        (uint256 lpTokenId,,,) = INonfungiblePositionManager(positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE_TIER,
                tickLower: MIN_TICK,
                tickUpper: MAX_TICK,
                amount0Desired: wavesIsToken0 ? wavesAmount : tokenAmount,
                amount1Desired: wavesIsToken0 ? tokenAmount : wavesAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Burn LP position (permanent liquidity)
        INonfungiblePositionManager(positionManager).transferFrom(
            address(this), 
            BURN_ADDRESS, 
            lpTokenId
        );
    }

    /// @notice Calculate sqrt price for Uniswap V3 pool initialization
    function _calculateSqrtPrice(
        uint256 wavesAmount,
        uint256 tokenAmount,
        bool wavesIsToken0
    ) internal pure returns (uint160) {
        // price = token1 / token0
        uint256 price;
        if (wavesIsToken0) {
            // price = tokenAmount / wavesAmount (how many tokens per WAVES)
            price = (tokenAmount * 1e18) / wavesAmount;
        } else {
            // price = wavesAmount / tokenAmount (how many WAVES per token)
            price = (wavesAmount * 1e18) / tokenAmount;
        }
        
        uint256 sqrtPrice = _sqrt(price * 1e18); // sqrt with 18 decimals
        return uint160((sqrtPrice << 96) / 1e18);
    }

    /// @notice Babylonian sqrt
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /// @notice Get the Uniswap pool for a token ID
    function getPool(uint256 tokenId) external view override returns (address) {
        return pools[tokenId];
    }

    /// @notice Get the BidToken for a token ID
    function getBidToken(uint256 tokenId) external view returns (address) {
        return bidTokens[tokenId];
    }

    /// @notice Receive WAVES (needed for liquidity seeding)
    receive() external payable {}
}

// ============ Uniswap V3 Interfaces ============

interface IUniswapV3Factory {
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function transferFrom(address from, address to, uint256 tokenId) external;
}
