import fs from 'node:fs';
import dotenv from 'dotenv';
import bs58 from 'bs58';
import { Keypair, PublicKey, LAMPORTS_PER_SOL } from '@solana/web3.js';
import { ENV_FILE, ENV_EXAMPLE_FILE, DATA_DIR, ROOT_DIR } from './paths.js';
import { SOL_MINT, USDC_MINT, USDT_MINT } from './constants.js';

export class ConfigError extends Error {}

function str(env, name, def = '') {
  const v = env[name];
  return v === undefined || v.trim() === '' ? def : v.trim();
}

function num(env, name, def, { min = -Infinity, max = Infinity } = {}) {
  const raw = str(env, name);
  if (raw === '') return def;
  const v = Number(raw.replace(',', '.'));
  if (!Number.isFinite(v)) throw new ConfigError(`${name} doit être un nombre (valeur actuelle : "${raw}")`);
  if (v < min || v > max) throw new ConfigError(`${name} doit être entre ${min} et ${max} (valeur actuelle : ${v})`);
  return v;
}

function bool(env, name, def) {
  const raw = str(env, name).toLowerCase();
  if (raw === '') return def;
  if (['true', '1', 'oui', 'yes', 'on'].includes(raw)) return true;
  if (['false', '0', 'non', 'no', 'off'].includes(raw)) return false;
  throw new ConfigError(`${name} doit valoir true ou false (valeur actuelle : "${raw}")`);
}

function pubkey(value, name) {
  try {
    return new PublicKey(value);
  } catch {
    throw new ConfigError(`${name} n'est pas une adresse Solana valide : "${value}"`);
  }
}

export function parsePrivateKey(raw) {
  const value = raw.trim().replace(/^["']|["']$/g, '');
  let bytes;
  if (value.startsWith('[')) {
    try {
      bytes = Uint8Array.from(JSON.parse(value));
    } catch {
      throw new ConfigError('PRIVATE_KEY : format tableau [1,2,3,...] invalide');
    }
  } else {
    try {
      bytes = bs58.decode(value);
    } catch {
      throw new ConfigError('PRIVATE_KEY : clé privée invalide (attendu : la clé exportée depuis Phantom/Solflare, en base58)');
    }
  }
  if (bytes.length === 64) return Keypair.fromSecretKey(bytes);
  if (bytes.length === 32) return Keypair.fromSeed(bytes);
  throw new ConfigError(`PRIVATE_KEY : longueur inattendue (${bytes.length} octets). As-tu copié la clé PRIVÉE et pas l'adresse ?`);
}

/**
 * Charge et valide la configuration depuis .env.
 * Si .env n'existe pas, il est créé à partir de .env.example.
 */
export function loadConfig({ requireKey } = {}) {
  if (!fs.existsSync(ENV_FILE)) {
    if (fs.existsSync(ENV_EXAMPLE_FILE)) {
      fs.copyFileSync(ENV_EXAMPLE_FILE, ENV_FILE);
      throw new ConfigError(
        `Le fichier .env n'existait pas : je l'ai créé ici -> ${ENV_FILE}\n` +
          '   Ouvre-le, remplis au minimum PRIVATE_KEY, RPC_URL et BUY_AMOUNT_SOL, puis relance.',
      );
    }
    throw new ConfigError('Fichier .env introuvable (et .env.example aussi). Re-télécharge le projet.');
  }

  const env = { ...dotenv.parse(fs.readFileSync(ENV_FILE)), ...pickOverrides(process.env) };

  const dryRun = bool(env, 'DRY_RUN', true);
  const rawKey = str(env, 'PRIVATE_KEY');
  const keypair = rawKey ? parsePrivateKey(rawKey) : null;
  if (!keypair && (requireKey ?? !dryRun)) {
    throw new ConfigError('PRIVATE_KEY est vide : colle la clé privée de ton wallet de trading dans .env (voir README, étape 3).');
  }

  const target = str(env, 'TARGET_WALLET');
  if (!target) throw new ConfigError('TARGET_WALLET est vide : mets l\'adresse du wallet du trader à copier.');
  const targetPk = pubkey(target, 'TARGET_WALLET');
  if (keypair && keypair.publicKey.equals(targetPk)) {
    throw new ConfigError('TARGET_WALLET est ton propre wallet : mets l\'adresse du TRADER à copier.');
  }

  const rpcUrl = str(env, 'RPC_URL', 'https://api.mainnet-beta.solana.com');
  if (!/^https?:\/\//.test(rpcUrl)) throw new ConfigError('RPC_URL doit commencer par https://');
  const wsUrl = str(env, 'WS_URL') || undefined;

  const buyAmountSol = num(env, 'BUY_AMOUNT_SOL', 0, { min: 0 });
  if (!(buyAmountSol > 0)) throw new ConfigError('BUY_AMOUNT_SOL doit être > 0 (ex : 0.05)');

  const slippagePct = num(env, 'SLIPPAGE_PERCENT', 15, { min: 0.1, max: 100 });
  const sellSlippagePct = num(env, 'SELL_SLIPPAGE_PERCENT', slippagePct, { min: 0.1, max: 100 });
  const priorityFeeSol = num(env, 'PRIORITY_FEE_SOL', 0.0005, { min: 0, max: 0.1 });

  const ignoreMints = new Set([SOL_MINT, USDC_MINT, USDT_MINT]);
  for (const m of str(env, 'IGNORE_TOKENS').split(/[\s,;]+/).filter(Boolean)) {
    ignoreMints.add(pubkey(m, 'IGNORE_TOKENS').toBase58());
  }

  const jupiterApiKey = str(env, 'JUPITER_API_KEY');
  const jupiterBaseUrl = str(
    env,
    'JUPITER_API_URL',
    jupiterApiKey ? 'https://api.jup.ag/swap/v1' : 'https://lite-api.jup.ag/swap/v1',
  ).replace(/\/+$/, '');

  const telegramToken = str(env, 'TELEGRAM_BOT_TOKEN');
  const telegramChatId = str(env, 'TELEGRAM_CHAT_ID');

  return {
    rootDir: ROOT_DIR,
    dataDir: DATA_DIR,
    dryRun,
    keypair,
    owner: keypair ? keypair.publicKey : null,
    target: targetPk,
    targetStr: targetPk.toBase58(),
    rpcUrl,
    wsUrl,

    buyAmountSol,
    buyLamports: Math.round(buyAmountSol * LAMPORTS_PER_SOL),
    slippageBps: Math.round(slippagePct * 100),
    sellSlippageBps: Math.round(sellSlippagePct * 100),
    priorityFeeLamports: Math.round(priorityFeeSol * LAMPORTS_PER_SOL),
    priorityFeeSol,
    minSolReserveLamports: Math.round(num(env, 'MIN_SOL_RESERVE', 0.02, { min: 0 }) * LAMPORTS_PER_SOL),
    maxBuysPerToken: Math.floor(num(env, 'MAX_BUYS_PER_TOKEN', 0, { min: 0 })),
    minTraderBuyLamports: Math.round(num(env, 'MIN_TRADER_BUY_SOL', 0, { min: 0 }) * LAMPORTS_PER_SOL),
    maxTradeAgeSec: num(env, 'MAX_TRADE_AGE_SEC', 60, { min: 5 }),

    copySells: bool(env, 'COPY_SELLS', true),
    onlySellBotPositions: bool(env, 'ONLY_SELL_BOT_TOKENS', true),
    closeEmptyAccounts: bool(env, 'CLOSE_EMPTY_ACCOUNTS', true),
    catchUpSells: bool(env, 'CATCH_UP_SELLS', true),
    pumpPortalFallback: bool(env, 'PUMPPORTAL_FALLBACK', true),

    jupiterApiKey,
    jupiterBaseUrl,

    ignoreMints,
    pollIntervalMs: Math.round(num(env, 'POLL_INTERVAL_SEC', 2, { min: 0.5 }) * 1000),
    maxRetries: Math.floor(num(env, 'MAX_RETRIES', 2, { min: 0, max: 10 })),

    telegram: telegramToken && telegramChatId ? { token: telegramToken, chatId: telegramChatId } : null,
    debug: bool(env, 'DEBUG', false),
  };
}

// Permet de surcharger une option depuis la ligne de commande (ex : DRY_RUN=true npm start)
function pickOverrides(processEnv) {
  const keys = ['DRY_RUN', 'DEBUG', 'BUY_AMOUNT_SOL', 'RPC_URL'];
  const out = {};
  for (const k of keys) if (processEnv[k] !== undefined) out[k] = processEnv[k];
  return out;
}
