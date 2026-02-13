#!/usr/bin/env bash
# Mint a card for every image in cog-works/public/images/card-images/
# Stores ERC-721 metadata as data:application/json;base64 URI on-chain
set -e
export PATH="$HOME/.foundry/bin:$PATH"

ROUTER="${1:?Usage: mint-all-cards.sh <ROUTER_ADDRESS>}"
RPC="http://127.0.0.1:8545"
PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
IMG_DIR="$HOME/Projects/cog-works/public/images/card-images"

declare -A CREATED
TOTAL=$(ls "$IMG_DIR"/*.png 2>/dev/null | wc -l)
COUNT=0
MINTED=0

for f in "$IMG_DIR"/*.png; do
  COUNT=$((COUNT + 1))
  fname=$(basename "$f")
  # Extract name: remove leading numbers + underscore, strip .png, replace _ with space
  raw=$(echo "$fname" | sed 's/^[0-9]*_//' | sed 's/\.png$//' | sed 's/_/ /g')

  # Skip duplicates
  key=$(echo "$raw" | tr '[:upper:]' '[:lower:]')
  if [[ -n "${CREATED[$key]}" ]]; then
    echo "[$COUNT/$TOTAL] SKIP (dupe): $raw"
    continue
  fi
  CREATED[$key]=1

  # Generate symbol: first letter of each word, uppercase, max 8
  symbol=$(echo "$raw" | awk '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1))}')
  if [ ${#symbol} -lt 2 ]; then
    symbol=$(echo "$raw" | tr '[:lower:]' '[:upper:]' | cut -c1-4)
  fi
  symbol="${symbol:0:8}"

  # Build ERC-721 metadata JSON
  metadata=$(cat <<EOF
{"name":"$raw","description":"A Whirlpool card","image":"/images/card-images/$fname","external_url":"https://howlonghasitben.github.io/cog-works/","attributes":[{"trait_type":"Type","value":"Creature"},{"trait_type":"Rarity","value":"Common"}]}
EOF
  )
  uri="data:application/json;base64,$(echo -n "$metadata" | base64 -w0)"

  echo "[$COUNT/$TOTAL] Creating $raw ($symbol)..."
  cast send "$ROUTER" "createCard(string,string,string)" "$raw" "$symbol" "$uri" \
    --value 0.05ether --private-key "$PK" --rpc-url "$RPC" --quiet 2>/dev/null || {
    echo "  ⚠ FAILED: $raw"
    continue
  }
  MINTED=$((MINTED + 1))
done

echo ""
echo "Done! Minted $MINTED unique cards from $TOTAL images."
