// Vérifie que tout est bien configuré, sans rien acheter : npm run check
import { createApp, run } from '../app.js';
import { log, colors as C } from '../logger.js';
import { analyzeTrade } from '../parser.js';
import { fetchParsedTransaction } from '../solana.js';
import { SOL_MINT, USDC_MINT } from '../constants.js';
import { sol, short, pct } from '../format.js';

const title = (t) => log.raw(`\n${C.bold}${t}${C.reset}`);

run(async () => {
  const { config, connection, jupiter, executor } = createApp({ requireKey: false });
  let problems = 0;
  const fail = (msg) => {
    problems++;
    log.error(msg);
  };

  title('1. Configuration (.env)');
  log.ok(`Mode : ${config.dryRun ? 'SIMULATION (DRY_RUN=true, aucun vrai trade)' : 'RÉEL (DRY_RUN=false)'}`);
  log.ok(`Trader copié : ${config.targetStr}`);
  log.ok(`Montant par achat : ${config.buyAmountSol} SOL, slippage ${config.slippageBps / 100}%`);

  title('2. Connexion au RPC Solana');
  try {
    const t0 = Date.now();
    await connection.getLatestBlockhash();
    const ms = Date.now() - t0;
    log.ok(`RPC OK (${new URL(config.rpcUrl).host}, ${ms} ms)`);
    if (config.rpcUrl.includes('api.mainnet-beta.solana.com')) {
      log.warn('Tu utilises le RPC public gratuit de Solana : il est lent et limité. Prends un RPC Helius gratuit (README, étape 4).');
    }
  } catch (e) {
    fail(`RPC injoignable : ${e.message} -> vérifie RPC_URL`);
  }

  title('3. Ton wallet');
  if (!config.owner) {
    if (config.dryRun) log.warn('Pas de PRIVATE_KEY : OK pour la simulation, obligatoire pour trader en vrai.');
    else fail('PRIVATE_KEY manquante.');
  } else {
    log.ok(`Adresse : ${config.owner.toBase58()}`);
    try {
      const bal = await executor.solBalance();
      const needed = config.buyLamports + config.minSolReserveLamports;
      if (bal >= needed) log.ok(`Solde : ${sol(bal)} SOL (≈ ${Math.floor((bal - config.minSolReserveLamports) / config.buyLamports)} achat(s) possible(s))`);
      else if (config.dryRun) log.warn(`Solde : ${sol(bal)} SOL (pas assez pour le mode réel : il faut au moins ${sol(needed)} SOL)`);
      else fail(`Solde : ${sol(bal)} SOL, il faut au moins ${sol(needed)} SOL (achat + réserve MIN_SOL_RESERVE)`);
    } catch (e) {
      fail(`Lecture du solde impossible : ${e.message}`);
    }
  }

  title('4. Jupiter (exécution des swaps)');
  try {
    const q = await jupiter.quote({ inputMint: SOL_MINT, outputMint: USDC_MINT, amount: config.buyLamports, slippageBps: 50 });
    log.ok(`Jupiter OK (${config.jupiterApiKey ? 'avec clé API' : 'sans clé'}) : ${config.buyAmountSol} SOL ≈ ${(Number(q.outAmount) / 1e6).toFixed(2)} $`);
  } catch (e) {
    fail(`Jupiter ne répond pas : ${e.message}`);
    if (!config.jupiterApiKey) log.warn('-> Crée une clé API gratuite sur https://portal.jup.ag et mets-la dans JUPITER_API_KEY');
  }

  title('5. Temps réel (websocket)');
  const wsOk = await new Promise((resolve) => {
    let id;
    const timer = setTimeout(() => resolve(false), 10_000);
    try {
      id = connection.onSlotChange(() => {
        clearTimeout(timer);
        resolve(true);
      });
    } catch {
      clearTimeout(timer);
      resolve(false);
    }
    return id;
  });
  if (wsOk) log.ok('Websocket OK : les trades seront détectés en temps réel.');
  else log.warn('Websocket muet : le bot marchera quand même (polling toutes les ' + config.pollIntervalMs / 1000 + ' s), mais un peu moins vite.');

  title('6. Derniers trades du trader (ce que le bot aurait copié)');
  try {
    const sigs = await connection.getSignaturesForAddress(config.target, { limit: 15 });
    if (!sigs.length) log.warn('Aucune transaction trouvée pour ce wallet.');
    let shown = 0;
    for (const s of sigs) {
      if (s.err) continue;
      const tx = await fetchParsedTransaction(connection, s.signature, { tries: 3 });
      if (!tx) continue;
      const res = analyzeTrade(tx, config.targetStr);
      const when = s.blockTime ? new Date(s.blockTime * 1000).toLocaleString('fr-FR') : '?';
      for (const ev of res.events) {
        if (config.ignoreMints.has(ev.mint)) continue;
        shown++;
        const info = await jupiter.tokenInfo(ev.mint).catch(() => null);
        const name = info?.symbol || short(ev.mint);
        const via = res.dex ? ` via ${res.dex}` : '';
        if (ev.type === 'buy') {
          log.raw(`  ${when}  ${C.green}ACHAT${C.reset} ${name}${ev.solSpent > 0n ? ` pour ${sol(ev.solSpent)} SOL` : ''}${via}  -> le bot achèterait pour ${config.buyAmountSol} SOL`);
        } else {
          log.raw(`  ${when}  ${C.magenta}VENTE${C.reset} ${pct(ev.pct)} de ses ${name}${via}  -> le bot vendrait ${pct(ev.pct >= 0.99 ? 1 : ev.pct)} des tiens`);
        }
      }
    }
    if (sigs.length && !shown) log.info('Aucun achat/vente de token dans ses 15 dernières transactions.');
  } catch (e) {
    fail(`Lecture de l'historique du trader impossible : ${e.message}`);
  }

  log.raw('');
  if (problems) log.error(`${problems} problème(s) à corriger avant de lancer le bot.`);
  else log.ok(`Tout est prêt ! Lance le bot avec : npm start${config.dryRun ? '  (en simulation)' : ''}`);
  process.exit(problems ? 1 : 0);
});
