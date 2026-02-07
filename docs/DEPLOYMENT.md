# Deployment Guide

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Node.js 16+ (optional, for frontend)
- Wallet with ETH for gas (mainnet/testnet)
- RPC endpoint (Alchemy, Infura, or local node)

## Local Development (Anvil)

### Quick Start

```bash
bash launch-dev.sh
```

This script:
1. Kills existing Anvil instance (if any)
2. Starts Anvil on port 8545
3. Deploys all contracts
4. Creates 2 example cards
5. Prints contract addresses
6. (Optional) Launches frontend

### Manual Local Deployment

```bash
# Terminal 1: Start Anvil
anvil

# Terminal 2: Deploy
forge script script/LocalDeploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

**Deployed addresses** are printed to console and saved to:
```
broadcast/LocalDeploy.s.sol/31337/run-latest.json
```

### Verification

Test deployment with Foundry's cast:

```bash
# Get WAVES address from deployment output
export WAVES_ADDR=0x5FbDB2315678afecb367f032d93F642f64180aa3

# Check total supply (should be 0 initially)
cast call $WAVES_ADDR "totalSupply()" --rpc-url http://localhost:8545
```

## Testnet Deployment (Sepolia)

### 1. Setup Environment

Create `.env` file:

```bash
# .env
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_KEY
```

**⚠️ Security**: Never commit `.env` to git!

### 2. Fund Your Address

Get Sepolia ETH from faucets:
- https://sepoliafaucet.com/
- https://www.infura.io/faucet/sepolia

You need ~0.1 ETH for deployment + testing.

### 3. Deploy Script

```bash
forge script script/SepoliaDeploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

**Note**: If contract size exceeds 24KB, you'll get:
```
Error: contract code size exceeds 24576 bytes
```

See [REVIEW.md](REVIEW.md) for mitigation (--code-size-limit flag).

### 4. Verify Contracts

If `--verify` fails during deployment, manually verify:

```bash
forge verify-contract \
  --chain sepolia \
  --compiler-version v0.8.20 \
  --num-of-optimizations 200 \
  0xYOUR_CONTRACT_ADDRESS \
  src/WhirlpoolRouter.sol:WhirlpoolRouter \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" $WAVES $BIDNFT $SURFSWAP $WHIRLPOOL $WETH $PROTOCOL) \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 5. Test Deployment

Create a test card:

```bash
# Get router address from deployment
export ROUTER=0xYOUR_ROUTER_ADDRESS

# Create card (0.05 ETH)
cast send $ROUTER \
  "createCard(string,string,string)" \
  "TestCard" \
  "TEST" \
  "ipfs://QmTest" \
  --value 0.05ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

Check card created:

```bash
cast call $ROUTER "totalCards()" --rpc-url $SEPOLIA_RPC_URL
# Should return: 1
```

## Mainnet Deployment

⚠️ **DANGER ZONE**: Contracts are immutable. No undo.

### Pre-Deployment Checklist

- [ ] All tests pass (`forge test`)
- [ ] Contract sizes under 24KB (`forge build --sizes`)
- [ ] Audited by reputable firm
- [ ] Bug bounty program launched
- [ ] Multisig ready for protocol address
- [ ] Sufficient ETH for deployment (~0.5 ETH)
- [ ] Deployer address has no prior nonce (for clean prediction)
- [ ] Etherscan API key ready for verification

### Deployment Steps

1. **Setup Production .env**

```bash
# .env.mainnet
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY
MAINNET_PRIVATE_KEY=0xYOUR_DEPLOYMENT_KEY
ETHERSCAN_API_KEY=YOUR_KEY
PROTOCOL_ADDRESS=0xYOUR_MULTISIG_OR_DAO
```

2. **Dry Run**

```bash
forge script script/MainnetDeploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $MAINNET_PRIVATE_KEY \
  --slow \
  -vvvv
```

Review the output carefully. Check:
- Gas estimates
- Predicted addresses
- Constructor arguments

3. **Deploy**

```bash
forge script script/MainnetDeploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $MAINNET_PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --slow \
  -vvvv
```

**Flags**:
- `--slow`: 3s delay between transactions (prevents nonce issues)
- `-vvvv`: Max verbosity
- `--broadcast`: Actually send transactions (remove for simulation)

4. **Save Addresses**

```bash
# Extract from broadcast/MainnetDeploy.s.sol/1/run-latest.json
export WAVES_MAINNET=0x...
export ROUTER_MAINNET=0x...
export SURFSWAP_MAINNET=0x...
export WHIRLPOOL_MAINNET=0x...
export BIDNFT_MAINNET=0x...

# Save to file
echo "WAVES=$WAVES_MAINNET" >> deployed-mainnet.txt
# ... repeat for all contracts
```

5. **Verify All Contracts**

```bash
forge verify-contract --chain mainnet ... # (see Sepolia example)
```

6. **Post-Deployment Verification**

```bash
# Check contract code matches
forge verify-check --chain mainnet 0xYOUR_ADDRESS

# Create test card (0.05 ETH + gas)
cast send $ROUTER_MAINNET "createCard(string,string,string)" \
  "Genesis" "GEN" "ipfs://..." \
  --value 0.05ether \
  --private-key $TEST_USER_KEY \
  --rpc-url $MAINNET_RPC_URL

# Verify card created
cast call $ROUTER_MAINNET "totalCards()" --rpc-url $MAINNET_RPC_URL
# Should return: 1
```

## Address Prediction Pattern

Whirlpool uses CREATE opcode address prediction to solve circular dependencies.

### How It Works

```solidity
// In deployment script:
uint256 nonce = vm.getNonce(deployer);

// Predict addresses based on future nonces
address predictedRouter = vm.computeCreateAddress(deployer, nonce + 4);
address predictedWhirlpool = vm.computeCreateAddress(deployer, nonce + 2);
address predictedSurfSwap = vm.computeCreateAddress(deployer, nonce + 1);

// Deploy in order:
WAVES waves = new WAVES(predictedRouter);          // nonce+0
SurfSwap surfSwap = new SurfSwap(..., predictedWhirlpool, predictedRouter); // nonce+1
WhirlpoolStaking whirlpool = new WhirlpoolStaking(..., predictedRouter);   // nonce+2
BidNFT bidNFT = new BidNFT(whirlpool, predictedRouter);                    // nonce+3
WhirlpoolRouter router = new WhirlpoolRouter(...);                          // nonce+4

// Verify predictions matched
assert(address(router) == predictedRouter);
```

### Why This Pattern?

**Problem**: Router needs WAVES address, WAVES needs Router address → circular dependency.

**Solution**: Predict Router's address before deploying it, use predicted address in WAVES constructor.

**Requirement**: Deploy sequence must be **exactly** as predicted. Any extra transaction breaks it.

### Risks

1. **Nonce mismatch**: If deployer sends any transaction between prediction and deployment, addresses shift.
2. **Out-of-gas**: If one deployment fails midway, nonce is consumed but contract not deployed.
3. **CREATE2 alternative**: Could use CREATE2 for deterministic addresses (no nonce dependency), but adds complexity.

**Mitigation**: Use fresh deployer address with known starting nonce (usually 0).

## Post-Deployment Setup

### 1. Initialize Frontend

```bash
cd frontend
npm install
npm run build

# Update contract addresses
cat > src/config.js << EOF
export const ROUTER_ADDRESS = "$ROUTER_MAINNET"
export const WAVES_ADDRESS = "$WAVES_MAINNET"
export const SURFSWAP_ADDRESS = "$SURFSWAP_MAINNET"
export const WHIRLPOOL_ADDRESS = "$WHIRLPOOL_MAINNET"
export const BIDNFT_ADDRESS = "$BIDNFT_MAINNET"
EOF

# Deploy to hosting (Vercel, Netlify, etc.)
vercel --prod
```

### 2. Create Initial Cards

Seed the system with interesting cards to bootstrap liquidity:

```bash
./scripts/create-initial-cards.sh
```

### 3. Monitor

Set up monitoring:
- Block explorer (Etherscan)
- TVL tracking
- Fee distribution analytics
- Gas costs

### 4. Announce

- Tweet contract addresses
- Update README with mainnet addresses
- Update docs site
- Post on forums (Discord, Reddit, etc.)

## Upgrading / Migration

**You can't.** Contracts are immutable.

If bugs are found:
1. Deploy new version of entire system
2. Announce migration plan
3. Users must manually move funds
4. Old system continues operating (or drains naturally)

This is **intentional** for trustlessness.

## Gas Optimization for Deployment

### Current Gas Costs (Sepolia)

| Contract | Gas | ETH @ 50 gwei |
|----------|-----|---------------|
| WAVES | ~500K | 0.025 ETH |
| SurfSwap | ~3.5M | 0.175 ETH |
| WhirlpoolStaking | ~4.2M | 0.210 ETH |
| BidNFT | ~1.2M | 0.060 ETH |
| WhirlpoolRouter | ~3.8M | 0.190 ETH |
| **Total** | ~13.2M | **0.66 ETH** |

At mainnet gas prices (100 gwei), expect **1.32 ETH** (~$2,640 @ $2K/ETH).

### Size Optimization

If contract exceeds 24KB:

1. **Enable optimizer** (already done):
   ```toml
   [profile.default]
   optimizer = true
   optimizer_runs = 200
   ```

2. **Increase optimizer_runs** (trades deployment cost for runtime cost):
   ```toml
   optimizer_runs = 1000  # More expensive deploy, cheaper execution
   ```

3. **Use --code-size-limit** (local only):
   ```toml
   code_size_limit = 30000
   ```

4. **Refactor large contracts**:
   - Extract view functions to libraries
   - Remove error strings
   - Combine small functions

See [REVIEW.md](REVIEW.md) for current size issues.

## Troubleshooting

### "Contract code size exceeds 24576 bytes"

**Cause**: SurfSwap or WhirlpoolStaking too large.

**Fix**: Refactor or use yul optimizations (see REVIEW.md).

### "Nonce too low"

**Cause**: Deployer sent transaction between prediction and deployment.

**Fix**: Use fresh address or recalculate predictions.

### "Failed to verify contract"

**Cause**: Constructor args mismatch or bytecode mismatch.

**Fix**:
```bash
# Get exact constructor args from deployment transaction
cast tx $TX_HASH --rpc-url $RPC_URL

# Manually verify with exact args
forge verify-contract ... --constructor-args $(cast abi-encode "...")
```

### "Out of gas"

**Cause**: Gas limit too low or contract too large.

**Fix**: Increase gas limit in script:
```solidity
vm.broadcast{gas: 10_000_000}();
```

## Next Steps

After deployment:
1. Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the system
2. Read [MECHANICS.md](MECHANICS.md) for math details
3. Read [REVIEW.md](REVIEW.md) for known issues
4. Monitor the system and gather feedback
5. (Optional) Deploy improved V2 after learning from V1

---

**Remember**: Deployment is permanent. Triple-check everything.
