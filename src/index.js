import { createApp, run } from './app.js';
import { CopyBot } from './bot.js';
import { createNotifier } from './notifier.js';
import { log, colors as C } from './logger.js';
import { sol, short } from './format.js';

run(async () => {
  const app = createApp();
  const { config, connection, executor, state, jupiter } = app;

  log.raw(`\n${C.bold}${C.cyan}=== BOT DE COPY-TRADING SOLANA ===${C.reset}`);
  log.raw(`Trader copié      : ${config.targetStr}`);
  log.raw(`Montant par achat : ${config.buyAmountSol} SOL`);
  log.raw(`Ventes            : ${config.copySells ? 'même pourcentage que le trader' : 'non copiées'}`);
  log.raw(`Slippage          : ${config.slippageBps / 100}% achat / ${config.sellSlippageBps / 100}% vente`);
  if (config.maxBuysPerToken) log.raw(`Achats max/token  : ${config.maxBuysPerToken}`);
  log.raw(`RPC               : ${new URL(config.rpcUrl).host}`);
  if (config.owner) log.raw(`Ton wallet        : ${config.owner.toBase58()}`);

  if (config.dryRun) {
    log.raw(`\n${C.yellow}${C.bold}MODE SIMULATION (DRY_RUN=true) : aucun vrai achat.${C.reset}`);
    log.raw(`${C.yellow}Le bot montre ce qu'il ferait. Pour trader en vrai : DRY_RUN=false dans .env${C.reset}\n`);
  } else {
    log.raw(`\n${C.green}${C.bold}MODE RÉEL : le bot trade avec ton argent.${C.reset}\n`);
    const balance = await executor.solBalance().catch(() => null);
    const needed = config.buyLamports + config.minSolReserveLamports;
    if (balance !== null) log.info(`Solde : ${sol(balance)} SOL`);
    if (balance !== null && balance < needed) {
      log.warn(`Solde trop faible pour acheter (${sol(needed)} SOL nécessaires avec la réserve). Le bot tournera mais ne pourra que vendre.`);
    }
  }

  const open = Object.values(state.positions).filter((p) => p.open);
  if (open.length) log.info(`${open.length} position(s) ouverte(s) : ${open.map((p) => p.symbol || short(p.mint)).join(', ')}`);
  if (!config.jupiterApiKey) {
    log.warn('JUPITER_API_KEY est vide : j\'utilise l\'API Jupiter gratuite sans clé, qui peut être limitée ou fermée. Mets une clé gratuite (README, étape 4).');
  }

  const bot = new CopyBot({ config, connection, executor, state, jupiter, notify: createNotifier(config) });
  await bot.start();
  log.ok(`En écoute du trader ${short(config.targetStr)}… (Ctrl+C pour arrêter)`);
  bot.notify(`🤖 Bot démarré${config.dryRun ? ' (simulation)' : ''} — copie de ${short(config.targetStr)}, ${config.buyAmountSol} SOL par achat`);

  let stopping = false;
  const shutdown = async () => {
    if (stopping) process.exit(0);
    stopping = true;
    log.info('Arrêt… (j\'attends la fin des trades en cours, Ctrl+C encore pour forcer)');
    await bot.stop();
    state.save();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
});

// Le bot ne doit jamais s'arrêter sur une erreur imprévue
process.on('unhandledRejection', (e) => log.error(`Erreur non gérée : ${e?.stack || e}`));
process.on('uncaughtException', (e) => log.error(`Exception : ${e?.stack || e}`));
