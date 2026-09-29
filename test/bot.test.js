// Test de bout en bout avec un faux réseau Solana et un faux Jupiter :
// le trader achète, vend 50 %, puis vend le reste -> le bot doit faire pareil.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import bs58 from 'bs58';
import { Keypair, PublicKey, TransactionMessage, VersionedTransaction, TransactionInstruction } from '@solana/web3.js';
import { CopyBot } from '../src/bot.js';
import { Executor } from '../src/executor.js';
import { State } from '../src/state.js';
import { NoRouteError } from '../src/swap.js';
import { makeTx, newKey, PUMP } from './helpers.js';

const SOL = 1_000_000_000;
const MEMO = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// arrête tous les bots créés, même si un test échoue
const running = [];
test.afterEach(async () => {
  await Promise.all(running.splice(0).map((b) => b.stop()));
});

function setup({ dryRun = false } = {}) {
  const me = Keypair.generate();
  const traderKey = Keypair.generate().publicKey;
  const trader = traderKey.toBase58();
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'copybot-'));

  const config = {
    dryRun,
    keypair: me,
    owner: me.publicKey,
    target: traderKey,
    targetStr: trader,
    buyAmountSol: 0.1,
    buyLamports: 0.1 * SOL,
    slippageBps: 1500,
    sellSlippageBps: 2000,
    priorityFeeLamports: 100_000,
    priorityFeeSol: 0.0001,
    minSolReserveLamports: 0.02 * SOL,
    maxBuysPerToken: 0,
    minTraderBuyLamports: 0,
    maxTradeAgeSec: 60,
    copySells: true,
    onlySellBotPositions: true,
    closeEmptyAccounts: true,
    catchUpSells: true,
    pumpPortalFallback: true,
    ignoreMints: new Set(),
    pollIntervalMs: 50,
    maxRetries: 1,
    dataDir,
  };

  // --- faux wallet + faux réseau -------------------------------------------
  const wallet = { lamports: 1 * SOL, tokens: new Map() }; // mint -> bigint
  const traderTxs = new Map(); // sig -> tx
  const traderSigs = []; // plus récent en premier
  const ownTxs = new Map();
  const statuses = new Map();
  const effects = new Map(); // blockhash -> effet à appliquer à l'envoi
  const sent = [];
  let logsCb = null;

  const connection = {
    async getSignaturesForAddress(_pk, { until, limit }) {
      const out = [];
      for (const s of traderSigs) {
        if (s === until) break;
        out.push({ signature: s, err: null, blockTime: Math.floor(Date.now() / 1000) });
        if (out.length >= limit) break;
      }
      return out;
    },
    onLogs(_pk, cb) {
      logsCb = cb;
      return 1;
    },
    async removeOnLogsListener() {},
    async getParsedTransaction(sig) {
      return traderTxs.get(sig) || ownTxs.get(sig) || null;
    },
    async getBalance() {
      return wallet.lamports;
    },
    async getParsedTokenAccountsByOwner(_owner, { mint }) {
      const m = mint.toBase58();
      if (!wallet.tokens.has(m)) return { value: [] };
      return {
        value: [
          {
            pubkey: new PublicKey(newKey()),
            account: {
              owner: new PublicKey('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
              data: { parsed: { info: { tokenAmount: { amount: String(wallet.tokens.get(m)), decimals: 6 } } } },
            },
          },
        ],
      };
    },
    async getLatestBlockhash() {
      return { blockhash: bs58.encode(Keypair.generate().publicKey.toBytes()), lastValidBlockHeight: 1000 };
    },
    async getBlockHeight() {
      return 10;
    },
    async sendRawTransaction(raw) {
      const tx = VersionedTransaction.deserialize(raw);
      const sig = bs58.encode(tx.signatures[0]);
      if (statuses.has(sig)) return sig; // renvoi du même tx
      const effect = effects.get(tx.message.recentBlockhash);
      sent.push({ sig, effect: effect?.kind || 'close' });
      const pre = wallet.lamports;
      const preTok = effect ? wallet.tokens.get(effect.mint) ?? 0n : 0n;
      if (effect) effect.apply();
      const postTok = effect ? wallet.tokens.get(effect.mint) ?? 0n : 0n;
      ownTxs.set(
        sig,
        makeTx({
          signature: sig,
          accounts: [{ key: me.publicKey.toBase58(), signer: true, pre, post: wallet.lamports }],
          tokens: effect ? [{ owner: me.publicKey.toBase58(), mint: effect.mint, pre: preTok, post: postTok }] : [],
        }),
      );
      statuses.set(sig, { confirmationStatus: 'confirmed', err: null });
      return sig;
    },
    async getSignatureStatuses(sigs) {
      return { value: sigs.map((s) => statuses.get(s) || null) };
    },
  };

  function signableTx(effect) {
    const blockhash = bs58.encode(Keypair.generate().publicKey.toBytes());
    effects.set(blockhash, effect);
    const msg = new TransactionMessage({
      payerKey: me.publicKey,
      recentBlockhash: blockhash,
      instructions: [new TransactionInstruction({ programId: new PublicKey(MEMO), keys: [], data: Buffer.from('swap') })],
    }).compileToV0Message();
    return new VersionedTransaction(msg);
  }

  // --- faux Jupiter : 1 SOL = 1 000 000 tokens (6 décimales) -> 1 lamport = 1 unité brute / 1000
  const noRoute = new Set();
  const jupiter = {
    async quote({ inputMint, outputMint, amount }) {
      const mint = inputMint === 'So11111111111111111111111111111111111111112' ? outputMint : inputMint;
      if (noRoute.has(mint)) throw new NoRouteError('pas de route');
      const isBuy = inputMint === 'So11111111111111111111111111111111111111112';
      const out = isBuy ? BigInt(amount) * 1000n : BigInt(amount) / 1000n;
      return { inputMint, outputMint, inAmount: String(amount), outAmount: String(out) };
    },
    async swapTransaction({ quote }) {
      const isBuy = quote.inputMint === 'So11111111111111111111111111111111111111112';
      const mint = isBuy ? quote.outputMint : quote.inputMint;
      const inAmt = BigInt(quote.inAmount);
      const outAmt = BigInt(quote.outAmount);
      const tx = signableTx({
        kind: isBuy ? 'buy' : 'sell',
        mint,
        apply() {
          const cur = wallet.tokens.get(mint) ?? 0n;
          if (isBuy) {
            wallet.lamports -= Number(inAmt) + 5000;
            wallet.tokens.set(mint, cur + outAmt);
          } else {
            wallet.lamports += Number(outAmt) - 5000;
            wallet.tokens.set(mint, cur - inAmt);
          }
        },
      });
      return { tx, lastValidBlockHeight: 1000 };
    },
    async tokenInfo() {
      return { symbol: 'TEST' };
    },
  };
  const pumpPortal = {
    calls: [],
    async transaction(args) {
      this.calls.push(args);
      return signableTx({
        kind: `pumpportal-${args.action}`,
        mint: args.mint,
        apply() {
          wallet.lamports -= Math.round(args.amount * SOL);
          wallet.tokens.set(args.mint, (wallet.tokens.get(args.mint) ?? 0n) + 42n);
        },
      });
    },
  };

  const state = new State(dataDir, { dryRun });
  const executor = new Executor({ config, connection, jupiter, pumpPortal, state });
  const bot = new CopyBot({ config, connection, executor, state, jupiter });
  running.push(bot);

  // Le trader fait un trade : on l'ajoute à "la blockchain" et on le notifie par websocket
  function traderTrade({ solDelta, tokenPre, tokenPost, mint, via = 'ws', blockTime }) {
    const tx = makeTx({
      accounts: [{ key: trader, signer: true, pre: 50 * SOL, post: 50 * SOL + solDelta }],
      tokens: [{ owner: trader, mint, pre: tokenPre, post: tokenPost }],
      programs: [PUMP],
      blockTime,
    });
    const sig = tx.transaction.signatures[0];
    traderTxs.set(sig, tx);
    traderSigs.unshift(sig);
    if (via === 'ws') logsCb?.({ signature: sig, err: null, logs: [] }, { slot: 1 });
    return sig;
  }

  async function settle() {
    // laisse le temps au polling + aux files de tourner
    for (let i = 0; i < 100; i++) {
      await sleep(50);
      await bot.orderChain;
      await Promise.all([...bot.mintQueues.values()]);
      if (!bot.mintQueues.size) break;
    }
  }

  return { bot, state, wallet, sent, traderTrade, settle, config, pumpPortal, noRoute, dataDir };
}

test('mode réel : achat, vente 50 %, vente du reste, avec le même pourcentage', async () => {
  const t = setup();
  const mint = newKey();
  await t.bot.start();

  t.traderTrade({ mint, solDelta: -2 * SOL, tokenPre: null, tokenPost: 5_000_000 });
  await t.settle();
  assert.equal(t.wallet.tokens.get(mint), 100_000_000_000n, 'le bot a acheté pour 0.1 SOL');
  assert.equal(t.state.getPosition(mint).open, true);
  assert.equal(t.state.getPosition(mint).symbol, 'TEST');

  t.traderTrade({ mint, solDelta: SOL, tokenPre: 5_000_000, tokenPost: 2_500_000 });
  await t.settle();
  assert.equal(t.wallet.tokens.get(mint), 50_000_000_000n, 'le bot a vendu 50 %');

  t.traderTrade({ mint, solDelta: SOL, tokenPre: 2_500_000, tokenPost: null });
  await t.settle();
  assert.equal(t.wallet.tokens.get(mint), 0n, 'le bot a tout vendu');
  const pos = t.state.getPosition(mint);
  assert.equal(pos.open, false);
  assert.equal(pos.buys, 1);
  assert.equal(pos.sells, 2);
  assert.deepEqual(t.sent.map((s) => s.effect), ['buy', 'sell', 'sell', 'close']);
  await t.bot.stop();
});

test('un tx vu par websocket ET par polling n\'est copié qu\'une fois', async () => {
  const t = setup();
  const mint = newKey();
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000 }); // ws + poll
  await sleep(200);
  await t.settle();
  assert.equal(t.sent.filter((s) => s.effect === 'buy').length, 1);
  await t.bot.stop();
});

test('détection par polling seul (websocket muet)', async () => {
  const t = setup();
  const mint = newKey();
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000, via: 'poll' });
  await sleep(300);
  await t.settle();
  assert.equal(t.sent.filter((s) => s.effect === 'buy').length, 1);
  await t.bot.stop();
});

test('vente d\'un token jamais acheté par le bot : ignorée', async () => {
  const t = setup();
  await t.bot.start();
  t.traderTrade({ mint: newKey(), solDelta: SOL, tokenPre: 1000, tokenPost: 0 });
  await t.settle();
  assert.equal(t.sent.length, 0);
  await t.bot.stop();
});

test('achat trop ancien : ignoré', async () => {
  const t = setup();
  await t.bot.start();
  t.traderTrade({ mint: newKey(), solDelta: -SOL, tokenPre: 0, tokenPost: 1000, blockTime: Math.floor(Date.now() / 1000) - 600 });
  await t.settle();
  assert.equal(t.sent.length, 0);
  await t.bot.stop();
});

test('solde insuffisant : pas d\'achat', async () => {
  const t = setup();
  t.wallet.lamports = 0.05 * SOL;
  await t.bot.start();
  t.traderTrade({ mint: newKey(), solDelta: -SOL, tokenPre: 0, tokenPost: 1000 });
  await t.settle();
  assert.equal(t.sent.length, 0);
  await t.bot.stop();
});

test('MAX_BUYS_PER_TOKEN limite les achats répétés', async () => {
  const t = setup();
  t.config.maxBuysPerToken = 1;
  const mint = newKey();
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000 });
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 1000, tokenPost: 2000 });
  await t.settle();
  assert.equal(t.sent.filter((s) => s.effect === 'buy').length, 1);
  await t.bot.stop();
});

test('token sans route Jupiter : secours PumpPortal', async () => {
  const t = setup();
  const mint = newKey();
  t.noRoute.add(mint);
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000 });
  await t.settle();
  assert.equal(t.pumpPortal.calls.length, 1);
  assert.equal(t.pumpPortal.calls[0].action, 'buy');
  assert.equal(t.pumpPortal.calls[0].amount, 0.1);
  assert.equal(t.wallet.tokens.get(mint), 42n);
  await t.bot.stop();
});

test('rattrapage au redémarrage : les ventes manquées sont copiées, pas les vieux achats', async () => {
  const t = setup();
  const mint = newKey();
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000 });
  await t.settle();
  await t.bot.stop();
  assert.equal(t.wallet.tokens.get(mint), 100_000_000_000n);

  // bot éteint : le trader vend 40 % et achète un autre token il y a 10 minutes
  const old = Math.floor(Date.now() / 1000) - 600;
  t.traderTrade({ mint, solDelta: SOL, tokenPre: 1000, tokenPost: 600, via: 'none', blockTime: old });
  t.traderTrade({ mint: newKey(), solDelta: -SOL, tokenPre: 0, tokenPost: 10, via: 'none', blockTime: old });

  const bot2 = new CopyBot({ config: t.config, connection: t.bot.connection, executor: t.bot.executor, state: t.state, jupiter: t.bot.jupiter });
  t.bot = bot2;
  running.push(bot2);
  await bot2.start();
  await t.settle();
  assert.equal(t.wallet.tokens.get(mint), 60_000_000_000n, 'vente de 40 % rattrapée');
  assert.equal(t.sent.filter((s) => s.effect === 'buy').length, 1, 'pas de nouvel achat');
  await bot2.stop();
});

test('simulation : portefeuille papier, aucune transaction envoyée', async () => {
  const t = setup({ dryRun: true });
  const mint = newKey();
  await t.bot.start();
  t.traderTrade({ mint, solDelta: -SOL, tokenPre: 0, tokenPost: 1000 });
  await t.settle();
  assert.equal(t.state.getPosition(mint).paperAmount, '100000000000');
  t.traderTrade({ mint, solDelta: SOL, tokenPre: 1000, tokenPost: 250 });
  await t.settle();
  assert.equal(t.state.getPosition(mint).paperAmount, '25000000000');
  t.traderTrade({ mint, solDelta: SOL, tokenPre: 250, tokenPost: 0 });
  await t.settle();
  const pos = t.state.getPosition(mint);
  assert.equal(pos.paperAmount, '0');
  assert.equal(pos.open, false);
  assert.equal(t.sent.length, 0);
  assert.ok(t.state.file.endsWith('state-simulation.json'));
  await t.bot.stop();
});
