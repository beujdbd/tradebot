import { LAMPORTS_PER_SOL } from '@solana/web3.js';

const nf = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 });

export const short = (s) => (s ? `${s.slice(0, 4)}…${s.slice(-4)}` : '?');
export const sol = (lamports) => (Number(lamports) / LAMPORTS_PER_SOL).toFixed(4);
export const tokens = (raw, decimals) => nf.format(Number(raw) / 10 ** (decimals ?? 0));
export const pct = (ratio) => `${nf.format(ratio * 100)}%`;
export const txLink = (sig) => `https://solscan.io/tx/${sig}`;
export const tokenLink = (mint) => `https://dexscreener.com/solana/${mint}`;

export function signedSol(lamports) {
  const v = Number(lamports) / LAMPORTS_PER_SOL;
  return `${v >= 0 ? '+' : ''}${v.toFixed(4)}`;
}
