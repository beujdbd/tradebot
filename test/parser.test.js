import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeTrade } from '../src/parser.js';
import { makeTx, newKey, PUMP, SYSTEM, TOKEN, WSOL, USDC } from './helpers.js';

const trader = newKey();
const other = newKey();
const mint = newKey();
const mint2 = newKey();
const SOL = 1_000_000_000;

test('achat Pump.fun : SOL -> token', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: 10 * SOL, post: 10 * SOL - 1.5 * SOL - 2_039_280 - 5000 }],
    tokens: [{ owner: trader, mint, pre: null, post: 1_000_000_000 }],
  });
  const r = analyzeTrade(tx, trader);
  assert.equal(r.events.length, 1);
  assert.equal(r.events[0].type, 'buy');
  assert.equal(r.events[0].mint, mint);
  assert.equal(r.events[0].amountRaw, 1_000_000_000n);
  assert.equal(r.dex, 'Pump.fun');
  assert.ok(r.events[0].solSpent >= BigInt(1.5 * SOL));
});

test('vente partielle : pourcentage exact', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: 2 * SOL }],
    tokens: [{ owner: trader, mint, pre: 1_000_000, post: 625_000 }],
  });
  const [ev] = analyzeTrade(tx, trader).events;
  assert.equal(ev.type, 'sell');
  assert.equal(ev.pct, 0.375);
});

test('vente totale (compte de token fermé) = 100 %', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: 3 * SOL }],
    tokens: [{ owner: trader, mint, pre: 1_234_567, post: null }],
  });
  const [ev] = analyzeTrade(tx, trader).events;
  assert.equal(ev.type, 'sell');
  assert.equal(ev.pct, 1);
});

test('vente même si le SOL reçu est mangé par un tip (DEX appelé)', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 1_000_000 }],
    tokens: [{ owner: trader, mint, pre: 100, post: 50 }],
  });
  const [ev] = analyzeTrade(tx, trader).events;
  assert.equal(ev.type, 'sell');
  assert.equal(ev.pct, 0.5);
});

test('achat payé en WSOL (compte wrappé persistant)', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 5000 }],
    tokens: [
      { owner: trader, mint: WSOL, pre: 5 * SOL, post: 4 * SOL, decimals: 9 },
      { owner: trader, mint, pre: 0, post: 777 },
    ],
  });
  const r = analyzeTrade(tx, trader);
  assert.equal(r.events.length, 1);
  assert.equal(r.events[0].type, 'buy');
  assert.equal(r.events[0].solSpent, BigInt(SOL));
});

test('achat payé en USDC', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 5000 }],
    tokens: [
      { owner: trader, mint: USDC, pre: 100_000_000, post: 50_000_000 },
      { owner: trader, mint, pre: 0, post: 999 },
    ],
  });
  const r = analyzeTrade(tx, trader);
  assert.deepEqual(r.events.map((e) => e.type), ['buy']);
  assert.equal(r.events[0].mint, mint);
});

test('swap token -> token : vente de X + achat de Y', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 5000 }],
    tokens: [
      { owner: trader, mint, pre: 1000, post: 0 },
      { owner: trader, mint: mint2, pre: 0, post: 5000 },
    ],
  });
  const r = analyzeTrade(tx, trader);
  assert.deepEqual(r.events.map((e) => e.type).sort(), ['buy', 'sell']);
});

test('airdrop / token reçu d\'un autre wallet : ignoré', () => {
  const tx = makeTx({
    accounts: [
      { key: other, signer: true, pre: SOL, post: SOL - 2_044_280 },
      { key: trader, signer: false, pre: SOL, post: SOL },
    ],
    tokens: [{ owner: trader, mint, pre: null, post: 1000 }],
    programs: [SYSTEM, TOKEN],
  });
  const r = analyzeTrade(tx, trader);
  assert.equal(r.events.length, 0);
});

test('simple envoi de tokens par le trader (pas de DEX) : ignoré', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 5000 }],
    tokens: [
      { owner: trader, mint, pre: 1000, post: 0 },
      { owner: other, mint, pre: 0, post: 1000 },
    ],
    programs: [TOKEN],
  });
  assert.equal(analyzeTrade(tx, trader).events.length, 0);
});

test('transaction échouée : ignorée', () => {
  const tx = makeTx({
    accounts: [{ key: trader, signer: true, pre: SOL, post: SOL - 5000 }],
    tokens: [{ owner: trader, mint, pre: 0, post: 1000 }],
    err: { InstructionError: [2, { Custom: 6001 }] },
  });
  assert.equal(analyzeTrade(tx, trader).events.length, 0);
});

test('les mouvements des autres wallets du tx ne comptent pas', () => {
  const tx = makeTx({
    accounts: [
      { key: trader, signer: true, pre: SOL, post: SOL / 2 },
      { key: other, signer: false, pre: SOL, post: SOL * 1.5 },
    ],
    tokens: [
      { owner: trader, mint, pre: 0, post: 500 },
      { owner: other, mint, pre: 10_000, post: 9_500 }, // la pool
    ],
    programs: [PUMP],
  });
  const r = analyzeTrade(tx, trader);
  assert.deepEqual(r.events.map((e) => e.type), ['buy']);
});
