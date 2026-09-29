import fs from 'node:fs';
import path from 'node:path';

const HISTORY_LIMIT = 50;
const PROCESSED_LIMIT = 300;

/**
 * Sauvegarde locale (data/state.json) : positions ouvertes, stats par token, dernier tx vu du trader.
 * La simulation et le mode réel ont chacun leur fichier.
 */
export class State {
  constructor(dataDir, { dryRun }) {
    this.file = path.join(dataDir, dryRun ? 'state-simulation.json' : 'state.json');
    this.data = { version: 1, cursor: null, processed: [], positions: {} };
    try {
      const loaded = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      this.data = { ...this.data, ...loaded, positions: loaded.positions || {}, processed: loaded.processed || [] };
    } catch (e) {
      if (e.code !== 'ENOENT') throw new Error(`Impossible de lire ${this.file} : ${e.message}`);
    }
  }

  save() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    fs.renameSync(tmp, this.file);
  }

  get cursor() {
    return this.data.cursor;
  }

  set cursor(sig) {
    if (sig && sig !== this.data.cursor) {
      this.data.cursor = sig;
      this.save();
    }
  }

  /** Tx du trader déjà copiés (évite de recopier un trade après un redémarrage). */
  wasProcessed(sig) {
    return this.data.processed.includes(sig);
  }

  markProcessed(sig) {
    if (this.wasProcessed(sig)) return;
    this.data.processed.push(sig);
    if (this.data.processed.length > PROCESSED_LIMIT) this.data.processed.splice(0, this.data.processed.length - PROCESSED_LIMIT);
    this.save();
  }

  get positions() {
    return this.data.positions;
  }

  getPosition(mint) {
    return this.data.positions[mint] || null;
  }

  ensurePosition(mint, { symbol, decimals } = {}) {
    let p = this.data.positions[mint];
    if (!p) {
      p = this.data.positions[mint] = {
        mint,
        symbol: symbol || null,
        decimals: decimals ?? null,
        open: false,
        buys: 0,
        roundBuys: 0,
        sells: 0,
        solSpent: 0,
        solReceived: 0,
        paperAmount: '0',
        openedAt: null,
        updatedAt: null,
        history: [],
      };
    }
    if (symbol && !p.symbol) p.symbol = symbol;
    if (decimals !== undefined && decimals !== null) p.decimals = decimals;
    return p;
  }

  recordBuy(mint, { solSpent, tokens, decimals, symbol, signature, simulated }) {
    const p = this.ensurePosition(mint, { symbol, decimals });
    const now = new Date().toISOString();
    if (!p.open) {
      p.open = true;
      p.roundBuys = 0;
      p.openedAt = now;
    }
    p.buys++;
    p.roundBuys++;
    p.solSpent += solSpent;
    if (simulated) p.paperAmount = (BigInt(p.paperAmount) + tokens).toString();
    p.updatedAt = now;
    this.pushHistory(p, { t: now, type: 'buy', sig: signature || null, sol: solSpent, tokens: tokens.toString() });
    this.save();
    return p;
  }

  recordSell(mint, { solReceived, tokens, pct, full, signature, simulated }) {
    const p = this.ensurePosition(mint);
    const now = new Date().toISOString();
    p.sells++;
    p.solReceived += solReceived;
    if (simulated) {
      const left = BigInt(p.paperAmount) - tokens;
      p.paperAmount = (left > 0n ? left : 0n).toString();
    }
    if (full || (simulated && p.paperAmount === '0')) {
      p.open = false;
      p.roundBuys = 0;
    }
    p.updatedAt = now;
    this.pushHistory(p, { t: now, type: 'sell', sig: signature || null, sol: solReceived, tokens: tokens.toString(), pct });
    this.save();
    return p;
  }

  markClosed(mint) {
    const p = this.data.positions[mint];
    if (p && p.open) {
      p.open = false;
      p.roundBuys = 0;
      p.paperAmount = '0';
      this.save();
    }
  }

  pushHistory(p, entry) {
    p.history.push(entry);
    if (p.history.length > HISTORY_LIMIT) p.history.splice(0, p.history.length - HISTORY_LIMIT);
  }
}
