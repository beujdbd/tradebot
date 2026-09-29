import { Keypair, PublicKey } from '@solana/web3.js';

export const PUMP = '6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P';
export const SYSTEM = '11111111111111111111111111111111';
export const TOKEN = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
export const WSOL = 'So11111111111111111111111111111111111111112';
export const USDC = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

export const newKey = () => Keypair.generate().publicKey.toBase58();

let counter = 0;
export const fakeSig = () => `sig${++counter}${'x'.repeat(40)}`;

/**
 * Construit une transaction au format "jsonParsed" renvoyé par getParsedTransaction.
 * accounts : [{ key, signer, pre, post }] (lamports) ; tokens : [{ owner, mint, pre, post, decimals }]
 */
export function makeTx({ signature = fakeSig(), accounts, tokens = [], programs = [PUMP], fee = 5000, err = null, blockTime } = {}) {
  const accountKeys = accounts.map((a) => ({ pubkey: new PublicKey(a.key), signer: !!a.signer, writable: true }));
  const preTokenBalances = [];
  const postTokenBalances = [];
  tokens.forEach((t, i) => {
    const accountIndex = accounts.length + i;
    const bal = (amount) => ({
      accountIndex,
      mint: t.mint,
      owner: t.owner,
      programId: TOKEN,
      uiTokenAmount: { amount: String(amount), decimals: t.decimals ?? 6, uiAmount: null, uiAmountString: '' },
    });
    if (t.pre !== null && t.pre !== undefined) preTokenBalances.push(bal(t.pre));
    if (t.post !== null && t.post !== undefined) postTokenBalances.push(bal(t.post));
  });
  return {
    slot: 1,
    blockTime: blockTime ?? Math.floor(Date.now() / 1000),
    transaction: {
      signatures: [signature],
      message: {
        accountKeys,
        instructions: programs.map((p) => ({ programId: new PublicKey(p), accounts: [], data: '' })),
      },
    },
    meta: {
      err,
      fee,
      preBalances: accounts.map((a) => a.pre),
      postBalances: accounts.map((a) => a.post),
      preTokenBalances,
      postTokenBalances,
      innerInstructions: [],
      logMessages: [],
    },
  };
}
