import { VersionedTransaction } from '@solana/web3.js';

export class NoRouteError extends Error {}

const TIMEOUT_MS = 12_000;

/** Client minimal pour l'API Swap de Jupiter (meilleur prix sur tous les DEX Solana, y compris Pump.fun). */
export class Jupiter {
  constructor({ baseUrl, apiKey, fetchImpl = globalThis.fetch }) {
    this.baseUrl = baseUrl;
    this.apiKey = apiKey;
    this.fetch = fetchImpl;
    this.origin = new URL(baseUrl).origin;
  }

  headers(extra = {}) {
    return this.apiKey ? { 'x-api-key': this.apiKey, ...extra } : extra;
  }

  async quote({ inputMint, outputMint, amount, slippageBps }) {
    const params = new URLSearchParams({
      inputMint,
      outputMint,
      amount: String(amount),
      slippageBps: String(slippageBps),
      restrictIntermediateTokens: 'true',
    });
    const res = await this.fetch(`${this.baseUrl}/quote?${params}`, {
      headers: this.headers(),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const text = await res.text();
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
    if (!res.ok || !body || body.error) {
      const msg = body?.error || body?.message || text.slice(0, 200) || `HTTP ${res.status}`;
      if (/route|not tradable|TOKEN_NOT_TRADABLE|COULD_NOT_FIND/i.test(`${msg} ${body?.errorCode ?? ''}`)) {
        throw new NoRouteError(`Jupiter : pas de route (${msg})`);
      }
      if (res.status === 401 || res.status === 403) {
        throw new Error(`Jupiter refuse la requête (HTTP ${res.status}) : vérifie JUPITER_API_KEY dans .env`);
      }
      if (res.status === 429) throw new Error('Jupiter : trop de requêtes (limite atteinte), réessaie');
      throw new Error(`Jupiter quote : ${msg}`);
    }
    return body;
  }

  async swapTransaction({ quote, userPublicKey, priorityFeeLamports }) {
    const res = await this.fetch(`${this.baseUrl}/swap`, {
      method: 'POST',
      headers: this.headers({ 'content-type': 'application/json' }),
      body: JSON.stringify({
        quoteResponse: quote,
        userPublicKey,
        wrapAndUnwrapSol: true,
        dynamicComputeUnitLimit: true,
        prioritizationFeeLamports: priorityFeeLamports
          ? { priorityLevelWithMaxLamports: { maxLamports: priorityFeeLamports, priorityLevel: 'veryHigh', global: false } }
          : undefined,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const body = await res.json().catch(() => null);
    if (!res.ok || !body?.swapTransaction) {
      throw new Error(`Jupiter swap : ${body?.error || body?.message || `HTTP ${res.status}`}`);
    }
    if (body.simulationError) {
      throw new Error(`Jupiter swap : la simulation échoue (${body.simulationError.error || JSON.stringify(body.simulationError)})`);
    }
    return {
      tx: VersionedTransaction.deserialize(Buffer.from(body.swapTransaction, 'base64')),
      lastValidBlockHeight: body.lastValidBlockHeight,
    };
  }

  /** Nom / symbole du token (pour des logs lisibles). */
  async tokenInfo(mint) {
    const res = await this.fetch(`${this.origin}/tokens/v2/search?query=${mint}`, {
      headers: this.headers(),
      signal: AbortSignal.timeout(5_000),
    });
    if (!res.ok) return null;
    const list = await res.json();
    const t = Array.isArray(list) ? list.find((x) => x.id === mint) : null;
    return t ? { symbol: t.symbol, name: t.name, decimals: t.decimals } : null;
  }
}

/**
 * Solution de secours via PumpPortal (Pump.fun, PumpSwap, Raydium, LaunchLab, Bonk…) quand Jupiter
 * ne trouve pas de route (token tout juste lancé). PumpPortal prend ~0.5 % de frais sur ces trades.
 */
export class PumpPortal {
  constructor({ fetchImpl = globalThis.fetch } = {}) {
    this.fetch = fetchImpl;
  }

  async transaction({ publicKey, action, mint, amount, denominatedInSol, slippagePct, priorityFeeSol }) {
    const res = await this.fetch('https://pumpportal.fun/api/trade-local', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        publicKey,
        action,
        mint,
        amount,
        denominatedInSol: denominatedInSol ? 'true' : 'false',
        slippage: slippagePct,
        priorityFee: priorityFeeSol,
        pool: 'auto',
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.status !== 200) {
      const text = await res.text().catch(() => '');
      throw new Error(`PumpPortal : ${text.slice(0, 200) || `HTTP ${res.status}`}`);
    }
    const buf = new Uint8Array(await res.arrayBuffer());
    return VersionedTransaction.deserialize(buf);
  }
}
