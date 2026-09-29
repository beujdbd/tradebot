import fs from 'node:fs';
import path from 'node:path';
import { ROOT_DIR } from './paths.js';

const LOG_DIR = path.join(ROOT_DIR, 'logs');
const LOG_FILE = path.join(LOG_DIR, 'bot.log');

const C = {
  reset: '\x1b[0m',
  gray: '\x1b[90m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
  bold: '\x1b[1m',
};

let debugEnabled = false;
let fileStream = null;

function stream() {
  if (fileStream === null) {
    try {
      fs.mkdirSync(LOG_DIR, { recursive: true });
      fileStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });
      fileStream.on('error', () => { fileStream = false; });
    } catch {
      fileStream = false;
    }
  }
  return fileStream || null;
}

function time() {
  return new Date().toLocaleTimeString('fr-FR', { hour12: false });
}

function write(color, tag, args) {
  const msg = args.map((a) => (a instanceof Error ? a.message : typeof a === 'string' ? a : JSON.stringify(a))).join(' ');
  console.log(`${C.gray}${time()}${C.reset} ${color}${tag}${C.reset} ${msg}`);
  const s = stream();
  if (s) s.write(`${new Date().toISOString()} ${tag.trim()} ${msg.replace(/\x1b\[[0-9;]*m/g, '')}\n`);
}

export const log = {
  setDebug(v) { debugEnabled = !!v; },
  info: (...a) => write(C.cyan, 'INFO ', a),
  ok: (...a) => write(C.green, 'OK   ', a),
  buy: (...a) => write(C.green + C.bold, 'ACHAT', a),
  sell: (...a) => write(C.magenta + C.bold, 'VENTE', a),
  trader: (...a) => write(C.blue + C.bold, 'TRADER', a),
  warn: (...a) => write(C.yellow, 'ATTN ', a),
  error: (...a) => write(C.red, 'ERREUR', a),
  debug: (...a) => { if (debugEnabled) write(C.gray, 'DEBUG', a); },
  raw: (msg = '') => console.log(msg),
};

export const colors = C;

/**
 * La librairie Solana écrit une ligne par seconde quand le websocket ou le RPC coince
 * ("ws error: ...", "Server responded with 429 ..."). On les regroupe : max 1 par minute.
 */
export function throttleLibraryErrors(intervalMs = 60_000) {
  const original = console.error.bind(console);
  const last = new Map();
  const patterns = [
    [/^ws error/i, 'Websocket en erreur (le bot continue en polling)'],
    [/429 Too Many Requests/i, 'Le RPC limite les requêtes (429) : un RPC Helius gratuit règle ça'],
  ];
  console.error = (...args) => {
    const text = args.map(String).join(' ');
    const hit = patterns.find(([re]) => re.test(text));
    if (!hit) return original(...args);
    const now = Date.now();
    if (now - (last.get(hit[1]) || 0) < intervalMs) return;
    last.set(hit[1], now);
    log.warn(`${hit[1]} — ${text.slice(0, 150)}`);
  };
}
