import { log } from './logger.js';
import { analyzeTrade } from './parser.js';
import { fetchParsedTransaction, sleep } from './solana.js';
import { short, sol, tokens, pct, txLink, tokenLink, signedSol } from './format.js';

const SEEN_LIMIT = 5000;
const HEARTBEAT_MS = 15 * 60 * 1000;
const MAX_PARALLEL_FETCHES = 8;

/** Limite le nombre d'appels RPC simultanés (évite de se faire bloquer par le RPC). */
function createLimiter(max) {
  let active = 0;
  const queue = [];
  const next = () => {
    if (active >= max || !queue.length) return;
    active++;
    const { fn, resolve, reject } = queue.shift();
    fn()
      .then(resolve, reject)
      .finally(() => {
        active--;
        next();
      });
  };
  return (fn) =>
    new Promise((resolve, reject) => {
      queue.push({ fn, resolve, reject });
      next();
    });
}

/**
 * Surveille le wallet du trader (websocket temps réel + polling de secours)
 * et copie chacun de ses achats / ventes.
 */
export class CopyBot {
  constructor({ config, connection, executor, state, jupiter, notify = () => {} }) {
    this.config = config;
    this.connection = connection;
    this.executor = executor;
    this.state = state;
    this.jupiter = jupiter;
    this.notify = notify;

    this.seen = new Set();
    this.fetchLimit = createLimiter(MAX_PARALLEL_FETCHES);
    this.orderChain = Promise.resolve();
    this.mintQueues = new Map();
    this.symbols = new Map();
    this.names = new Map();
    this.cursor = null;
    this.stopped = false;
    this.pollFailures = 0;
    this.stats = { detected: 0, buys: 0, sells: 0, errors: 0 };
    this.tag = config.dryRun ? '[SIMULATION] ' : '';
  }

  async start() {
    for (let i = 1; ; i++) {
      try {
        await this.initCursor();
        break;
      } catch (e) {
        if (i >= 5) throw new Error(`le RPC ne répond pas (${e.message}). Vérifie RPC_URL dans .env`);
        log.warn(`RPC injoignable (${e.message}), nouvel essai dans 3 s…`);
        await sleep(3000);
      }
    }
    this.subscribe();
    this.pollPromise = this.pollLoop();
    this.heartbeatTimer = setInterval(() => this.heartbeat(), HEARTBEAT_MS);
    this.heartbeatTimer.unref?.();
  }

  async stop() {
    this.stopped = true;
    clearInterval(this.heartbeatTimer);
    if (this.subId !== undefined) await this.connection.removeOnLogsListener(this.subId).catch(() => {});
    // on laisse finir les trades en cours
    await Promise.allSettled([...this.mintQueues.values()]);
  }

  /** Point de départ : on ne recopie pas l'historique, sauf les ventes manquées pendant que le bot était éteint. */
  async initCursor() {
    const saved = this.state.cursor;
    if (saved && this.config.catchUpSells) {
      const sigs = await this.connection.getSignaturesForAddress(this.config.target, { until: saved, limit: 1000 });
      this.cursor = sigs[0]?.signature ?? saved;
      const missed = sigs.filter((s) => !s.err).reverse();
      if (missed.length) {
        log.info(`${missed.length} transaction(s) du trader pendant que le bot était éteint : je rattrape ses ventes.`);
        for (const s of missed) this.onSignature(s.signature, { source: 'rattrapage' });
      }
    } else {
      const sigs = await this.connection.getSignaturesForAddress(this.config.target, { limit: 1 });
      this.cursor = sigs[0]?.signature ?? null;
    }
    this.state.cursor = this.cursor;
  }

  subscribe() {
    try {
      this.subId = this.connection.onLogs(
        this.config.target,
        (logs) => {
          if (!logs.err) this.onSignature(logs.signature, { source: 'ws' });
        },
        'confirmed',
      );
      log.ok('Connexion temps réel (websocket) active.');
    } catch (e) {
      log.warn(`Websocket indisponible (${e.message}) : je surveille par polling uniquement.`);
    }
  }

  async pollLoop() {
    while (!this.stopped) {
      try {
        const sigs = await this.connection.getSignaturesForAddress(this.config.target, {
          until: this.cursor ?? undefined,
          limit: 100,
        });
        if (sigs.length) {
          this.cursor = sigs[0].signature;
          for (const s of sigs.slice().reverse()) if (!s.err) this.onSignature(s.signature, { source: 'poll' });
          this.state.cursor = this.cursor;
        }
        if (this.pollFailures >= 3) log.ok('Connexion au RPC rétablie.');
        this.pollFailures = 0;
      } catch (e) {
        this.pollFailures++;
        if (this.pollFailures === 3 || this.pollFailures % 30 === 0) {
          log.warn(`Le RPC ne répond pas bien (${e.message}). Je continue d'essayer…`);
        }
      }
      await sleep(this.config.pollIntervalMs);
    }
  }

  /**
   * Nouvelle transaction du trader. Le téléchargement démarre tout de suite, mais les trades sont
   * traités dans l'ordre d'arrivée (un achat puis une vente rapide restent dans le bon ordre).
   */
  onSignature(signature, { source } = {}) {
    if (this.seen.has(signature) || this.state.wasProcessed(signature)) return;
    this.seen.add(signature);
    if (this.seen.size > SEEN_LIMIT) this.seen.delete(this.seen.values().next().value);

    const analysis = this.fetchLimit(() => fetchParsedTransaction(this.connection, signature)).then((tx) =>
      tx ? analyzeTrade(tx, this.config.targetStr) : null,
    );
    analysis.catch(() => {}); // l'erreur est gérée plus bas, dans l'ordre d'arrivée
    this.orderChain = this.orderChain.then(async () => {
      let res;
      try {
        res = await analysis;
      } catch (e) {
        log.warn(`Impossible de lire la transaction ${short(signature)} : ${e.message}`);
        return;
      }
      if (!res) return log.debug(`tx ${short(signature)} introuvable`);
      if (!res.events.length) return log.debug(`tx ${short(signature)} ignorée (${source}) : ${res.skip}`);
      this.dispatch(res);
    });
  }

  dispatch(res) {
    this.state.markProcessed(res.signature);
    // les ventes d'abord (swap token -> token : on vend X puis on achète Y)
    const events = [...res.events].sort((a, b) => (a.type === b.type ? 0 : a.type === 'sell' ? -1 : 1));
    for (const ev of events) {
      if (this.config.ignoreMints.has(ev.mint)) continue;
      this.stats.detected++;
      this.symbol(ev.mint); // lance la recherche du nom en parallèle
      this.enqueue(ev.mint, () => (ev.type === 'buy' ? this.handleBuy(ev, res) : this.handleSell(ev, res)));
    }
  }

  /** Une file par token : un achat et une vente du même token ne se chevauchent jamais. */
  enqueue(mint, fn) {
    const prev = this.mintQueues.get(mint) || Promise.resolve();
    const next = prev.then(fn).catch((e) => log.error(`Erreur inattendue (${short(mint)}) : ${e.stack || e.message}`));
    this.mintQueues.set(mint, next);
    next.then(() => {
      if (this.mintQueues.get(mint) === next) this.mintQueues.delete(mint);
    });
    return next;
  }

  async handleBuy(ev, res) {
    const { config } = this;
    const name = this.nameOf(ev.mint);
    const via = res.dex ? ` via ${res.dex}` : '';
    const paid = ev.solSpent > 0n ? `${sol(ev.solSpent)} SOL` : 'un autre token';
    log.trader(`a ACHETÉ ${name} pour ${paid}${via}  ${tokenLink(ev.mint)}`);

    const age = res.blockTime ? Date.now() / 1000 - res.blockTime : 0;
    if (age > config.maxTradeAgeSec) {
      return log.warn(`Achat ignoré : il date de ${Math.round(age)} s (limite MAX_TRADE_AGE_SEC=${config.maxTradeAgeSec}).`);
    }
    if (config.minTraderBuyLamports > 0 && ev.solSpent > 0n && ev.solSpent < BigInt(config.minTraderBuyLamports)) {
      return log.info(`Achat ignoré : le trader a mis moins que MIN_TRADER_BUY_SOL.`);
    }
    const pos = this.state.getPosition(ev.mint);
    if (config.maxBuysPerToken > 0 && pos?.open && pos.roundBuys >= config.maxBuysPerToken) {
      return log.info(`Achat ignoré : déjà ${pos.roundBuys} achat(s) de ${name} (MAX_BUYS_PER_TOKEN=${config.maxBuysPerToken}).`);
    }

    const t0 = Date.now();
    try {
      const r = await this.executor.buy(ev.mint);
      const decimals = r.decimals ?? ev.decimals;
      const symbol = await this.symbolWithin(ev.mint, 2000);
      this.state.recordBuy(ev.mint, { ...r, decimals, symbol, simulated: !!r.simulated });
      this.stats.buys++;
      const link = r.signature ? `  ${txLink(r.signature)}` : '';
      log.buy(
        `${this.tag}${symbol} : ${sol(r.solSpent)} SOL -> ${tokens(r.tokens, decimals)} tokens (${r.route}, ${((Date.now() - t0) / 1000).toFixed(1)} s)${link}`,
      );
      this.notify(`🟢 ${this.tag}ACHAT ${symbol}\n${sol(r.solSpent)} SOL -> ${tokens(r.tokens, decimals)} tokens\n${tokenLink(ev.mint)}`);
    } catch (e) {
      this.stats.errors++;
      log.error(`${this.tag}Achat de ${name} raté : ${e.message}`);
      this.notify(`⚠️ Achat de ${name} raté : ${e.message}`);
    }
  }

  async handleSell(ev, res) {
    const { config } = this;
    const name = this.nameOf(ev.mint);
    const via = res.dex ? ` via ${res.dex}` : '';
    log.trader(`a VENDU ${pct(ev.pct)} de ses ${name}${ev.solReceived > 0n ? ` pour ${sol(ev.solReceived)} SOL` : ''}${via}`);

    if (!config.copySells) return log.info('Vente non copiée (COPY_SELLS=false).');
    const pos = this.state.getPosition(ev.mint);
    if (config.onlySellBotPositions && !pos?.open) {
      return log.info(`Rien à faire : tu n'as pas de ${name} acheté par le bot.`);
    }

    let bal = await this.executor.tokenBalance(ev.mint);
    // juste après un achat, le RPC peut encore afficher un solde vide : on laisse une chance
    for (let i = 0; i < 3 && bal.amount === 0n && this.executor.live && pos?.open; i++) {
      await sleep(1500);
      bal = await this.executor.tokenBalance(ev.mint);
    }
    if (bal.amount === 0n) {
      this.state.markClosed(ev.mint);
      return log.info(`Rien à vendre : ton solde de ${name} est à 0.`);
    }

    const full = ev.pct >= 0.99;
    const amount = full ? bal.amount : (bal.amount * BigInt(Math.round(ev.pct * 1_000_000))) / 1_000_000n;
    if (amount <= 0n) return;
    const decimals = bal.decimals ?? pos?.decimals ?? ev.decimals;

    const t0 = Date.now();
    try {
      const r = await this.executor.sell(ev.mint, amount, { full, decimals });
      const p = this.state.recordSell(ev.mint, { ...r, pct: ev.pct, full, simulated: !!r.simulated });
      this.stats.sells++;
      const link = r.signature ? `  ${txLink(r.signature)}` : '';
      log.sell(
        `${this.tag}${name} : ${full ? 'TOUT' : pct(ev.pct)} vendu (${tokens(amount, decimals)} tokens) -> ${sol(r.solReceived)} SOL (${r.route}, ${((Date.now() - t0) / 1000).toFixed(1)} s)${link}`,
      );
      let pnlText = '';
      if (!p.open) {
        const pnl = p.solReceived - p.solSpent;
        const ratio = p.solSpent > 0 ? pnl / p.solSpent : 0;
        pnlText = `\nPosition fermée. Résultat total sur ${name} : ${signedSol(pnl)} SOL (${ratio >= 0 ? '+' : ''}${pct(ratio)})`;
        (pnl >= 0 ? log.ok : log.warn)(pnlText.trim());
      }
      this.notify(`🔴 ${this.tag}VENTE ${name} (${full ? '100%' : pct(ev.pct)})\n-> ${sol(r.solReceived)} SOL${pnlText}`);
    } catch (e) {
      this.stats.errors++;
      log.error(`${this.tag}Vente de ${name} ratée : ${e.message}`);
      this.notify(`⚠️ Vente de ${name} ratée : ${e.message}\nVends manuellement si besoin : ${tokenLink(ev.mint)}`);
    }
  }

  /** Recherche (une seule fois) le symbole du token, sans jamais bloquer un trade. */
  symbol(mint) {
    if (!this.symbols.has(mint)) {
      const saved = this.state.getPosition(mint)?.symbol;
      const lookup = saved ? Promise.resolve(saved) : this.jupiter.tokenInfo(mint).then((i) => i?.symbol || null);
      this.symbols.set(
        mint,
        lookup
          .then((sym) => {
            if (sym) this.names.set(mint, sym);
            return sym || short(mint);
          })
          .catch(() => short(mint)),
      );
    }
    return this.symbols.get(mint);
  }

  /** Nom déjà connu (ou adresse raccourcie), instantané. */
  nameOf(mint) {
    return this.names.get(mint) || short(mint);
  }

  /** Nom du token en attendant au plus `ms` millisecondes. */
  symbolWithin(mint, ms) {
    return Promise.race([this.symbol(mint), sleep(ms).then(() => this.nameOf(mint))]);
  }

  async heartbeat() {
    const s = this.stats;
    let balance = '';
    if (this.executor.live) {
      const b = await this.executor.solBalance().catch(() => null);
      if (b !== null) balance = ` | solde : ${sol(b)} SOL`;
    }
    const open = Object.values(this.state.positions).filter((p) => p.open).length;
    log.info(
      `${this.tag}Toujours en écoute. Trades détectés : ${s.detected}, achats : ${s.buys}, ventes : ${s.sells}, erreurs : ${s.errors}, positions ouvertes : ${open}${balance}`,
    );
  }
}
