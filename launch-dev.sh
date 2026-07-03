#!/usr/bin/env bash
# ═══════════════════════════════════════════════════
# ERC-1142 / Whirlpool AMM — Local Dev Launcher
# Starts Anvil, deploys contracts, launches frontend
# ═══════════════════════════════════════════════════
set -e

export PATH="$HOME/.foundry/bin:$PATH"
PROJECT="$HOME/Projects/erc-1142"
cd "$PROJECT"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  ERC-1142 / Whirlpool AMM — Local Dev Suite${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# ─── Kill existing processes ───
echo -e "${YELLOW}Cleaning up old processes...${NC}"
pkill -f "anvil --host" 2>/dev/null || true
pkill -f "vite.*erc-1142" 2>/dev/null || true
pkill -f "vite.*5174" 2>/dev/null || true
pkill -f "node.*cog-works" 2>/dev/null || true
sleep 1

# ─── Run tests ───
echo -e "${YELLOW}Running tests...${NC}"
FORGE_OUT=$(forge test 2>&1)
PASSED=$(echo "$FORGE_OUT" | grep -c "\[PASS\]" || true)
FAILED=$(echo "$FORGE_OUT" | grep -c "\[FAIL" || true)

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Tests: ${PASSED} passed, ${FAILED} failed${NC}"
    echo "$FORGE_OUT" | grep "\[FAIL" | while read -r line; do
        echo -e "  ${RED}$line${NC}"
    done
    echo ""
    echo -e "${YELLOW}Continuing with deployment anyway...${NC}"
else
    echo -e "${GREEN}Tests: ${PASSED} passed, 0 failed ✓${NC}"
fi
echo ""

# ─── Start Anvil ───
echo -e "${YELLOW}Starting Anvil (Chain 31337)...${NC}"
anvil --host 0.0.0.0 --code-size-limit 50000 --gas-limit 30000000 \
    > /tmp/anvil-erc1142.log 2>&1 &
ANVIL_PID=$!
echo -e "${GREEN}Anvil PID: ${ANVIL_PID} (listening on 0.0.0.0:8545)${NC}"
sleep 2

# Check Anvil started
if ! kill -0 $ANVIL_PID 2>/dev/null; then
    echo -e "${RED}Anvil failed to start! Check /tmp/anvil-erc1142.log${NC}"
    exit 1
fi

# ─── Deploy Contracts ───
echo -e "${YELLOW}Deploying contracts...${NC}"
DEPLOY_OUT=$(forge script script/LocalDeploy.s.sol --tc LocalDeployScript \
    --rpc-url http://127.0.0.1:8545 --broadcast --code-size-limit 50000 2>&1)

if echo "$DEPLOY_OUT" | grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL"; then
    echo -e "${GREEN}Deployment successful ✓${NC}"
else
    echo -e "${RED}Deployment failed!${NC}"
    echo "$DEPLOY_OUT" | tail -10
    kill $ANVIL_PID 2>/dev/null
    exit 1
fi

# Extract addresses (Option B: 3-way split)
echo ""
echo -e "${CYAN}═══ Deployed Addresses ═══${NC}"
echo "$DEPLOY_OUT" | grep -E "^\s+(WETH|WAVES|GlobalRewards|SurfSwap|CardStaking|WethPool|BidNFT|Router)" | while read -r line; do
    echo -e "  ${GREEN}$line${NC}"
done

# Parse addresses from deploy output
WETH=$(echo "$DEPLOY_OUT" | grep "WETH:" | head -1 | awk '{print $NF}')
WAVES=$(echo "$DEPLOY_OUT" | grep "WAVES:" | head -1 | awk '{print $NF}')
GLOBAL_REWARDS=$(echo "$DEPLOY_OUT" | grep "GlobalRewards:" | awk '{print $NF}')
SURFSWAP=$(echo "$DEPLOY_OUT" | grep "SurfSwap:" | awk '{print $NF}')
CARD_STAKING=$(echo "$DEPLOY_OUT" | grep "CardStaking:" | awk '{print $NF}')
WETH_POOL=$(echo "$DEPLOY_OUT" | grep "WethPool:" | awk '{print $NF}')
BIDNFT=$(echo "$DEPLOY_OUT" | grep "BidNFT:" | awk '{print $NF}')
ROUTER=$(echo "$DEPLOY_OUT" | grep "Router:" | awk '{print $NF}')

for CONTRACTS_FILE in "$PROJECT/frontend/src/contracts.ts" "$HOME/Projects/cog-works/src/contracts/erc1142.ts"; do
  if [ -f "$CONTRACTS_FILE" ]; then
    # Map WHIRLPOOL_ADDRESS → CardStaking (backward compat — card staking functions)
    sed -i "s|WHIRLPOOL_ADDRESS = '0x[^']*'|WHIRLPOOL_ADDRESS = '${CARD_STAKING}'|" "$CONTRACTS_FILE"
    sed -i "s|WAVES_ADDRESS     = '0x[^']*'|WAVES_ADDRESS     = '${WAVES}'|" "$CONTRACTS_FILE"
    sed -i "s|BIDNFT_ADDRESS    = '0x[^']*'|BIDNFT_ADDRESS    = '${BIDNFT}'|" "$CONTRACTS_FILE"
    sed -i "s|WETH_ADDRESS      = '0x[^']*'|WETH_ADDRESS      = '${WETH}'|" "$CONTRACTS_FILE"
    sed -i "s|SURFSWAP_ADDRESS  = '0x[^']*'|SURFSWAP_ADDRESS  = '${SURFSWAP}'|" "$CONTRACTS_FILE"
    sed -i "s|ROUTER_ADDRESS    = '0x[^']*'|ROUTER_ADDRESS    = '${ROUTER}'|" "$CONTRACTS_FILE"
    # New Option B addresses (add if not present, update if present)
    if grep -q "CARD_STAKING_ADDRESS" "$CONTRACTS_FILE"; then
      sed -i "s|CARD_STAKING_ADDRESS = '0x[^']*'|CARD_STAKING_ADDRESS = '${CARD_STAKING}'|" "$CONTRACTS_FILE"
    else
      sed -i "/ROUTER_ADDRESS/a export const CARD_STAKING_ADDRESS = '${CARD_STAKING}' as const;" "$CONTRACTS_FILE"
    fi
    if grep -q "WETH_POOL_ADDRESS" "$CONTRACTS_FILE"; then
      sed -i "s|WETH_POOL_ADDRESS = '0x[^']*'|WETH_POOL_ADDRESS = '${WETH_POOL}'|" "$CONTRACTS_FILE"
    else
      sed -i "/CARD_STAKING_ADDRESS/a export const WETH_POOL_ADDRESS    = '${WETH_POOL}' as const;" "$CONTRACTS_FILE"
    fi
    if grep -q "GLOBAL_REWARDS_ADDRESS" "$CONTRACTS_FILE"; then
      sed -i "s|GLOBAL_REWARDS_ADDRESS = '0x[^']*'|GLOBAL_REWARDS_ADDRESS = '${GLOBAL_REWARDS}'|" "$CONTRACTS_FILE"
    else
      sed -i "/WETH_POOL_ADDRESS/a export const GLOBAL_REWARDS_ADDRESS = '${GLOBAL_REWARDS}' as const;" "$CONTRACTS_FILE"
    fi
    echo -e "${GREEN}Updated: $CONTRACTS_FILE ✓${NC}"
  fi
done

# ─── Generate Metadata & Mint Cards ───
echo ""
echo -e "${YELLOW}Generating ERC-721 metadata & minting all cards from cardData.json...${NC}"
echo -e "${CYAN}(First card will automatically seed the WETH pool with real WAVES — post-audit security fix)${NC}"
bash "$PROJECT/scripts/mint-all-cards.sh" "$ROUTER"

# ─── Verify WETH pool seed (new post-iteration check) ───
echo ""
echo -e "${YELLOW}Verifying WETH pool seeding...${NC}"
SEED_CHECK=$(cast call "$SURFSWAP" "isWethPoolSeeded()(bool)" --rpc-url http://127.0.0.1:8545 2>/dev/null || echo "false")
if [ "$SEED_CHECK" = "true" ]; then
  echo -e "${GREEN}✓ WETH pool is securely seeded (real WAVES backing)${NC}"
else
  echo -e "${YELLOW}⚠ WETH pool seed status: $SEED_CHECK (check manually if needed)${NC}"
fi
WETH_RESERVES=$(cast call "$SURFSWAP" "getWethReserves()(uint256,uint256)" --rpc-url http://127.0.0.1:8545 2>/dev/null || echo "0 0")
echo -e "  WETH Reserves: $WETH_RESERVES"

# ─── Start Internal Frontend (build + serve for robustness) ───
echo ""
echo -e "${YELLOW}Building and starting internal frontend...${NC}"
cd "$PROJECT/frontend"
npm run build 2>&1 | tail -3 || true
npx serve dist -l 5173 > /tmp/serve-internal.log 2>&1 &
VITE_PID=$!
sleep 2
echo -e "${GREEN}Internal frontend (static) PID: ${VITE_PID} on :5173${NC}"

# Detect actual port if using dev (fallback)
VITE_PORT=5173

# ─── Start cog-works Frontend (build + serve for env robustness) ───
COG_DIR="$HOME/Projects/cog-works"
if [ -d "$COG_DIR" ]; then
    echo -e "${YELLOW}Building + serving cog-works (paired frontend) on :5174...${NC}"
    cd "$COG_DIR"
    npm run build 2>&1 | tail -3 || true
    npx serve dist -l 5174 > /tmp/serve-cogworks.log 2>&1 &
    COG_PID=$!
    sleep 2
    echo -e "${GREEN}cog-works (static) PID: ${COG_PID} (http://localhost:5174)${NC}"
fi
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  🌊 Dev Suite Running! (Updated launch script)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Internal Frontend:${NC}  http://localhost:${VITE_PORT}/"
echo -e "  ${GREEN}cog-works (main):${NC}   http://localhost:5174/"
echo -e "  ${GREEN}Anvil RPC:${NC}          http://127.0.0.1:8545"
echo -e "  ${GREEN}Chain ID:${NC}  31337"
echo -e "  ${YELLOW}Note:${NC} Frontends served statically (dev watchers limited in env). Contract addresses injected. WETH pool pre-seeded on first card."
echo ""
echo -e "  ${YELLOW}Test Accounts (10,000 ETH each):${NC}"
echo -e "  #0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
echo -e "      PK: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
echo -e "  #1: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
echo -e "      PK: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
echo -e "  #2: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
echo -e "      PK: 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
echo ""
echo -e "  ${YELLOW}Logs:${NC}"
echo -e "    Anvil: tail -f /tmp/anvil-erc1142.log"
echo -e "    Internal: tail -f /tmp/serve-internal.log"
echo -e "    cog-works: tail -f /tmp/serve-cogworks.log"
echo -e "  ${YELLOW}To use:${NC} Import Anvil PK #0 into wallet, connect to RPC, use test ETH."
echo ""
echo -e "  ${RED}Press Ctrl+C to stop everything${NC}"
echo ""

# ─── Trap cleanup ───
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $VITE_PID 2>/dev/null || true
    kill $COG_PID 2>/dev/null || true
    kill $ANVIL_PID 2>/dev/null || true
    pkill -f "vite.*5174" 2>/dev/null || true
    echo -e "${GREEN}Done.${NC}"
    exit 0
}
trap cleanup INT TERM

# Wait for either process
wait
