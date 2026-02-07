// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./CardToken.sol";
import "./WAVES.sol";
import "./BidNFT.sol";
import "./interfaces/ISurfSwap.sol";
import "./interfaces/IWhirlpool.sol";

/// @title WhirlpoolRouter — Card creation orchestrator
/// @author Whirlpool Team
/// @notice Immutable entry point for creating new cards. Deploys CardToken, mints WAVES,
///         seeds AMM liquidity, auto-stakes minter's allocation, mints BidNFT, and distributes mint fees.
/// @dev All card creation logic is in createCard(). No admin functions. No upgradability.
///      Uses address prediction (CREATE opcode) to resolve circular dependencies at deployment.
contract WhirlpoolRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ───────────────────────────────────────────────
    uint256 public constant MAX_CARDS = 5000;
    uint256 public constant MINT_FEE = 0.05 ether;
    uint256 public constant WAVES_PER_CARD = 2000 ether;
    uint256 public constant CARD_SUPPLY = 10_000_000 ether;

    // ─── Distribution ratios (WAVES) ────────────────────────────
    uint256 private constant WAVES_AMM_PCT = 25;   // 500 WAVES
    uint256 private constant WAVES_MINTER_PCT = 75; // 1500 WAVES

    // ─── Distribution ratios (CARD) ─────────────────────────────
    uint256 private constant CARD_AMM_PCT = 75;     // 7.5M
    uint256 private constant CARD_MINTER_PCT = 20;  // 2M
    uint256 private constant CARD_PROTOCOL_PCT = 5;  // 500K

    // ─── Immutable refs ─────────────────────────────────────────
    WAVES public immutable waves;
    BidNFT public immutable bidNFT;
    ISurfSwap public immutable surfSwap;
    IWhirlpool public immutable whirlpool;
    address public immutable weth;
    address public immutable protocol;

    // ─── Card registry ──────────────────────────────────────────
    uint256 public totalCards_;
    mapping(uint256 => address) public cardTokens;

    // ─── Events ─────────────────────────────────────────────────
    event CardCreated(uint256 indexed cardId, address indexed minter, address cardToken, uint256 wavesSeeded);

    // ─── Constructor ────────────────────────────────────────────
    constructor(
        address waves_,
        address bidNFT_,
        address surfSwap_,
        address whirlpool_,
        address weth_,
        address protocol_
    ) {
        waves = WAVES(waves_);
        bidNFT = BidNFT(bidNFT_);
        surfSwap = ISurfSwap(surfSwap_);
        whirlpool = IWhirlpool(whirlpool_);
        weth = weth_;
        protocol = protocol_;
    }

    // ═══════════════════════════════════════════════════════════
    //                     CARD CREATION
    // ═══════════════════════════════════════════════════════════

    /// @notice Create a new card: deploy token, seed AMM, auto-stake, mint NFT
    /// @dev Full creation flow in 9 steps (see inline comments). Costs exactly MINT_FEE (0.05 ETH).
    ///      Minter receives 1500 WAVES + 2M auto-staked tokens (becomes initial NFT owner).
    /// @param name Card token name (e.g., "Fire Dragon")
    /// @param symbol Card token symbol (e.g., "FDRAGON")
    /// @param tokenURI Metadata URI for the BidNFT (e.g., IPFS hash)
    /// @return cardId The unique identifier for the newly created card
    function createCard(
        string calldata name,
        string calldata symbol,
        string calldata tokenURI
    ) external payable nonReentrant returns (uint256 cardId) {
        require(msg.value == MINT_FEE, "Exact mint fee required");
        require(totalCards_ < MAX_CARDS, "Max cards reached");

        cardId = totalCards_++;

        // 1. Deploy card token — entire supply minted to this contract
        CardToken ct = new CardToken(name, symbol, address(this), CARD_SUPPLY);
        address cardAddr = address(ct);
        cardTokens[cardId] = cardAddr;

        // 2. Mint WAVES
        uint256 wavesToAmm = WAVES_PER_CARD * WAVES_AMM_PCT / 100;
        uint256 wavesToMinter = WAVES_PER_CARD * WAVES_MINTER_PCT / 100;
        waves.mint(address(this), wavesToAmm);
        waves.mint(msg.sender, wavesToMinter);

        // 3. Calculate card token distributions
        uint256 cardsToAmm = CARD_SUPPLY * CARD_AMM_PCT / 100;
        uint256 cardsToMinter = CARD_SUPPLY * CARD_MINTER_PCT / 100;
        uint256 cardsToProtocol = CARD_SUPPLY * CARD_PROTOCOL_PCT / 100;

        // 4. Transfer protocol share
        IERC20(cardAddr).safeTransfer(protocol, cardsToProtocol);

        // 5. Register card in Whirlpool
        whirlpool.registerCard(cardId, cardAddr);

        // 6. Initialize pool on SurfSwap
        IERC20(address(waves)).approve(address(surfSwap), wavesToAmm);
        IERC20(cardAddr).approve(address(surfSwap), cardsToAmm);
        surfSwap.initializePool(cardId, cardAddr, wavesToAmm, cardsToAmm);

        // 7. Auto-stake minter's share
        IERC20(cardAddr).approve(address(whirlpool), cardsToMinter);
        whirlpool.autoStake(cardId, msg.sender, cardsToMinter);

        // 8. Mint NFT
        bidNFT.mint(cardId, tokenURI);

        // 9. Distribute mint fee to global stakers
        whirlpool.distributeMintFee{value: MINT_FEE}();

        emit CardCreated(cardId, msg.sender, cardAddr, wavesToAmm);
    }

    // ═══════════════════════════════════════════════════════════
    //                       VIEWS
    // ═══════════════════════════════════════════════════════════

    /// @notice Get total number of cards created
    /// @return Total card count
    function totalCards() external view returns (uint256) {
        return totalCards_;
    }

    /// @notice Get the ERC-20 token address for a given card
    /// @param cardId Card identifier
    /// @return Card token contract address
    function cardToken(uint256 cardId) external view returns (address) {
        return cardTokens[cardId];
    }
}
