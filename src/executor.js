import { LAMPORTS_PER_SOL } from '@solana/web3.js';
import { SOL_MINT } from './constants.js';
import { log } from './logger.js';
import { computeDeltas, toUi } from './parser.js';
import {
  sleep,
  sendAndConfirm,
  fetchParsedTransaction,
  getTokenAccounts,
  closeTokenAccounts,
  TxFailedError,
} from './solana.js';
import { NoRouteError } from './swap.js';

export class InsufficientFundsError extends Error {}

/**
 * Exécute les achats / ventes. En mode simulation (DRY_RUN=true) rien n'est envoyé :
 * on demande juste un prix à Jupiter et on tient un portefeuille "papier".
 */
export class Executor {
  constructor({ config, connection, jupiter, pumpPortal, state }) {
    this.config = config;
    this.connection = connection;
    this.jupiter = jupiter;
    this.pumpPortal = pumpPortal;
    this.state = state;
    this.pendingLamports = 0;
  }

  get live() {
    return !this.config.dryRun;
  }

  async solBalance() {
    if (!this.config.owner) return null;
    return this.connection.getBalance(this.config.owner, 'confirmed');
  }

  /** Solde du token : réel en mode live, "papier" en simulation. */
  async tokenBalance(mint) {
    if (!this.live) {
      const pos = this.state.getPosition(mint);
      return { amount: BigInt(pos?.paperAmount ?? '0'), decimals: pos?.decimals ?? 0, accounts: [] };
    }
    return getTokenAccounts(this.connection, this.config.owner, mint);
  }

  async buy(mint) {
    const lamports = this.config.buyLamports;
    const slippageBps = this.config.slippageBps;

    if (!this.live) {
      const q = await this.jupiter.quote({ inputMint: SOL_MINT, outputMint: mint, amount: lamports, slippageBps });
      return { simulated: true, route: 'simulation', solSpent: lamports, tokens: BigInt(q.outAmount) };
    }

    const balance = await this.solBalance();
    const needed = lamports + this.config.minSolReserveLamports + this.pendingLamports;
    if (balance < needed) {
      throw new InsufficientFundsError(
        `solde insuffisant : ${(balance / LAMPORTS_PER_SOL).toFixed(4)} SOL (il faut ${(needed / LAMPORTS_PER_SOL).toFixed(4)} SOL avec la réserve MIN_SOL_RESERVE)`,
      );
    }

    this.pendingLamports += lamports;
    try {
      return await this.withRetries('achat', async () => {
        let tx;
        let lastValidBlockHeight;
        let route = 'Jupiter';
        let quotedOut = 0n;
        try {
          const quote = await this.jupiter.quote({ inputMint: SOL_MINT, outputMint: mint, amount: lamports, slippageBps });
          quotedOut = BigInt(quote.outAmount);
          ({ tx, lastValidBlockHeight } = await this.jupiter.swapTransaction({
            quote,
            userPublicKey: this.config.owner.toBase58(),
            priorityFeeLamports: this.config.priorityFeeLamports,
          }));
        } catch (e) {
          if (!(e instanceof NoRouteError) || !this.config.pumpPortalFallback) throw e;
          log.debug(`${e.message} -> essai via PumpPortal`);
          route = 'PumpPortal';
          tx = await this.pumpPortal.transaction({
            publicKey: this.config.owner.toBase58(),
            action: 'buy',
            mint,
            amount: lamports / LAMPORTS_PER_SOL,
            denominatedInSol: true,
            slippagePct: slippageBps / 100,
            priorityFeeSol: this.config.priorityFeeSol,
          });
        }
        tx.sign([this.config.keypair]);
        const signature = await sendAndConfirm(this.connection, tx, lastValidBlockHeight);
        const deltas = await this.ownDeltas(signature, mint);
        return {
          signature,
          route,
          solSpent: deltas ? -deltas.lamports : lamports,
          tokens: deltas?.tokens ?? quotedOut,
          decimals: deltas?.decimals,
        };
      });
    } finally {
      this.pendingLamports -= lamports;
    }
  }

  async sell(mint, amount, { full = false, decimals = 0 } = {}) {
    const slippageBps = this.config.sellSlippageBps;

    if (!this.live) {
      const q = await this.jupiter.quote({ inputMint: mint, outputMint: SOL_MINT, amount, slippageBps });
      return { simulated: true, route: 'simulation', solReceived: Number(q.outAmount), tokens: amount };
    }

    let attempt = 0;
    const result = await this.withRetries('vente', async () => {
      // Avant un nouvel essai, on relit le solde (le tx précédent a pu passer malgré une erreur)
      let toSell = amount;
      if (attempt++ > 0) {
        const { amount: bal } = await this.tokenBalance(mint);
        if (bal === 0n) return { signature: null, route: 'déjà vendu', solReceived: 0, tokens: 0n };
        if (full || toSell > bal) toSell = bal;
      }

      let tx;
      let lastValidBlockHeight;
      let route = 'Jupiter';
      try {
        const quote = await this.jupiter.quote({ inputMint: mint, outputMint: SOL_MINT, amount: toSell, slippageBps });
        ({ tx, lastValidBlockHeight } = await this.jupiter.swapTransaction({
          quote,
          userPublicKey: this.config.owner.toBase58(),
          priorityFeeLamports: this.config.priorityFeeLamports,
        }));
      } catch (e) {
        if (!(e instanceof NoRouteError) || !this.config.pumpPortalFallback) throw e;
        log.debug(`${e.message} -> essai via PumpPortal`);
        route = 'PumpPortal';
        tx = await this.pumpPortal.transaction({
          publicKey: this.config.owner.toBase58(),
          action: 'sell',
          mint,
          amount: full ? '100%' : toUi(toSell, decimals),
          denominatedInSol: false,
          slippagePct: slippageBps / 100,
          priorityFeeSol: this.config.priorityFeeSol,
        });
      }
      tx.sign([this.config.keypair]);
      const signature = await sendAndConfirm(this.connection, tx, lastValidBlockHeight);
      const deltas = await this.ownDeltas(signature, mint);
      return {
        signature,
        route,
        solReceived: deltas ? deltas.lamports : 0,
        tokens: deltas ? -deltas.tokens : toSell,
      };
    });

    if (full && this.config.closeEmptyAccounts) await this.closeEmpty(mint);
    return result;
  }

  /** Récupère les ~0.002 SOL de "loyer" des comptes de token vidés. Jamais bloquant. */
  async closeEmpty(mint) {
    try {
      const { accounts } = await getTokenAccounts(this.connection, this.config.owner, mint);
      const empty = accounts.filter((a) => a.amount === 0n);
      if (!empty.length) return;
      const sig = await closeTokenAccounts(this.connection, this.config.keypair, empty);
      log.debug(`compte(s) de token fermé(s), loyer récupéré : ${sig}`);
    } catch (e) {
      log.debug(`fermeture du compte de token impossible (${e.message}) — pas grave`);
    }
  }

  async withRetries(label, fn) {
    const attempts = 1 + this.config.maxRetries;
    for (let i = 1; ; i++) {
      try {
        return await fn();
      } catch (e) {
        const retryable = !(e instanceof NoRouteError) && !(e instanceof InsufficientFundsError);
        if (!retryable || i >= attempts) throw e;
        const where = e instanceof TxFailedError ? ` (tx ${e.signature})` : '';
        log.warn(`${label} : essai ${i}/${attempts} raté : ${e.message}${where} -> nouvel essai`);
        await sleep(400);
      }
    }
  }

  /** Ce que notre wallet a réellement dépensé / reçu dans une transaction. */
  async ownDeltas(signature, mint) {
    try {
      const tx = await fetchParsedTransaction(this.connection, signature, { tries: 6 });
      if (!tx) return null;
      const d = computeDeltas(tx, this.config.owner.toBase58());
      const t = d.tokens.get(mint);
      return { lamports: Number(d.lamports), tokens: t ? t.post - t.pre : 0n, decimals: t?.decimals };
    } catch {
      return null;
    }
  }
}
