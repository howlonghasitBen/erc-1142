#!/bin/bash
#
# Watch transactions on local Anvil with full details
#

CAST="${HOME}/.foundry/bin/cast"
RPC="http://127.0.0.1:8545"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}Watching for new blocks on Anvil...${NC}"
echo ""

LAST_BLOCK=0

while true; do
    CURRENT_BLOCK=$($CAST block-number --rpc-url $RPC 2>/dev/null)
    
    if [ -z "$CURRENT_BLOCK" ]; then
        echo -e "${YELLOW}Waiting for Anvil...${NC}"
        sleep 2
        continue
    fi
    
    if [ "$CURRENT_BLOCK" -gt "$LAST_BLOCK" ]; then
        for ((BLOCK=LAST_BLOCK+1; BLOCK<=CURRENT_BLOCK; BLOCK++)); do
            if [ "$BLOCK" -eq 0 ]; then continue; fi
            
            echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
            echo -e "${GREEN}Block #${BLOCK}${NC}"
            
            # Get block info
            BLOCK_INFO=$($CAST block $BLOCK --rpc-url $RPC 2>/dev/null)
            TIMESTAMP=$(echo "$BLOCK_INFO" | grep "timestamp" | awk '{print $2}')
            TX_COUNT=$(echo "$BLOCK_INFO" | grep -c "0x" || echo "0")
            
            # Get transactions in block
            TXS=$($CAST block $BLOCK --rpc-url $RPC --json 2>/dev/null | jq -r '.transactions[]' 2>/dev/null)
            
            if [ -n "$TXS" ]; then
                for TX in $TXS; do
                    echo ""
                    echo -e "${CYAN}TX: ${TX}${NC}"
                    
                    # Get receipt
                    RECEIPT=$($CAST receipt $TX --rpc-url $RPC --json 2>/dev/null)
                    
                    if [ -n "$RECEIPT" ]; then
                        FROM=$(echo "$RECEIPT" | jq -r '.from')
                        TO=$(echo "$RECEIPT" | jq -r '.to // "CONTRACT CREATE"')
                        GAS=$(echo "$RECEIPT" | jq -r '.gasUsed')
                        STATUS=$(echo "$RECEIPT" | jq -r '.status')
                        CONTRACT=$(echo "$RECEIPT" | jq -r '.contractAddress // empty')
                        
                        echo -e "  From:   ${FROM}"
                        [ "$TO" != "CONTRACT CREATE" ] && echo -e "  To:     ${TO}" || echo -e "  To:     ${YELLOW}(Contract Creation)${NC}"
                        [ -n "$CONTRACT" ] && echo -e "  ${GREEN}Created: ${CONTRACT}${NC}"
                        echo -e "  Gas:    ${GAS}"
                        echo -e "  Status: ${STATUS}"
                        
                        # Show logs (events)
                        LOGS=$(echo "$RECEIPT" | jq -r '.logs | length')
                        if [ "$LOGS" -gt 0 ]; then
                            echo -e "  Events: ${LOGS}"
                            
                            # Check for TopHolderChanged event
                            TOP_HOLDER_SIG="0x$(cast keccak 'TopHolderChanged(address,address,uint256)' | cut -c1-64)"
                            if echo "$RECEIPT" | jq -e ".logs[] | select(.topics[0] == \"$TOP_HOLDER_SIG\")" > /dev/null 2>&1; then
                                echo -e "  ${GREEN}🎉 TopHolderChanged event detected!${NC}"
                            fi
                        fi
                    fi
                done
            else
                echo -e "  ${YELLOW}(empty block)${NC}"
            fi
        done
        
        LAST_BLOCK=$CURRENT_BLOCK
    fi
    
    sleep 1
done
