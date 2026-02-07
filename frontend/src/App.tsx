import { useState, useEffect, useRef, useCallback } from 'react';
import { useAccount, useConnect, useDisconnect, useWriteContract } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { createPublicClient, http, formatEther, parseEther, maxUint256 } from 'viem';
import {
  WHIRLPOOL_ADDRESS, WAVES_ADDRESS, WETH_ADDRESS, SURFSWAP_ADDRESS, ROUTER_ADDRESS,
  WHIRLPOOL_ABI, WAVES_ABI, CARD_TOKEN_ABI, WETH_ABI, SURFSWAP_ABI, ROUTER_ABI,
  TEST_ACCOUNTS,
} from './contracts';
import { anvilChain } from './wagmi-config';
import './App.css';

const publicClient = createPublicClient({
  chain: anvilChain as any,
  transport: http('http://192.168.0.82:8545'),
});

type LogType = 'success' | 'error' | 'warn' | 'info' | 'ownership' | 'system' | 'default';
type LogFilter = 'all' | 'transfers' | 'ownership' | 'errors';

interface LogEntry {
  id: number;
  time: string;
  type: LogType;
  message: string;
  hash?: string;
  category: 'transfer' | 'ownership' | 'error' | 'system' | 'other';
}

interface CardState {
  id: number;
  name: string;
  symbol: string;
  address: `0x${string}`;
  owner: string;
  price: string;
  wavesReserve: string;
  cardReserve: string;
  myStake: string;
  myBalance: string;
}

let logCounter = 0;

function App() {
  const { address, isConnected } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();
  const { writeContractAsync } = useWriteContract();

  const [cards, setCards] = useState<CardState[]>([]);
  const [selectedCard, setSelectedCard] = useState(0);
  const [transferTo, setTransferTo] = useState('');
  const [transferAmount, setTransferAmount] = useState('');
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const [filter, setFilter] = useState<LogFilter>('all');
  const [scrollLocked, setScrollLocked] = useState(false);
  const [activeTab, setActiveTab] = useState<'transfer' | 'faucet' | 'mint'>('transfer');

  // Mint/AMM state
  const [mintName, setMintName] = useState('');
  const [mintSymbol, setMintSymbol] = useState('');
  const [mintURI, setMintURI] = useState('');
  const [swapIn, setSwapIn] = useState('waves');
  const [swapOut, setSwapOut] = useState('');
  const [swapAmount, setSwapAmount] = useState('');
  const [swapSource, setSwapSource] = useState<'wallet' | 'staked'>('wallet');
  const [swapInBalance, setSwapInBalance] = useState({ wallet: '0', staked: '0' });
  const [stakeCardId, setStakeCardId] = useState(0);
  const [stakeAmount, setStakeAmount] = useState('');
  const [wethStakeAmount, setWethStakeAmount] = useState('');
  const [wrapAmount, setWrapAmount] = useState('');
  const [swapStakeFrom, setSwapStakeFrom] = useState(0);
  const [swapStakeTo, setSwapStakeTo] = useState(0);
  const [swapStakeAmount, setSwapStakeAmount] = useState('');

  // Balances
  const [wavesBalance, setWavesBalance] = useState('0');
  const [wethBalance, setWethBalance] = useState('0');
  const [myWethStake, setMyWethStake] = useState('0');
  const [pendingGlobal, setPendingGlobal] = useState('0');

  const termRef = useRef<HTMLDivElement>(null);

  const addLog = useCallback((message: string, type: LogType = 'default', extra: Partial<LogEntry> = {}) => {
    const entry: LogEntry = {
      id: ++logCounter,
      time: new Date().toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }),
      type, message, category: extra.category || 'other', ...extra,
    };
    setLogs(prev => [...prev, entry].slice(-500));
  }, []);

  useEffect(() => {
    if (!scrollLocked && termRef.current) {
      termRef.current.scrollTop = termRef.current.scrollHeight;
    }
  }, [logs, scrollLocked]);

  /**
   * Load all card data from on-chain contracts.
   * Queries Router.totalCards() then iterates to fetch each card's token address,
   * name, symbol, owner, price, reserves, and user-specific stake/balance.
   * Also fetches user's WAVES, WETH, WETH stake, and pending global rewards.
   * Called on mount, every 5s via interval, and after every transaction.
   */
  const loadCards = useCallback(async () => {
    try {
      const totalBig = await publicClient.readContract({
        address: ROUTER_ADDRESS, abi: ROUTER_ABI, functionName: 'totalCards',
      }) as bigint;
      const total = Number(totalBig);
      const cardData: CardState[] = [];

      for (let i = 0; i < total; i++) {
        try {
          const tokenAddr = await publicClient.readContract({
            address: ROUTER_ADDRESS, abi: ROUTER_ABI, functionName: 'cardToken', args: [BigInt(i)],
          }) as `0x${string}`;

          const [name, symbol, owner, price, reserves] = await Promise.all([
            publicClient.readContract({ address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'name' }),
            publicClient.readContract({ address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'symbol' }),
            publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(i)] }),
            publicClient.readContract({ address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'getPrice', args: [BigInt(i)] }),
            publicClient.readContract({ address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'getReserves', args: [BigInt(i)] }),
          ]);

          let myStake = '0';
          let myBalance = '0';
          if (address) {
            const [s, b] = await Promise.all([
              publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(i), address] }),
              publicClient.readContract({ address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'balanceOf', args: [address] }),
            ]);
            myStake = formatEther(s as bigint);
            myBalance = formatEther(b as bigint);
          }

          const [wavesR, cardsR] = reserves as [bigint, bigint];
          cardData.push({
            id: i, name: name as string, symbol: symbol as string, address: tokenAddr,
            owner: owner as string,
            price: formatEther(price as bigint),
            wavesReserve: formatEther(wavesR),
            cardReserve: formatEther(cardsR),
            myStake, myBalance,
          });
        } catch (e: any) {
          console.error(`Error loading card ${i}:`, e);
          addLog(`⚠ Error loading card ${i}: ${e.shortMessage || e.message}`, 'error');
        }
      }
      setCards(cardData);

      // Load user balances
      if (address) {
        try {
          const [wb, wethb, ws, pg] = await Promise.all([
            publicClient.readContract({ address: WAVES_ADDRESS, abi: WAVES_ABI, functionName: 'balanceOf', args: [address] }),
            publicClient.readContract({ address: WETH_ADDRESS, abi: WETH_ABI, functionName: 'balanceOf', args: [address] }),
            publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'userWethStake', args: [address] }),
            publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'pendingGlobalRewards', args: [address] }),
          ]);
          setWavesBalance(formatEther(wb as bigint));
          setWethBalance(formatEther(wethb as bigint));
          setMyWethStake(formatEther(ws as bigint));
          setPendingGlobal(formatEther(pg as bigint));
        } catch (_) {}
      }
    } catch (e: any) {
      console.error('Error loading cards:', e);
      addLog(`⚠ Error loading cards: ${e.shortMessage || e.message}`, 'error');
    }
  }, [address]);

  /**
   * Ensure ERC-20 approval for a spender. Checks current allowance and only
   * sends an approve(maxUint256) transaction if allowance is insufficient.
   * @param token - ERC-20 token address to approve
   * @param spender - Address being approved to spend tokens
   * @param amount - Minimum required allowance
   */
  const ensureApproval = async (token: `0x${string}`, spender: `0x${string}`, amount: bigint) => {
    const allowance = await publicClient.readContract({
      address: token, abi: CARD_TOKEN_ABI, functionName: 'allowance', args: [address!, spender],
    }) as bigint;
    if (allowance < amount) {
      addLog(`Approving ${spender.slice(0, 10)}... to spend tokens...`, 'info');
      const hash = await writeContractAsync({ address: token, abi: CARD_TOKEN_ABI, functionName: 'approve', args: [spender, maxUint256] });
      await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Approval confirmed`, 'success');
    }
  };

  // ─── Transfer ───
  const handleTransfer = async () => {
    if (!transferTo || !transferAmount || !isConnected || cards.length === 0) return;
    setLoading(true);
    const card = cards[selectedCard];
    try {
      addLog(`TRANSFER ${transferAmount} ${card.symbol} → ${transferTo.slice(0, 10)}...`, 'info', { category: 'transfer' });
      const hash = await writeContractAsync({
        address: card.address, abi: CARD_TOKEN_ABI, functionName: 'transfer',
        args: [transferTo as `0x${string}`, parseEther(transferAmount)],
      });
      addLog(`TX submitted: ${hash}`, 'info', { hash, category: 'transfer' });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Confirmed block #${receipt.blockNumber} · gas ${receipt.gasUsed}`, 'success', { hash, category: 'transfer' });
      await loadCards();
    } catch (e: any) { addLog(`✗ ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Faucet: Wrap ETH → WETH ───
  const handleWrapETH = async () => {
    if (!isConnected || !wrapAmount) return;
    setLoading(true);
    try {
      const amt = parseEther(wrapAmount);
      addLog(`Wrapping ${wrapAmount} ETH → WETH...`, 'info');
      const hash = await writeContractAsync({
        address: WETH_ADDRESS, abi: WETH_ABI, functionName: 'deposit', value: amt,
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Wrapped ${wrapAmount} ETH → WETH · block #${receipt.blockNumber}`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ Wrap: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Faucet: Swap some WAVES for card tokens ───
  const handleFaucetSwap = async (cardIdx: number) => {
    if (!isConnected || !address) return;
    setLoading(true);
    const card = cards[cardIdx];
    try {
      const wavesAmt = parseEther('100'); // swap 100 WAVES for some card tokens
      addLog(`Swapping 100 WAVES → ${card.symbol}...`, 'info', { category: 'transfer' });
      await ensureApproval(WAVES_ADDRESS, SURFSWAP_ADDRESS, wavesAmt);
      const hash = await writeContractAsync({
        address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'swapExact',
        args: [WAVES_ADDRESS, card.address, wavesAmt, BigInt(0)],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Swapped 100 WAVES → ${card.symbol} · block #${receipt.blockNumber}`, 'success', { category: 'transfer' });
      await loadCards();
    } catch (e: any) { addLog(`✗ Faucet swap: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Create Card ───
  const handleCreateCard = async () => {
    if (!isConnected || !mintName || !mintSymbol) return;
    setLoading(true);
    try {
      addLog(`Creating card "${mintName}" (${mintSymbol}) for 0.05 ETH...`, 'info');
      const hash = await writeContractAsync({
        address: ROUTER_ADDRESS, abi: ROUTER_ABI, functionName: 'createCard',
        args: [mintName, mintSymbol, mintURI || ''], value: parseEther('0.05'),
      });
      addLog(`TX submitted: ${hash}`, 'info', { hash });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Card created! Block #${receipt.blockNumber} · gas ${receipt.gasUsed}`, 'success', { hash });

      // Fetch detailed post-mint info
      try {
        const newTotal = await publicClient.readContract({ address: ROUTER_ADDRESS, abi: ROUTER_ABI, functionName: 'totalCards' }) as bigint;
        const newCardId = Number(newTotal) - 1;
        const tokenAddr = await publicClient.readContract({ address: ROUTER_ADDRESS, abi: ROUTER_ABI, functionName: 'cardToken', args: [BigInt(newCardId)] }) as `0x${string}`;
        const [reserves, wavesBalance, tokenBalance] = await Promise.all([
          publicClient.readContract({ address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'getReserves', args: [BigInt(newCardId)] }),
          publicClient.readContract({ address: WAVES_ADDRESS, abi: WAVES_ABI, functionName: 'balanceOf', args: [address!] }),
          publicClient.readContract({ address: tokenAddr, abi: CARD_TOKEN_ABI, functionName: 'balanceOf', args: [address!] }),
        ]);
        const [wavesR, cardsR] = reserves as [bigint, bigint];
        addLog(`  Card #${newCardId} token: ${tokenAddr}`, 'info');
        addLog(`  2,000 WAVES minted (500 → AMM, 1,500 → you)`, 'ownership');
        addLog(`  10M ${mintSymbol} created (7.5M → AMM, 2M → staked for you, 500K → protocol)`, 'ownership');
        addLog(`  LP seeded: ${formatEther(wavesR)} WAVES / ${formatEther(cardsR)} ${mintSymbol}`, 'info');
        addLog(`  Your WAVES balance: ${formatEther(wavesBalance as bigint)}`, 'info');
        addLog(`  Your ${mintSymbol} balance: ${formatEther(tokenBalance as bigint)}`, 'info');
        addLog(`  NFT ownership: YOU (auto-staked 2M tokens)`, 'success');
      } catch (e: any) {
        addLog(`  ⚠ Could not fetch post-mint details: ${e.shortMessage || e.message}`, 'warn');
      }

      setMintName(''); setMintSymbol(''); setMintURI('');
      await loadCards();
    } catch (e: any) { addLog(`✗ Create: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  /**
   * SwapStake auto-detection and source toggle logic.
   * When the swap input token changes, this effect:
   * 1. Fetches both wallet balance and staked balance for the selected token
   * 2. Auto-selects the swap source (wallet vs staked):
   *    - If only staked balance exists → auto-select "staked" (triggers swapStake path)
   *    - If only wallet balance exists → auto-select "wallet" (regular swap)
   *    - If both exist → prefer "staked" (swapStake is more gas-efficient for card→card)
   * 3. When source="staked" AND both in/out are cards, handleSwap() uses
   *    WhirlpoolStaking.swapStake() instead of SurfSwap.swapExact()
   */
  useEffect(() => {
    const updateSwapBalance = async () => {
      if (!address || !swapIn) return;
      
      let walletBal = '0';
      let stakedBal = '0';
      
      try {
        if (swapIn === 'waves') {
          walletBal = wavesBalance;
        } else if (swapIn === 'weth') {
          walletBal = wethBalance;
        } else if (swapIn.startsWith('card-')) {
          const cardIdx = parseInt(swapIn.replace('card-', ''));
          const card = cards[cardIdx];
          if (card) {
            walletBal = card.myBalance;
            stakedBal = card.myStake;
          }
        }
        
        setSwapInBalance({ wallet: walletBal, staked: stakedBal });
        
        // Auto-detect source
        const hasWallet = Number(walletBal) > 0;
        const hasStaked = Number(stakedBal) > 0;
        
        if (hasStaked && !hasWallet) {
          setSwapSource('staked');
        } else if (hasWallet && !hasStaked) {
          setSwapSource('wallet');
        } else if (hasStaked) {
          setSwapSource('staked'); // Prefer staked if both exist
        } else {
          setSwapSource('wallet');
        }
      } catch (e) {
        console.error('Error updating swap balance:', e);
      }
    };
    
    updateSwapBalance();
  }, [swapIn, address, wavesBalance, wethBalance, cards]);

  /**
   * Resolve a UI token key (e.g., 'waves', 'weth', 'card-0') to its contract address.
   * @param key - Token key from dropdown selection
   * @returns Contract address as hex string
   */
  const resolveToken = (key: string): `0x${string}` => {
    if (key === 'waves') return WAVES_ADDRESS;
    if (key === 'weth') return WETH_ADDRESS;
    // card index
    const idx = parseInt(key.replace('card-', ''));
    return cards[idx]?.address || ('0x0' as `0x${string}`);
  };

  /**
   * Execute a swap. Routes to either:
   * - WhirlpoolStaking.swapStake() — when both in/out are cards AND source is "staked"
   *   (atomic, no token transfers, pure reserve math, ~280K gas)
   * - SurfSwap.swapExact() — for all other routes (wallet tokens, WAVES, WETH)
   *   (standard AMM swap with token transfers)
   *
   * For swapStake, records pre/post state to show ownership changes in the log.
   */
  const handleSwap = async () => {
    if (!isConnected || !swapAmount || !swapIn || !swapOut) return;
    setLoading(true);
    try {
      const isCardIn = swapIn.startsWith('card-');
      const isCardOut = swapOut.startsWith('card-');
      const amt = parseEther(swapAmount);
      
      // Check if we should use swapStake
      if (isCardIn && isCardOut && swapSource === 'staked') {
        const fromCardId = parseInt(swapIn.replace('card-', ''));
        const toCardId = parseInt(swapOut.replace('card-', ''));
        const fromCard = cards[fromCardId];
        const toCard = cards[toCardId];
        
        addLog(`⚡ Using swapStake (staked tokens detected)...`, 'info');
        addLog(`Swapping ${swapAmount} shares from ${fromCard.symbol} → ${toCard.symbol}...`, 'info');
        
        // Record pre-swap state
        const [preFromStake, preToStake, preFromOwner, preToOwner] = await Promise.all([
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(fromCardId), address!] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(toCardId), address!] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(fromCardId)] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(toCardId)] }),
        ]);
        
        const hash = await writeContractAsync({
          address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'swapStake',
          args: [BigInt(fromCardId), BigInt(toCardId), amt],
        });
        
        addLog(`TX submitted: ${hash}`, 'info', { hash });
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        addLog(`⚡ SwapStake: ${swapAmount} shares from ${fromCard.symbol} → ${toCard.symbol} (atomic, no transfers)`, 'success', { hash });
        addLog(`✓ Confirmed · block #${receipt.blockNumber} · gas ${receipt.gasUsed}`, 'success');
        
        // Post-swap details
        const [postFromStake, postToStake, postFromOwner, postToOwner] = await Promise.all([
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(fromCardId), address!] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(toCardId), address!] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(fromCardId)] }),
          publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(toCardId)] }),
        ]);
        
        addLog(`  ${fromCard.symbol}: ${formatEther(preFromStake as bigint)} → ${formatEther(postFromStake as bigint)} shares`, 'info');
        addLog(`  ${toCard.symbol}: ${formatEther(preToStake as bigint)} → ${formatEther(postToStake as bigint)} shares`, 'info');
        
        if (preFromOwner !== postFromOwner) {
          addLog(`  ${fromCard.symbol} ownership: ${addr(preFromOwner as string)} → ${addr(postFromOwner as string)}`, 'ownership', { category: 'ownership' });
        }
        if (preToOwner !== postToOwner) {
          addLog(`  ${toCard.symbol} ownership: ${addr(preToOwner as string)} → ${addr(postToOwner as string)}`, 'ownership', { category: 'ownership' });
        }
      } else {
        // Regular swap via SurfSwap
        const tokenIn = resolveToken(swapIn);
        const tokenOut = resolveToken(swapOut);
        
        addLog(`Swapping ${swapAmount} ${swapIn} → ${swapOut}...`, 'info');
        await ensureApproval(tokenIn, SURFSWAP_ADDRESS, amt);
        const hash = await writeContractAsync({
          address: SURFSWAP_ADDRESS, abi: SURFSWAP_ABI, functionName: 'swapExact',
          args: [tokenIn, tokenOut, amt, BigInt(0)],
        });
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        addLog(`✓ Swap confirmed · block #${receipt.blockNumber} · gas ${receipt.gasUsed}`, 'success');
      }
      
      await loadCards();
    } catch (e: any) { addLog(`✗ Swap: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Stake / Unstake card tokens ───
  const handleStake = async () => {
    if (!isConnected || !stakeAmount) return;
    setLoading(true);
    const card = cards[stakeCardId];
    try {
      const amt = parseEther(stakeAmount);
      addLog(`Staking ${stakeAmount} ${card?.symbol || '?'} on card #${stakeCardId}...`, 'info');
      await ensureApproval(card.address, WHIRLPOOL_ADDRESS, amt);
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stake',
        args: [BigInt(stakeCardId), amt],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Staked · block #${receipt.blockNumber}`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ Stake: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  const handleUnstake = async () => {
    if (!isConnected || !stakeAmount) return;
    setLoading(true);
    try {
      const amt = parseEther(stakeAmount);
      addLog(`Unstaking ${stakeAmount} from card #${stakeCardId}...`, 'info');
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'unstake',
        args: [BigInt(stakeCardId), amt],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Unstaked · block #${receipt.blockNumber}`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ Unstake: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  const handleClaimRewards = async (cardId: number) => {
    if (!isConnected) return;
    setLoading(true);
    try {
      addLog(`Claiming rewards for card #${cardId}...`, 'info');
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'claimRewards',
        args: [BigInt(cardId)],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Rewards claimed`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ Claim: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Swap Stake ───
  const handleSwapStake = async () => {
    if (!isConnected || !swapStakeAmount || swapStakeFrom === swapStakeTo) return;
    setLoading(true);
    const fromCard = cards[swapStakeFrom];
    const toCard = cards[swapStakeTo];
    try {
      const amt = parseEther(swapStakeAmount);
      addLog(`Swapping stake: ${swapStakeAmount} shares from ${fromCard.symbol} → ${toCard.symbol}...`, 'info');
      
      // Record pre-swap state
      const [preFromStake, preToStake, preFromOwner, preToOwner] = await Promise.all([
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(swapStakeFrom), address!] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(swapStakeTo), address!] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(swapStakeFrom)] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(swapStakeTo)] }),
      ]);

      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'swapStake',
        args: [BigInt(swapStakeFrom), BigInt(swapStakeTo), amt],
      });
      addLog(`TX submitted: ${hash}`, 'info', { hash });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ Swap stake confirmed · block #${receipt.blockNumber} · gas ${receipt.gasUsed}`, 'success', { hash });

      // Post-swap details
      const [postFromStake, postToStake, postFromOwner, postToOwner] = await Promise.all([
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(swapStakeFrom), address!] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeOf', args: [BigInt(swapStakeTo), address!] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(swapStakeFrom)] }),
        publicClient.readContract({ address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'ownerOfCard', args: [BigInt(swapStakeTo)] }),
      ]);

      addLog(`  ${fromCard.symbol}: ${formatEther(preFromStake as bigint)} → ${formatEther(postFromStake as bigint)} shares`, 'info');
      addLog(`  ${toCard.symbol}: ${formatEther(preToStake as bigint)} → ${formatEther(postToStake as bigint)} shares`, 'info');
      
      if (preFromOwner !== postFromOwner) {
        addLog(`  ${fromCard.symbol} ownership: ${addr(preFromOwner as string)} → ${addr(postFromOwner as string)}`, 'ownership', { category: 'ownership' });
      }
      if (preToOwner !== postToOwner) {
        addLog(`  ${toCard.symbol} ownership: ${addr(preToOwner as string)} → ${addr(postToOwner as string)}`, 'ownership', { category: 'ownership' });
      }

      await loadCards();
    } catch (e: any) { addLog(`✗ Swap stake: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── WETH Staking ───
  const handleStakeWETH = async () => {
    if (!isConnected || !wethStakeAmount) return;
    setLoading(true);
    try {
      const amt = parseEther(wethStakeAmount);
      addLog(`Staking ${wethStakeAmount} WETH (1.5x boost)...`, 'info');
      await ensureApproval(WETH_ADDRESS, WHIRLPOOL_ADDRESS, amt);
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'stakeWETH', args: [amt],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ WETH staked · block #${receipt.blockNumber}`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ WETH stake: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  const handleUnstakeWETH = async () => {
    if (!isConnected || !wethStakeAmount) return;
    setLoading(true);
    try {
      const amt = parseEther(wethStakeAmount);
      addLog(`Unstaking ${wethStakeAmount} WETH...`, 'info');
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'unstakeWETH', args: [amt],
      });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ WETH unstaked · block #${receipt.blockNumber}`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ WETH unstake: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  const handleClaimWETHRewards = async () => {
    if (!isConnected) return;
    setLoading(true);
    try {
      addLog(`Claiming WETH staking rewards...`, 'info');
      const hash = await writeContractAsync({
        address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, functionName: 'claimWETHRewards',
      });
      await publicClient.waitForTransactionReceipt({ hash });
      addLog(`✓ WETH rewards claimed`, 'success');
      await loadCards();
    } catch (e: any) { addLog(`✗ Claim: ${e.shortMessage || e.message}`, 'error', { category: 'error' }); }
    setLoading(false);
  };

  // ─── Watch events ───
  useEffect(() => {
    const unwatch = publicClient.watchContractEvent({
      address: WHIRLPOOL_ADDRESS, abi: WHIRLPOOL_ABI, eventName: 'OwnerChanged',
      onLogs: (eventLogs) => {
        for (const log of eventLogs) {
          const args = log.args as any;
          addLog(`★ OWNERSHIP CHANGED card #${args.cardId} → ${args.newOwner?.slice(0, 12)}…`, 'ownership', { category: 'ownership' });
        }
        loadCards();
      },
    });
    return () => unwatch();
  }, [addLog, loadCards]);

  // ─── Init ───
  useEffect(() => {
    addLog('═══ ERC-1142 · Whirlpool AMM Terminal ═══', 'system', { category: 'system' });
    addLog(`Whirlpool: ${WHIRLPOOL_ADDRESS}`, 'system', { category: 'system' });
    addLog(`WAVES: ${WAVES_ADDRESS}`, 'system', { category: 'system' });
    addLog(`WETH: ${WETH_ADDRESS}`, 'system', { category: 'system' });
    addLog(`RPC: http://192.168.0.82:8545 · Chain 31337`, 'system', { category: 'system' });
    addLog('Watching for on-chain events...', 'info', { category: 'system' });
    loadCards();
    const interval = setInterval(loadCards, 5000);
    return () => clearInterval(interval);
  }, [address]);

  const filteredLogs = logs.filter(l => {
    if (filter === 'all') return true;
    if (filter === 'transfers') return l.category === 'transfer';
    if (filter === 'ownership') return l.category === 'ownership';
    if (filter === 'errors') return l.category === 'error';
    return true;
  });

  const copyLogs = () => {
    navigator.clipboard.writeText(filteredLogs.map(l => `[${l.time}] ${l.message}`).join('\n'));
    addLog('Copied to clipboard', 'info', { category: 'system' });
  };

  const currentCard = cards[selectedCard];
  const addr = (s: string) => s ? `${s.slice(0, 8)}…${s.slice(-6)}` : '—';

  // Token options for swap dropdowns
  const tokenOptions = [
    { key: 'waves', label: 'WAVES' },
    { key: 'weth', label: 'WETH' },
    ...cards.map((c, i) => ({ key: `card-${i}`, label: c.symbol })),
  ];

  return (
    <div className="app-root">
      {/* ─── Top Bar ─── */}
      <div className="topbar">
        <div className="topbar-left">
          <h1>ERC-1142 · Whirlpool AMM</h1>
          <span className="chain-badge">● ANVIL 31337</span>
        </div>
        <div className="topbar-right">
          {isConnected ? (<>
            <span className="wallet-dot" />
            <code className="wallet-addr">{addr(address!)}</code>
            <span style={{ fontSize: '0.75rem', opacity: 0.7, marginLeft: 8 }}>
              WAVES: {Number(wavesBalance).toFixed(1)} · WETH: {Number(wethBalance).toFixed(4)}
            </span>
            <button className="btn btn-sm btn-disconnect" onClick={() => disconnect()}>Disconnect</button>
          </>) : (
            <button className="btn btn-connect" onClick={() => connect({ connector: injected() })}>Connect Wallet</button>
          )}
        </div>
      </div>

      {/* ─── Upper 3/4: Interactive UI ─── */}
      <div className="ui-area">
        {/* Card Grid */}
        <div className="cards-section">
          <div className="section-header">
            <h2>NFT Cards</h2>
            <span className="section-badge">{cards.length} loaded</span>
          </div>
          <div className="card-grid">
            {cards.map((card, i) => (
              <div key={card.id} className={`nft-card ${selectedCard === i ? 'selected' : ''} ${card.owner === address ? 'owned' : ''}`} onClick={() => { setSelectedCard(i); setStakeCardId(i); }}>
                <div className="card-top">
                  <h3>{card.name}</h3>
                  <span className="card-symbol">${card.symbol}</span>
                </div>
                <div className="card-stats">
                  <div className="stat-row">
                    <span className="stat-label">NFT Owner</span>
                    <span className={`stat-value ${card.owner === address ? 'is-you' : ''}`}>
                      {card.owner === address ? '👑 YOU' : card.owner === '0x0000000000000000000000000000000000000000' ? 'Unclaimed' : addr(card.owner)}
                    </span>
                  </div>
                  <div className="stat-row">
                    <span className="stat-label">Price (WAVES)</span>
                    <span className="stat-value">{Number(card.price).toFixed(6)}</span>
                  </div>
                  <div className="stat-row">
                    <span className="stat-label">Reserves</span>
                    <span className="stat-value" style={{ fontSize: '0.7rem' }}>
                      {Number(card.wavesReserve).toFixed(0)} W / {Number(card.cardReserve).toFixed(0)} C
                    </span>
                  </div>
                  {address && (
                    <>
                      <div className="stat-row">
                        <span className="stat-label">Your Stake</span>
                        <span className="stat-value">{Number(card.myStake).toLocaleString()}</span>
                      </div>
                      <div className="stat-row your-bal">
                        <span className="stat-label">Your Balance</span>
                        <span className="stat-value bal">{Number(card.myBalance).toLocaleString()}</span>
                      </div>
                    </>
                  )}
                </div>
              </div>
            ))}
            {cards.length === 0 && (
              <div className="nft-card" style={{ opacity: 0.5, textAlign: 'center', padding: '2rem' }}>
                No cards yet. Create one in the Mint/AMM tab!
              </div>
            )}
          </div>
        </div>

        {/* Actions Panel */}
        <div className="actions-section">
          <div className="tab-bar">
            <button className={`tab ${activeTab === 'transfer' ? 'active' : ''}`} onClick={() => setActiveTab('transfer')}>Transfer</button>
            <button className={`tab ${activeTab === 'faucet' ? 'active' : ''}`} onClick={() => setActiveTab('faucet')}>Faucet</button>
            <button className={`tab ${activeTab === 'mint' ? 'active' : ''}`} onClick={() => setActiveTab('mint')}>Mint / AMM</button>
          </div>

          <div className="tab-content">
            {/* ─── TRANSFER TAB ─── */}
            {activeTab === 'transfer' && (
              <div className="tab-panel">
                {!isConnected ? (
                  <p className="connect-prompt">Connect wallet to interact</p>
                ) : currentCard ? (<>
                  <div className="active-card-bar">
                    <span>Active: <strong>{currentCard.name}</strong></span>
                    <span className="active-bal">{Number(currentCard.myBalance).toLocaleString()} {currentCard.symbol}</span>
                  </div>
                  <div className="form-group">
                    <label>Recipient</label>
                    <input value={transferTo} onChange={e => setTransferTo(e.target.value)} placeholder="0x..." />
                    <div className="preset-row">
                      {TEST_ACCOUNTS.filter(a => a.address !== address).map(acc => (
                        <button key={acc.address} className="preset-btn" onClick={() => setTransferTo(acc.address)}>
                          Anvil #{TEST_ACCOUNTS.indexOf(acc)} ({acc.address.slice(0, 8)}…)
                        </button>
                      ))}
                    </div>
                  </div>
                  <div className="form-group">
                    <label>Amount</label>
                    <input type="number" value={transferAmount} onChange={e => setTransferAmount(e.target.value)} placeholder="0" />
                    <div className="quick-amounts">
                      <button onClick={() => setTransferAmount('100000')}>100k</button>
                      <button onClick={() => setTransferAmount('500000')}>500k</button>
                      <button onClick={() => setTransferAmount((Number(currentCard.myBalance) / 2).toString())}>Half</button>
                      <button onClick={() => setTransferAmount(currentCard.myBalance)}>Max</button>
                    </div>
                  </div>
                  <button className="btn-action" onClick={handleTransfer} disabled={loading || !transferTo || !transferAmount}>
                    {loading ? 'Confirming…' : `Transfer ${currentCard.symbol}`}
                  </button>
                </>) : <p className="connect-prompt">No cards available</p>}
              </div>
            )}

            {/* ─── FAUCET TAB ─── */}
            {activeTab === 'faucet' && (
              <div className="tab-panel">
                {!isConnected ? (
                  <p className="connect-prompt">Connect wallet to use faucet</p>
                ) : (<>
                  <div className="form-group">
                    <label>Wrap ETH → WETH</label>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                      <input type="number" value={wrapAmount} onChange={e => setWrapAmount(e.target.value)} placeholder="Amount in ETH" style={{ flex: 1 }} />
                      <button className="btn-action" onClick={handleWrapETH} disabled={loading} style={{ flex: 'none', width: 'auto', padding: '0 1rem' }}>
                        Wrap
                      </button>
                    </div>
                    <small style={{ opacity: 0.6 }}>WETH Balance: {Number(wethBalance).toFixed(4)}</small>
                  </div>

                  <div className="form-group">
                    <label>WAVES Balance</label>
                    <div style={{ padding: '0.5rem', background: 'rgba(0,255,170,0.05)', borderRadius: 4 }}>
                      <strong>{Number(wavesBalance).toLocaleString()}</strong> WAVES
                      <br /><small style={{ opacity: 0.6 }}>WAVES can only be obtained by creating cards (minter gets 1500) or swapping</small>
                    </div>
                  </div>

                  <div className="form-group">
                    <label>Swap 100 WAVES → Card Tokens</label>
                  </div>
                  <div className="faucet-grid">
                    {cards.map((c, i) => (
                      <button key={c.id} className="faucet-card-btn" onClick={() => handleFaucetSwap(i)} disabled={loading}>
                        <span className="faucet-name">{c.name}</span>
                        <span className="faucet-sym">${c.symbol}</span>
                        <span className="faucet-bal">Balance: {Number(c.myBalance).toLocaleString()}</span>
                        <span className="faucet-action">🌊 Swap 100 WAVES</span>
                      </button>
                    ))}
                  </div>
                </>)}
              </div>
            )}

            {/* ─── MINT / AMM TAB ─── */}
            {activeTab === 'mint' && (
              <div className="tab-panel" style={{ overflowY: 'auto' }}>
                {!isConnected ? (
                  <p className="connect-prompt">Connect wallet to interact</p>
                ) : (<>
                  {/* Create Card */}
                  <div className="form-group">
                    <label>🃏 Create Card (0.05 ETH)</label>
                    <input value={mintName} onChange={e => setMintName(e.target.value)} placeholder="Card Name" />
                    <input value={mintSymbol} onChange={e => setMintSymbol(e.target.value)} placeholder="Symbol (e.g. FDRAGON)" style={{ marginTop: 4 }} />
                    <input value={mintURI} onChange={e => setMintURI(e.target.value)} placeholder="Token URI (optional)" style={{ marginTop: 4 }} />
                    <button className="btn-action" onClick={handleCreateCard} disabled={loading || !mintName || !mintSymbol} style={{ marginTop: 8 }}>
                      {loading ? 'Creating…' : 'Create Card (0.05 ETH)'}
                    </button>
                  </div>

                  <hr style={{ borderColor: 'rgba(255,255,255,0.1)', margin: '1rem 0' }} />

                  {/* Swap */}
                  <div className="form-group">
                    <label>🌊 Swap</label>
                    <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                      <select value={swapIn} onChange={e => setSwapIn(e.target.value)} style={{ flex: 1 }}>
                        {tokenOptions.map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
                      </select>
                      <span>→</span>
                      <select value={swapOut} onChange={e => setSwapOut(e.target.value)} style={{ flex: 1 }}>
                        <option value="">Select...</option>
                        {tokenOptions.filter(t => t.key !== swapIn).map(t => <option key={t.key} value={t.key}>{t.label}</option>)}
                      </select>
                    </div>
                    
                    {/* Show balances for input token */}
                    {swapIn && (
                      <div style={{ fontSize: '0.75rem', opacity: 0.8, marginTop: 4, paddingLeft: 4 }}>
                        <div>Wallet: {Number(swapInBalance.wallet).toLocaleString()}</div>
                        {swapIn.startsWith('card-') && Number(swapInBalance.staked) > 0 && (
                          <div style={{ color: '#00ffaa', fontWeight: 500 }}>
                            Staked: {Number(swapInBalance.staked).toLocaleString()} shares
                          </div>
                        )}
                      </div>
                    )}
                    
                    {/* Source toggle for cards with both wallet and staked */}
                    {swapIn.startsWith('card-') && (Number(swapInBalance.wallet) > 0 || Number(swapInBalance.staked) > 0) && (
                      <div style={{ marginTop: 8, display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                        <span style={{ fontSize: '0.85rem', opacity: 0.7 }}>Swap from:</span>
                        <button 
                          className={`preset-btn ${swapSource === 'wallet' ? 'active' : ''}`}
                          onClick={() => setSwapSource('wallet')}
                          style={{ 
                            flex: 1,
                            background: swapSource === 'wallet' ? 'rgba(0,255,170,0.15)' : 'rgba(255,255,255,0.05)',
                            borderColor: swapSource === 'wallet' ? '#00ffaa' : 'rgba(255,255,255,0.1)'
                          }}
                        >
                          Wallet
                        </button>
                        <button 
                          className={`preset-btn ${swapSource === 'staked' ? 'active' : ''}`}
                          onClick={() => setSwapSource('staked')}
                          style={{ 
                            flex: 1,
                            background: swapSource === 'staked' ? 'rgba(0,255,170,0.15)' : 'rgba(255,255,255,0.05)',
                            borderColor: swapSource === 'staked' ? '#00ffaa' : 'rgba(255,255,255,0.1)'
                          }}
                          disabled={Number(swapInBalance.staked) === 0}
                        >
                          Staked
                        </button>
                      </div>
                    )}
                    
                    {/* Amount input with quick buttons */}
                    <input 
                      type="number" 
                      value={swapAmount} 
                      onChange={e => setSwapAmount(e.target.value)} 
                      placeholder={swapSource === 'staked' ? 'Shares to swap' : 'Amount'} 
                      style={{ marginTop: 8 }} 
                    />
                    <div className="quick-amounts" style={{ marginTop: 4 }}>
                      <button onClick={() => {
                        const bal = swapSource === 'staked' ? swapInBalance.staked : swapInBalance.wallet;
                        setSwapAmount((Number(bal) * 0.25).toString());
                      }}>25%</button>
                      <button onClick={() => {
                        const bal = swapSource === 'staked' ? swapInBalance.staked : swapInBalance.wallet;
                        setSwapAmount((Number(bal) * 0.5).toString());
                      }}>50%</button>
                      <button onClick={() => {
                        const bal = swapSource === 'staked' ? swapInBalance.staked : swapInBalance.wallet;
                        setSwapAmount((Number(bal) * 0.75).toString());
                      }}>75%</button>
                      <button onClick={() => {
                        const bal = swapSource === 'staked' ? swapInBalance.staked : swapInBalance.wallet;
                        setSwapAmount(bal);
                      }}>All</button>
                    </div>
                    
                    {/* Atomic swap note */}
                    {swapIn.startsWith('card-') && swapOut.startsWith('card-') && swapSource === 'staked' && (
                      <div style={{ 
                        marginTop: 8, 
                        padding: '0.5rem', 
                        background: 'rgba(0,255,170,0.05)', 
                        border: '1px solid rgba(0,255,170,0.2)', 
                        borderRadius: 4,
                        fontSize: '0.75rem',
                        color: '#00ffaa'
                      }}>
                        ⚡ Atomic swap — no tokens leave the pool
                      </div>
                    )}
                    
                    <button className="btn-action" onClick={handleSwap} disabled={loading || !swapAmount || !swapOut} style={{ marginTop: 8 }}>
                      {loading ? 'Swapping…' : 'Swap'}
                    </button>
                  </div>

                  <hr style={{ borderColor: 'rgba(255,255,255,0.1)', margin: '1rem 0' }} />

                  {/* Card Staking */}
                  <div className="form-group">
                    <label>📌 Stake Card Tokens → Own the NFT</label>
                    <select value={stakeCardId} onChange={e => setStakeCardId(Number(e.target.value))}>
                      {cards.map((c, i) => <option key={i} value={i}>{c.name} ({c.symbol})</option>)}
                    </select>
                    {currentCard && (
                      <div style={{ fontSize: '0.75rem', opacity: 0.7, marginTop: 4 }}>
                        Your stake: {Number(currentCard.myStake).toLocaleString()} · Owner: {currentCard.owner === address ? '👑 YOU' : addr(currentCard.owner)}
                      </div>
                    )}
                    <input type="number" value={stakeAmount} onChange={e => setStakeAmount(e.target.value)} placeholder="Amount to stake/unstake" style={{ marginTop: 4 }} />
                    <div style={{ display: 'flex', gap: '0.5rem', marginTop: 8 }}>
                      <button className="btn-action" onClick={handleStake} disabled={loading || !stakeAmount} style={{ flex: 1 }}>
                        Stake
                      </button>
                      <button className="btn-action" onClick={handleUnstake} disabled={loading || !stakeAmount} style={{ flex: 1, background: 'rgba(255,80,80,0.2)' }}>
                        Unstake
                      </button>
                      <button className="btn-action" onClick={() => handleClaimRewards(stakeCardId)} disabled={loading} style={{ flex: 'none', width: 'auto', padding: '0 0.75rem' }}>
                        Claim
                      </button>
                    </div>
                  </div>

                  <hr style={{ borderColor: 'rgba(255,255,255,0.1)', margin: '1rem 0' }} />

                  {/* WETH Staking */}
                  <div className="form-group">
                    <label>🔗 WETH Staking (1.5x boost)</label>
                    <div style={{ fontSize: '0.75rem', opacity: 0.7 }}>
                      Staked: {Number(myWethStake).toFixed(4)} WETH · Pending global: {Number(pendingGlobal).toFixed(6)} ETH
                    </div>
                    <input type="number" value={wethStakeAmount} onChange={e => setWethStakeAmount(e.target.value)} placeholder="WETH amount" style={{ marginTop: 4 }} />
                    <div style={{ display: 'flex', gap: '0.5rem', marginTop: 8 }}>
                      <button className="btn-action" onClick={handleStakeWETH} disabled={loading || !wethStakeAmount} style={{ flex: 1 }}>
                        Stake WETH
                      </button>
                      <button className="btn-action" onClick={handleUnstakeWETH} disabled={loading || !wethStakeAmount} style={{ flex: 1, background: 'rgba(255,80,80,0.2)' }}>
                        Unstake WETH
                      </button>
                      <button className="btn-action" onClick={handleClaimWETHRewards} disabled={loading} style={{ flex: 'none', width: 'auto', padding: '0 0.75rem' }}>
                        Claim
                      </button>
                    </div>
                  </div>

                  <hr style={{ borderColor: 'rgba(255,255,255,0.1)', margin: '1rem 0' }} />

                  {/* Swap Stake */}
                  <div className="form-group">
                    <label>🔄 Swap Stake (swap at market rate - 0.6% fees)</label>
                    <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                      <select value={swapStakeFrom} onChange={e => setSwapStakeFrom(Number(e.target.value))} style={{ flex: 1 }}>
                        {cards.filter(c => address && Number(c.myStake) > 0).map(c => {
                          const actualIdx = cards.indexOf(c);
                          return <option key={actualIdx} value={actualIdx}>{c.name} ({c.symbol}) - {Number(c.myStake).toLocaleString()} shares</option>;
                        })}
                      </select>
                      <span>→</span>
                      <select value={swapStakeTo} onChange={e => setSwapStakeTo(Number(e.target.value))} style={{ flex: 1 }}>
                        {cards.filter((_, i) => i !== swapStakeFrom).map(c => {
                          const actualIdx = cards.indexOf(c);
                          return <option key={actualIdx} value={actualIdx}>{c.name} ({c.symbol})</option>;
                        })}
                      </select>
                    </div>
                    {cards[swapStakeFrom] && (
                      <div style={{ fontSize: '0.75rem', opacity: 0.7, marginTop: 4 }}>
                        Your {cards[swapStakeFrom].symbol} stake: {Number(cards[swapStakeFrom].myStake).toLocaleString()} shares
                      </div>
                    )}
                    <input type="number" value={swapStakeAmount} onChange={e => setSwapStakeAmount(e.target.value)} placeholder="Shares to swap" style={{ marginTop: 4 }} />
                    <div className="quick-amounts" style={{ marginTop: 4 }}>
                      <button onClick={() => cards[swapStakeFrom] && setSwapStakeAmount((Number(cards[swapStakeFrom].myStake) * 0.25).toString())}>25%</button>
                      <button onClick={() => cards[swapStakeFrom] && setSwapStakeAmount((Number(cards[swapStakeFrom].myStake) * 0.5).toString())}>50%</button>
                      <button onClick={() => cards[swapStakeFrom] && setSwapStakeAmount((Number(cards[swapStakeFrom].myStake) * 0.75).toString())}>75%</button>
                      <button onClick={() => cards[swapStakeFrom] && setSwapStakeAmount(cards[swapStakeFrom].myStake)}>All</button>
                    </div>
                    <button className="btn-action" onClick={handleSwapStake} disabled={loading || !swapStakeAmount || swapStakeFrom === swapStakeTo} style={{ marginTop: 8 }}>
                      {loading ? 'Swapping…' : 'Swap Stake'}
                    </button>
                  </div>
                </>)}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ─── Bottom 1/4: Terminal ─── */}
      <div className="terminal-area">
        <div className="terminal-toolbar">
          <div className="terminal-toolbar-left">
            <span className="terminal-title">▸ TERMINAL</span>
            <span className="line-count">{filteredLogs.length} lines</span>
          </div>
          <div className="terminal-toolbar-right">
            {(['all', 'transfers', 'ownership', 'errors'] as LogFilter[]).map(f => (
              <button key={f} className={`filter-btn ${filter === f ? 'active' : ''}`} onClick={() => setFilter(f)}>{f.toUpperCase()}</button>
            ))}
            <button className={`toolbar-btn ${scrollLocked ? 'locked' : ''}`} onClick={() => setScrollLocked(!scrollLocked)}>
              {scrollLocked ? '⏸ LOCK' : '▼ AUTO'}
            </button>
            <button className="toolbar-btn" onClick={copyLogs}>COPY</button>
            <button className="toolbar-btn" onClick={() => { setLogs([]); logCounter = 0; }}>CLEAR</button>
          </div>
        </div>
        <div className="terminal-body" ref={termRef}>
          {filteredLogs.map(entry => (
            <div key={entry.id} className={`log-line log-${entry.type}`}>
              <span className="log-num">{entry.id}</span>
              <span className="log-time">{entry.time}</span>
              <span className="log-msg">
                {entry.hash ? (<>{entry.message.replace(entry.hash, '')} <span className="log-hash" onClick={() => navigator.clipboard.writeText(entry.hash!)} title="Copy hash">{entry.hash.slice(0, 10)}…{entry.hash.slice(-8)}</span></>) : entry.message}
              </span>
            </div>
          ))}
        </div>
        <div className="terminal-status">
          <span><span className="status-dot" />Watching events · Anvil 31337</span>
          <span>{cards.length} cards · {isConnected ? addr(address!) : 'not connected'}</span>
        </div>
      </div>
    </div>
  );
}

export default App;
