// Bouton d'urgence : vend 100 % de tous les tokens achetés par le bot : npm run sell-all
import readline from 'node:readline/promises';
import { createApp, run } from '../app.js';
import { log } from '../logger.js';
import { sol, short, tokens } from '../format.js';

run(async () => {
  const { config, state, executor } = createApp();
  const open = Object.values(state.positions).filter((p) => p.open);
  if (!open.length) {
    log.info('Aucune position ouverte.');
    process.exit(0);
  }

  const toSell = [];
  for (const p of open) {
    const bal = await executor.tokenBalance(p.mint);
    if (bal.amount > 0n) toSell.push({ p, bal });
    else state.markClosed(p.mint);
  }
  if (!toSell.length) {
    log.info('Rien à vendre (soldes à 0).');
    process.exit(0);
  }

  log.raw(`\nTokens à vendre ${config.dryRun ? '(SIMULATION)' : ''} :`);
  for (const { p, bal } of toSell) log.raw(`  - ${p.symbol || short(p.mint)} : ${tokens(bal.amount, bal.decimals ?? p.decimals)}`);

  if (!process.argv.includes('--yes')) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = await rl.question('\nTape OUI pour tout vendre : ');
    rl.close();
    if (answer.trim().toUpperCase() !== 'OUI') {
      log.info('Annulé.');
      process.exit(0);
    }
  }

  for (const { p, bal } of toSell) {
    const name = p.symbol || short(p.mint);
    try {
      const r = await executor.sell(p.mint, bal.amount, { full: true, decimals: bal.decimals ?? p.decimals ?? 0 });
      state.recordSell(p.mint, { ...r, pct: 1, full: true, simulated: !!r.simulated });
      log.sell(`${name} vendu -> ${sol(r.solReceived)} SOL ${r.signature ? `https://solscan.io/tx/${r.signature}` : ''}`);
    } catch (e) {
      log.error(`${name} : vente ratée (${e.message})`);
    }
  }
  process.exit(0);
});
