import { loadConfig, ConfigError } from './config.js';
import { log, throttleLibraryErrors } from './logger.js';
import { createConnection } from './solana.js';
import { Jupiter, PumpPortal } from './swap.js';
import { State } from './state.js';
import { Executor } from './executor.js';

/** Assemble tous les morceaux du bot à partir du fichier .env. */
export function createApp(options = {}) {
  const config = loadConfig(options);
  log.setDebug(config.debug);
  if (!config.debug) throttleLibraryErrors();
  const connection = createConnection(config);
  const jupiter = new Jupiter({ baseUrl: config.jupiterBaseUrl, apiKey: config.jupiterApiKey });
  const pumpPortal = new PumpPortal();
  const state = new State(config.dataDir, { dryRun: config.dryRun });
  const executor = new Executor({ config, connection, jupiter, pumpPortal, state });
  return { config, connection, jupiter, pumpPortal, state, executor };
}

/** Lance une commande en affichant proprement les erreurs de configuration. */
export async function run(main) {
  try {
    await main();
  } catch (e) {
    if (e instanceof ConfigError) {
      log.error(`Configuration : ${e.message}`);
    } else {
      log.error(process.env.DEBUG === 'true' ? e.stack : e.message);
    }
    process.exitCode = 1;
    // la connexion websocket peut garder le programme ouvert : on force la sortie
    setTimeout(() => process.exit(1), 300).unref();
  }
}
