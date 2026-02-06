#!/bin/bash
#
# ERC-1142 Bid-to-Own Demo Launcher
# Starts Anvil testnet + deploys contracts + launches frontend
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     ERC-1142 Bid-to-Own NFT Demo          ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command -v forge &> /dev/null && ! [ -f ~/.foundry/bin/forge ]; then
    echo "Foundry not found. Install with: curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

FORGE="${HOME}/.foundry/bin/forge"
ANVIL="${HOME}/.foundry/bin/anvil"

if ! command -v node &> /dev/null; then
    echo "Node.js not found. Please install Node.js 18+"
    exit 1
fi

# Kill any existing processes
echo -e "${YELLOW}Cleaning up old processes...${NC}"
pkill -f "anvil.*8545" 2>/dev/null || true
pkill -f "vite.*erc-1142" 2>/dev/null || true
sleep 1

# Start Anvil
echo -e "${YELLOW}Starting Anvil local testnet...${NC}"
$ANVIL --host 0.0.0.0 --port 8545 \
    > /tmp/anvil-erc1142.log 2>&1 &
ANVIL_PID=$!
sleep 2

if ! kill -0 $ANVIL_PID 2>/dev/null; then
    echo "Failed to start Anvil"
    cat /tmp/anvil-erc1142.log
    exit 1
fi

echo -e "${GREEN}✓ Anvil running on http://127.0.0.1:8545 (PID: $ANVIL_PID)${NC}"

# Deploy contracts
echo -e "${YELLOW}Deploying contracts...${NC}"
$FORGE script script/LocalDeploy.s.sol:LocalDeployScript \
    --rpc-url http://127.0.0.1:8545 \
    --broadcast \
    2>&1 | grep -E "(BidNFT:|Factory:|Card [0-9]|Deployer:)" || true

echo -e "${GREEN}✓ Contracts deployed${NC}"

# Install frontend deps if needed
if [ ! -d "frontend/node_modules" ]; then
    echo -e "${YELLOW}Installing frontend dependencies...${NC}"
    cd frontend && npm install && cd ..
fi

# Start frontend
echo -e "${YELLOW}Starting frontend...${NC}"
cd frontend
npm run dev -- --host 0.0.0.0 > /tmp/vite-erc1142.log 2>&1 &
VITE_PID=$!
cd ..
sleep 3

# Get the port Vite is using
VITE_PORT=$(grep -oP 'localhost:\K[0-9]+' /tmp/vite-erc1142.log | head -1)
if [ -z "$VITE_PORT" ]; then
    VITE_PORT="5173"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Demo is running!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "  Frontend:  ${BLUE}http://localhost:${VITE_PORT}${NC}"
echo -e "  Anvil RPC: ${BLUE}http://127.0.0.1:8545${NC}"
echo ""
echo -e "  TX watcher: ./watch-txs.sh  ${YELLOW}(verbose tx details)${NC}"
echo -e "  Anvil log:  tail -f /tmp/anvil-erc1142.log"
echo -e "  Vite log:   tail -f /tmp/vite-erc1142.log"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    kill $VITE_PID 2>/dev/null || true
    echo -e "${GREEN}Done.${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Wait for processes
wait $ANVIL_PID $VITE_PID
