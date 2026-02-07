// ═══════════════════════════════════════════════════════════════
// Contract Addresses — UPDATE AFTER DEPLOYMENT
// Run: forge script script/WhirlpoolDeploy.s.sol --rpc-url http://192.168.0.82:8545 --broadcast
// Then paste the logged addresses here.
// ═══════════════════════════════════════════════════════════════
export const WHIRLPOOL_ADDRESS = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9' as const;
export const WAVES_ADDRESS     = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512' as const;
export const BIDNFT_ADDRESS    = '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9' as const;
export const WETH_ADDRESS      = '0x5FbDB2315678afecb367f032d93F642f64180aa3' as const;
export const SURFSWAP_ADDRESS  = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0' as const;
export const ROUTER_ADDRESS    = '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707' as const;

// ═══════════════════════════════════════════════════════════════
// ABIs
// ═══════════════════════════════════════════════════════════════

// WhirlpoolRouter ABI - Card creation and registry
export const ROUTER_ABI = [
  { inputs: [{ name: 'name', type: 'string' }, { name: 'symbol', type: 'string' }, { name: 'tokenURI', type: 'string' }], name: 'createCard', outputs: [{ name: 'cardId', type: 'uint256' }], stateMutability: 'payable', type: 'function' },
  { inputs: [], name: 'totalCards', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }], name: 'cardToken', outputs: [{ name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
] as const;

// SurfSwap ABI - AMM swaps and pricing
export const SURFSWAP_ABI = [
  { inputs: [{ name: 'tokenIn', type: 'address' }, { name: 'tokenOut', type: 'address' }, { name: 'amountIn', type: 'uint256' }, { name: 'minAmountOut', type: 'uint256' }], name: 'swapExact', outputs: [{ name: 'amountOut', type: 'uint256' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }], name: 'getPrice', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }], name: 'getReserves', outputs: [{ name: 'wavesR', type: 'uint256' }, { name: 'cardsR', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'getWethReserves', outputs: [{ name: 'wavesR', type: 'uint256' }, { name: 'wethR', type: 'uint256' }], stateMutability: 'view', type: 'function' },
] as const;

// WhirlpoolStaking ABI - Staking and rewards
export const WHIRLPOOL_ABI = [
  // ─── Mutative ───
  { inputs: [{ name: 'cardId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], name: 'stake', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }, { name: 'amount', type: 'uint256' }], name: 'unstake', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }], name: 'claimRewards', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'amount', type: 'uint256' }], name: 'stakeWETH', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'amount', type: 'uint256' }], name: 'unstakeWETH', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [], name: 'claimWETHRewards', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  // ─── Views ───
  { inputs: [{ name: 'cardId', type: 'uint256' }, { name: 'user', type: 'address' }], name: 'stakeOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }], name: 'ownerOfCard', outputs: [{ name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: '', type: 'address' }], name: 'userWethStake', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'cardId', type: 'uint256' }, { name: 'user', type: 'address' }], name: 'pendingRewards', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'user', type: 'address' }], name: 'pendingGlobalRewards', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  // ─── Events ───
  { anonymous: false, inputs: [{ indexed: true, name: 'cardId', type: 'uint256' }, { indexed: true, name: 'user', type: 'address' }, { indexed: false, name: 'amount', type: 'uint256' }], name: 'Staked', type: 'event' },
  { anonymous: false, inputs: [{ indexed: true, name: 'cardId', type: 'uint256' }, { indexed: true, name: 'user', type: 'address' }, { indexed: false, name: 'amount', type: 'uint256' }], name: 'Unstaked', type: 'event' },
  { anonymous: false, inputs: [{ indexed: true, name: 'cardId', type: 'uint256' }, { indexed: true, name: 'previousOwner', type: 'address' }, { indexed: true, name: 'newOwner', type: 'address' }], name: 'OwnerChanged', type: 'event' },
  { anonymous: false, inputs: [{ indexed: true, name: 'user', type: 'address' }, { indexed: false, name: 'amount', type: 'uint256' }], name: 'WETHStaked', type: 'event' },
  { anonymous: false, inputs: [{ indexed: true, name: 'user', type: 'address' }, { indexed: false, name: 'amount', type: 'uint256' }], name: 'WETHUnstaked', type: 'event' },
  { anonymous: false, inputs: [{ indexed: true, name: 'user', type: 'address' }, { indexed: false, name: 'amount', type: 'uint256' }], name: 'RewardsClaimed', type: 'event' },
] as const;

export const WAVES_ABI = [
  { inputs: [], name: 'name', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'symbol', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'decimals', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalSupply', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transfer', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'approve', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], name: 'allowance', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transferFrom', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'mint', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [], name: 'whirlpool', outputs: [{ name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'MAX_SUPPLY', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
] as const;

export const CARD_TOKEN_ABI = [
  { inputs: [], name: 'name', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'symbol', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'decimals', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalSupply', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transfer', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'approve', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], name: 'allowance', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transferFrom', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
] as const;

export const BIDNFT_ABI = [
  { inputs: [{ name: 'tokenId', type: 'uint256' }], name: 'ownerOf', outputs: [{ name: '', type: 'address' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'tokenId', type: 'uint256' }], name: 'tokenURI', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'tokenId', type: 'uint256' }], name: 'exists', outputs: [{ name: '', type: 'bool' }], stateMutability: 'view', type: 'function' },
] as const;

export const WETH_ABI = [
  { inputs: [], name: 'deposit', outputs: [], stateMutability: 'payable', type: 'function' },
  { inputs: [{ name: 'amount', type: 'uint256' }], name: 'withdraw', outputs: [], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [], name: 'name', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'symbol', outputs: [{ name: '', type: 'string' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'decimals', outputs: [{ name: '', type: 'uint8' }], stateMutability: 'view', type: 'function' },
  { inputs: [], name: 'totalSupply', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'account', type: 'address' }], name: 'balanceOf', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transfer', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'approve', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
  { inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], name: 'allowance', outputs: [{ name: '', type: 'uint256' }], stateMutability: 'view', type: 'function' },
  { inputs: [{ name: 'from', type: 'address' }, { name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], name: 'transferFrom', outputs: [{ name: '', type: 'bool' }], stateMutability: 'nonpayable', type: 'function' },
] as const;

// Anvil test accounts
export const TEST_ACCOUNTS = [
  { address: '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266', pk: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' },
  { address: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8', pk: '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d' },
  { address: '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC', pk: '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a' },
] as const;
