// Affiche les positions du bot et le résultat : npm run status
import { createApp, run } from '../app.js';
import { log, colors as C } from '../logger.js';
import { SOL_MINT } from '../constants.js';
import { sol, short, tokens, signedSol, tokenLink } from '../format.js';

run(async () => {
  const { config, state, executor, jupiter } = createApp();
  const positions = Object.values(state.positions).sort((a, b) => (b.updatedAt || '').localeCompare(a.updatedAt || ''));

  log.raw(`\n${C.bold}Positions du bot ${config.dryRun ? '(SIMULATION)' : '(RÉEL)'}${C.reset}\n`);
  if (!positions.length) {
    log.info('Aucun trade pour le moment.');
    process.exit(0);
  }

  let totalSpent = 0;
  let totalReceived = 0;
  let totalValue = 0;
  for (const p of positions) {
    const name = p.symbol || short(p.mint);
    let value = 0;
    let holding = '';
    if (p.open) {
      try {
        const bal = await executor.tokenBalance(p.mint);
        const decimals = bal.decimals ?? p.decimals ?? 0;
        holding = `${tokens(bal.amount, decimals)} tokens`;
        if (bal.amount > 0n) {
          const q = await jupiter.quote({ inputMint: p.mint, outputMint: SOL_MINT, amount: bal.amount, slippageBps: 100 });
          value = Number(q.outAmount);
          holding += ` ≈ ${sol(value)} SOL`;
        }
      } catch (e) {
        holding += ` (valeur inconnue : ${e.message})`;
      }
    }
    const pnl = p.solReceived + value - p.solSpent;
    totalSpent += p.solSpent;
    totalReceived += p.solReceived;
    totalValue += value;
    const color = pnl >= 0 ? C.green : C.red;
    log.raw(
      `${C.bold}${name.padEnd(12)}${C.reset} ${p.open ? `${C.cyan}OUVERTE${C.reset}` : 'fermée '}  ` +
        `achats ${p.buys}, ventes ${p.sells} | investi ${sol(p.solSpent)} SOL, récupéré ${sol(p.solReceived)} SOL` +
        `${holding ? ` | détenu : ${holding}` : ''} | ${color}résultat ${signedSol(pnl)} SOL${C.reset}`,
    );
    log.raw(`${C.gray}             ${tokenLink(p.mint)}${C.reset}`);
  }

  const total = totalReceived + totalValue - totalSpent;
  log.raw(
    `\n${C.bold}TOTAL${C.reset} : investi ${sol(totalSpent)} SOL, récupéré ${sol(totalReceived)} SOL, encore en jeu ≈ ${sol(totalValue)} SOL` +
      ` -> ${total >= 0 ? C.green : C.red}${signedSol(total)} SOL${C.reset}\n`,
  );
  process.exit(0);
});
