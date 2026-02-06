import { http, createConfig } from 'wagmi';
import { injected } from 'wagmi/connectors';

// Anvil local testnet as custom chain
export const anvilChain = {
  id: 31337,
  name: 'Anvil Local',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: {
    default: { http: ['http://192.168.0.82:8545'] },
  },
  blockExplorers: {
    default: { name: 'Local', url: 'http://localhost:8545' },
  },
} as const;

export const config = createConfig({
  chains: [anvilChain],
  connectors: [
    injected(), // Rabby, MetaMask, etc.
  ],
  transports: {
    [anvilChain.id]: http('http://192.168.0.82:8545'),
  },
});
