import bs58 from 'bs58';
import {
  Connection,
  PublicKey,
  TransactionInstruction,
  TransactionMessage,
  VersionedTransaction,
  ComputeBudgetProgram,
} from '@solana/web3.js';
import { log } from './logger.js';

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function createConnection(config) {
  return new Connection(config.rpcUrl, {
    commitment: 'confirmed',
    wsEndpoint: config.wsUrl,
    confirmTransactionInitialTimeout: 60_000,
  });
}

/** Récupère une transaction (avec plusieurs essais : elle n'est pas toujours dispo tout de suite). */
export async function fetchParsedTransaction(connection, signature, { tries = 12, delayMs = 500 } = {}) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const tx = await connection.getParsedTransaction(signature, {
        maxSupportedTransactionVersion: 0,
        commitment: 'confirmed',
      });
      if (tx) return tx;
    } catch (e) {
      lastErr = e;
    }
    await sleep(delayMs * Math.min(1 + i, 4));
  }
  if (lastErr) throw lastErr;
  return null;
}

export class TxFailedError extends Error {
  constructor(signature, err) {
    super(`transaction échouée on-chain (${describeTxError(err)})`);
    this.signature = signature;
    this.txErr = err;
  }
}

export function describeTxError(err) {
  const custom = err?.InstructionError?.[1]?.Custom;
  if (custom !== undefined) {
    if ([6001, 6002, 6003, 6004].includes(custom)) return `probablement slippage dépassé, code ${custom}`;
    return `code ${custom}`;
  }
  if (err?.InstructionError?.[1] === 'InsufficientFunds' || JSON.stringify(err).includes('Insufficient')) return 'fonds insuffisants';
  return JSON.stringify(err);
}

/**
 * Envoie une transaction signée et la renvoie régulièrement jusqu'à confirmation
 * (méthode la plus fiable pour faire passer un tx quand le réseau est chargé).
 */
export async function sendAndConfirm(connection, tx, lastValidBlockHeight) {
  const raw = tx.serialize();
  const signature = bs58.encode(tx.signatures[0]);
  if (!lastValidBlockHeight) lastValidBlockHeight = (await connection.getBlockHeight('confirmed')) + 150;

  const send = () =>
    connection.sendRawTransaction(raw, { skipPreflight: true, maxRetries: 0 }).catch((e) => {
      log.debug(`envoi ${signature.slice(0, 8)}… : ${e.message}`);
    });

  await send();
  let lastSend = Date.now();
  let loops = 0;
  for (;;) {
    await sleep(800);
    loops++;
    const status = await connection
      .getSignatureStatuses([signature])
      .then((r) => r.value[0])
      .catch(() => null);
    if (status && (status.confirmationStatus === 'confirmed' || status.confirmationStatus === 'finalized')) {
      if (status.err) throw new TxFailedError(signature, status.err);
      return signature;
    }
    if (loops % 3 === 0) {
      const height = await connection.getBlockHeight('confirmed').catch(() => 0);
      if (height > lastValidBlockHeight) {
        const final = await connection
          .getSignatureStatuses([signature], { searchTransactionHistory: true })
          .then((r) => r.value[0])
          .catch(() => null);
        if (final && !final.err && final.confirmationStatus) return signature;
        if (final?.err) throw new TxFailedError(signature, final.err);
        const e = new Error('transaction expirée sans confirmation (réseau chargé ? augmente PRIORITY_FEE_SOL)');
        e.signature = signature;
        throw e;
      }
    }
    if (Date.now() - lastSend >= 2000) {
      send();
      lastSend = Date.now();
    }
  }
}

/** Soldes des comptes de token d'un wallet pour un mint (SPL Token et Token-2022). */
export async function getTokenAccounts(connection, owner, mint) {
  const res = await connection.getParsedTokenAccountsByOwner(owner, { mint: new PublicKey(mint) }, 'confirmed');
  let amount = 0n;
  let decimals = null;
  const accounts = [];
  for (const { pubkey, account } of res.value) {
    const info = account.data?.parsed?.info;
    if (!info) continue;
    const a = BigInt(info.tokenAmount.amount);
    amount += a;
    decimals = info.tokenAmount.decimals;
    accounts.push({ pubkey, programId: account.owner, amount: a });
  }
  return { amount, decimals, accounts };
}

/** Ferme les comptes de token vides pour récupérer le "loyer" (~0.002 SOL par compte). */
export async function closeTokenAccounts(connection, keypair, accounts, priorityMicroLamports = 50_000) {
  if (!accounts.length) return null;
  const ixs = [
    ComputeBudgetProgram.setComputeUnitLimit({ units: 20_000 + 5_000 * accounts.length }),
    ComputeBudgetProgram.setComputeUnitPrice({ microLamports: priorityMicroLamports }),
  ];
  for (const acc of accounts) {
    ixs.push(
      new TransactionInstruction({
        programId: acc.programId,
        keys: [
          { pubkey: acc.pubkey, isSigner: false, isWritable: true },
          { pubkey: keypair.publicKey, isSigner: false, isWritable: true },
          { pubkey: keypair.publicKey, isSigner: true, isWritable: false },
        ],
        data: Buffer.from([9]), // CloseAccount
      }),
    );
  }
  const { blockhash, lastValidBlockHeight } = await connection.getLatestBlockhash('confirmed');
  const message = new TransactionMessage({
    payerKey: keypair.publicKey,
    recentBlockhash: blockhash,
    instructions: ixs,
  }).compileToV0Message();
  const tx = new VersionedTransaction(message);
  tx.sign([keypair]);
  return sendAndConfirm(connection, tx, lastValidBlockHeight);
}
