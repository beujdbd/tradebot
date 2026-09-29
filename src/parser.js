import { SOL_MINT, STABLE_MINTS, BASIC_PROGRAMS, DEX_NAMES } from './constants.js';

// En dessous de ce montant, une variation de SOL est considérée comme des frais / du bruit.
const SOL_NOISE_LAMPORTS = 100_000n; // 0.0001 SOL
const PCT_PRECISION = 1_000_000n;

const toBase58 = (k) => (typeof k === 'string' ? k : (k.pubkey ?? k).toBase58?.() ?? String(k.pubkey ?? k));

/**
 * Variations de solde (SOL + tokens) d'un wallet dans une transaction "jsonParsed".
 */
export function computeDeltas(tx, owner) {
  const accountKeys = tx.transaction.message.accountKeys;
  const keys = accountKeys.map(toBase58);
  const meta = tx.meta;
  const idx = keys.indexOf(owner);

  const tokens = new Map();
  const add = (list, field) => {
    for (const b of list || []) {
      if (b.owner !== owner) continue;
      const entry = tokens.get(b.mint) || { pre: 0n, post: 0n, decimals: b.uiTokenAmount.decimals };
      entry[field] += BigInt(b.uiTokenAmount.amount);
      tokens.set(b.mint, entry);
    }
  };
  add(meta.preTokenBalances, 'pre');
  add(meta.postTokenBalances, 'post');

  let lamports = 0n;
  let isSigner = false;
  if (idx >= 0) {
    lamports = BigInt(meta.postBalances[idx]) - BigInt(meta.preBalances[idx]);
    isSigner = typeof accountKeys[idx] === 'object' && 'signer' in accountKeys[idx] ? !!accountKeys[idx].signer : idx === 0;
  }
  return { tokens, lamports, fee: BigInt(meta.fee || 0), isSigner, isFeePayer: idx === 0 };
}

/** Liste des programmes appelés (instructions + instructions internes). */
export function invokedPrograms(tx) {
  const ids = new Set();
  for (const ix of tx.transaction.message.instructions || []) ids.add(toBase58(ix.programId));
  for (const inner of tx.meta?.innerInstructions || []) {
    for (const ix of inner.instructions || []) ids.add(toBase58(ix.programId));
  }
  return ids;
}

export function dexName(programs) {
  for (const p of programs) if (DEX_NAMES[p]) return DEX_NAMES[p];
  for (const p of programs) if (!BASIC_PROGRAMS.has(p)) return 'DEX';
  return null;
}

function ratio(part, whole) {
  if (whole <= 0n) return 1;
  const r = Number((part * PCT_PRECISION) / whole) / Number(PCT_PRECISION);
  return Math.min(1, Math.max(0, r));
}

/**
 * Analyse une transaction du trader et renvoie les achats / ventes détectés.
 *
 * - ACHAT : le solde d'un token augmente ET le trader a payé (SOL, USDC/USDT ou un autre token) via un DEX.
 * - VENTE : le solde d'un token diminue via un DEX. Le pourcentage vendu = quantité vendue / solde avant la vente.
 * Les simples transferts (envoi / réception de tokens, airdrops) sont ignorés.
 */
export function analyzeTrade(tx, trader) {
  const signature = tx?.transaction?.signatures?.[0];
  const base = { signature, slot: tx?.slot, blockTime: tx?.blockTime ?? null, events: [], dex: null };
  if (!tx?.meta) return { ...base, skip: 'transaction introuvable' };
  if (tx.meta.err) return { ...base, skip: 'transaction échouée' };

  const d = computeDeltas(tx, trader);
  if (!d.isSigner) return { ...base, skip: 'le trader n\'a pas signé (transfert reçu / airdrop)' };

  const programs = invokedPrograms(tx);
  const swapLike = [...programs].some((p) => !BASIC_PROGRAMS.has(p));
  base.dex = dexName(programs);
  if (!swapLike) return { ...base, skip: 'simple transfert, pas un swap' };

  // Variation de SOL hors frais réseau (le SOL "wrappé" compte comme du SOL)
  let solDelta = d.lamports + (d.isFeePayer ? d.fee : 0n);
  const wsol = d.tokens.get(SOL_MINT);
  if (wsol) {
    solDelta += wsol.post - wsol.pre;
    d.tokens.delete(SOL_MINT);
  }

  let stableSpent = false;
  const increased = [];
  const decreased = [];
  for (const [mint, t] of d.tokens) {
    const diff = t.post - t.pre;
    if (diff === 0n) continue;
    if (STABLE_MINTS.has(mint)) {
      if (diff < 0n) stableSpent = true;
      continue;
    }
    (diff > 0n ? increased : decreased).push({ mint, ...t, diff });
  }

  const paidSol = solDelta < -SOL_NOISE_LAMPORTS;
  const gotSol = solDelta > SOL_NOISE_LAMPORTS;
  const events = [];

  for (const t of decreased) {
    const sold = t.pre - t.post;
    events.push({
      type: 'sell',
      mint: t.mint,
      decimals: t.decimals,
      pct: t.post === 0n ? 1 : ratio(sold, t.pre),
      soldRaw: sold,
      preRaw: t.pre,
      postRaw: t.post,
      solReceived: gotSol ? solDelta : 0n,
    });
  }
  for (const t of increased) {
    if (!(paidSol || stableSpent || decreased.length > 0)) continue;
    events.push({
      type: 'buy',
      mint: t.mint,
      decimals: t.decimals,
      amountRaw: t.diff,
      solSpent: paidSol ? -solDelta : 0n,
    });
  }

  return { ...base, events, solDelta, skip: events.length ? null : 'aucun achat/vente de token' };
}

/** Montant brut (BigInt) -> nombre lisible. */
export function toUi(raw, decimals) {
  return Number(raw) / 10 ** decimals;
}
