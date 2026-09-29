# Bot de copy-trading Solana

Ce bot suit **un trader** sur Solana et **copie ses trades automatiquement** :

- **Il achète** un token → le bot achète **le même token**, pour **le montant fixe que tu choisis** (ex : 0,05 SOL à chaque fois).
- **Il vend X %** de ses tokens → le bot vend **X % des tiens**. S'il vend tout, le bot vend tout.

Wallet copié par défaut : `89HbgWduLwoxcofWpmn1EiF9wEdpgkNDEyPjzZ72mkDi`

**Ce que fait le bot :**

- Il détecte les trades **en temps réel** (websocket). Il vérifie aussi toutes les 2 secondes, au cas où le websocket rate quelque chose.
- Il marche sur **tous les DEX** : Pump.fun, PumpSwap, Raydium, Meteora, Orca… Il achète au meilleur prix via Jupiter. Si Jupiter ne trouve pas un token tout juste lancé, il passe par PumpPortal.
- Il ignore les simples transferts et les airdrops. Seuls les vrais achats et ventes sont copiés.
- **Mode simulation** : tu vois ce que le bot aurait fait, sans dépenser un centime.
- **Redémarrage sûr** : si le trader a vendu pendant que ton bot était éteint, ces ventes sont rattrapées au redémarrage. Les vieux achats, eux, ne sont jamais rachetés.
- **Protections** :
  - une réserve de SOL est toujours gardée pour les frais ;
  - il ne vend que les tokens qu'il a lui-même achetés ;
  - il réessaie si une transaction échoue ;
  - il récupère les ~0,002 SOL bloqués dans chaque compte de token vidé.
- `npm run status` affiche tes gains et pertes. `npm run sell-all` est le bouton d'urgence. Tu peux aussi recevoir des notifications Telegram (optionnel).

---

## ⚠️ À lire avant de commencer

- **Le copy-trading de memecoins est très risqué.** Tu peux perdre tout l'argent que tu mets dans le bot. Les bons résultats passés du trader ne garantissent rien.
- **Tu achètes toujours un peu après le trader** (1 à 3 secondes). Sur un memecoin qui monte vite, ton prix sera un peu moins bon que le sien. Si le trader est un bot « sniper » ultra-rapide, le copier peut être perdant. **C'est pour ça qu'il faut tester en simulation d'abord (étape 7).**
- **Utilise un wallet dédié au bot**, avec seulement l'argent que tu acceptes de perdre. Ne mets jamais la clé de ton wallet principal.
- **Ne partage jamais ta clé privée ni ton fichier `.env`.** Personne d'honnête ne te les demandera, ni un « support », ni un « admin ».

---

## Marche à suivre (étape par étape)

### Étape 1 — Installer Node.js

1. Va sur **https://nodejs.org** et télécharge la version **LTS** (le gros bouton vert).
2. Installe-la en laissant toutes les options par défaut.
3. Pour vérifier, ouvre un terminal :
   - **Windows** : touche Windows, tape `cmd`, puis Entrée.
   - **Mac** : ouvre l'app « Terminal ».

   Tape ensuite :

   ```
   node -v
   ```

   Tu dois voir un numéro de version égal ou supérieur à `v18` (par exemple `v22.x.x`).

### Étape 2 — Télécharger le bot et installer ce qu'il faut

1. Sur la page GitHub du projet, clique sur le bouton vert **Code**, puis **Download ZIP**. Décompresse le ZIP (clic droit → « Extraire tout »).
2. Ouvre un terminal **dans le dossier du bot** :
   - **Windows** : ouvre le dossier dans l'Explorateur. Clique dans la barre d'adresse en haut, tape `cmd`, puis Entrée.
   - **Mac** : dans le Terminal, tape `cd ` (avec un espace), glisse le dossier dans la fenêtre, puis Entrée.
3. Tape :

   ```
   npm install
   ```

   Attends la fin. Des messages `npm WARN` ou `vulnerabilities` peuvent s'afficher : c'est normal, ignore-les.

### Étape 3 — Créer un wallet dédié et récupérer sa clé privée

Avec **Phantom** (c'est pareil avec Solflare) :

1. Crée un **nouveau compte** : clique sur ton avatar en haut à gauche, puis **Ajouter un compte**.
2. Envoie sur ce compte le SOL que tu veux confier au bot.

   Compte au minimum **quelques achats + 0,05 SOL** pour les frais. Par exemple, pour des achats de 0,05 SOL, mets 0,5 SOL ou plus : le bot peut avoir plusieurs positions ouvertes en même temps.
3. Récupère la clé privée : **Paramètres** (roue dentée), puis **Gérer les comptes**. Choisis ce compte, puis **Afficher la clé privée**, et entre ton mot de passe.
4. Copie la clé : c'est une longue suite de lettres et de chiffres. Tu la colleras à l'étape 5.

> La clé privée **n'est pas** l'adresse du wallet. L'adresse sert à recevoir des fonds. La clé privée donne le contrôle total du wallet.

### Étape 4 — Obtenir un RPC rapide et une clé Jupiter (gratuits, 5 minutes)

Ces deux clés rendent le bot **beaucoup plus rapide et fiable**. C'est fortement conseillé.

**RPC Helius** : c'est la connexion du bot à la blockchain Solana.

1. Va sur **https://dashboard.helius.dev** et crée un compte gratuit.
2. Sur le tableau de bord, copie l'URL **Mainnet RPC**. Elle ressemble à `https://mainnet.helius-rpc.com/?api-key=xxxxxxxx`.

**Clé API Jupiter** : Jupiter est le service qui exécute les achats et les ventes au meilleur prix.

1. Va sur **https://portal.jup.ag** et connecte-toi.
2. Crée une clé API (l'offre gratuite suffit), puis copie-la.

### Étape 5 — Remplir le fichier de configuration `.env`

1. Crée le fichier `.env`. Le plus simple : lance `npm start` une fois, et le bot le crée tout seul. Sinon, dans le terminal :
   - **Windows** : `copy .env.example .env`
   - **Mac / Linux** : `cp .env.example .env`
2. Ouvre `.env` avec le Bloc-notes (clic droit → Ouvrir avec → Bloc-notes). Sur Mac, utilise TextEdit.
3. Remplis ces lignes :

   ```ini
   PRIVATE_KEY=ta_clé_privée_de_l_étape_3
   TARGET_WALLET=89HbgWduLwoxcofWpmn1EiF9wEdpgkNDEyPjzZ72mkDi
   BUY_AMOUNT_SOL=0.05
   RPC_URL=https://mainnet.helius-rpc.com/?api-key=ta_clé_helius
   JUPITER_API_KEY=ta_clé_jupiter
   DRY_RUN=true
   ```

   - `BUY_AMOUNT_SOL` = combien de SOL le bot dépense **à chaque achat** du trader. Utilise un point, pas une virgule : `0.05`.
   - `TARGET_WALLET` est déjà rempli avec le wallet à copier.
   - Laisse `DRY_RUN=true` pour l'instant : c'est la simulation.
4. Enregistre.

> **Piège Windows** : le fichier doit s'appeler exactement `.env`, et pas `.env.txt`. Dans l'Explorateur, active **Affichage → Extensions de noms de fichiers** pour vérifier.

### Étape 6 — Vérifier que tout marche

```
npm run check
```

Le bot vérifie ta config, le RPC, ton solde, Jupiter et la connexion temps réel. Il affiche aussi **les derniers trades du trader**, avec ce que le bot aurait fait pour chacun. Corrige ce qui est en rouge, puis relance jusqu'à voir **« Tout est prêt ! »**.

### Étape 7 — Tester en simulation (recommandé)

Avec `DRY_RUN=true` :

```
npm start
```

Le bot écoute le trader et affiche ce qu'il **aurait** acheté et vendu, aux vrais prix du marché, **sans rien dépenser**. Laisse-le tourner quelques heures, puis regarde le résultat :

```
npm run status
```

### Étape 8 — Passer en réel

1. Arrête le bot avec **Ctrl + C**.
2. Dans `.env`, mets `DRY_RUN=false` et enregistre.
3. Relance :

   ```
   npm start
   ```

Le bot affiche **« MODE RÉEL »** et ton solde, puis **« En écoute du trader… »**. C'est parti. **Laisse la fenêtre ouverte** : si tu la fermes, le bot s'arrête.

### Étape 9 (optionnel) — Le faire tourner 24h/24

Le bot ne copie que **pendant qu'il tourne**. Si tu le fais tourner sur ton PC :

- empêche la mise en veille : Windows → Paramètres → Système → Alimentation → Mise en veille : **Jamais** ;
- ou utilise un petit serveur VPS Linux (environ 5 €/mois), avec les mêmes étapes.

Pour qu'il redémarre tout seul en cas de souci, utilise **pm2** :

```
npm install -g pm2
pm2 start npm --name copybot -- start
pm2 logs copybot      # voir les logs
pm2 stop copybot      # arrêter
pm2 restart copybot   # redémarrer (après avoir modifié .env)
```

### Étape 10 (optionnel) — Notifications Telegram sur ton téléphone

1. Sur Telegram, écris à **@BotFather** et envoie `/newbot`. Suis les instructions, puis copie le **token** qu'il te donne.
2. Envoie un message quelconque (par exemple « salut ») à ton nouveau bot.
3. Ouvre dans ton navigateur : `https://api.telegram.org/bot<TON_TOKEN>/getUpdates`. Repère `"chat":{"id":123456789`. Ce nombre est ton **chat id**.
4. Dans `.env` :

   ```ini
   TELEGRAM_BOT_TOKEN=ton_token
   TELEGRAM_CHAT_ID=123456789
   ```

Tu recevras un message à chaque achat, à chaque vente (avec le résultat) et à chaque erreur.

---

## Commandes

| Commande | Ce qu'elle fait |
|---|---|
| `npm start` | Lance le bot (Ctrl + C pour l'arrêter proprement) |
| `npm run check` | Vérifie la configuration et affiche les derniers trades du trader |
| `npm run status` | Affiche tes positions, ce que tu as investi et récupéré, et ton résultat en SOL |
| `npm run sell-all` | **Urgence** : vend 100 % des tokens achetés par le bot (arrête le bot avant) |
| `npm test` | Lance les tests automatiques du bot |

---

## Exemple de ce que tu verras

```
=== BOT DE COPY-TRADING SOLANA ===
Trader copié      : 89HbgWduLwoxcofWpmn1EiF9wEdpgkNDEyPjzZ72mkDi
Montant par achat : 0.05 SOL
MODE RÉEL : le bot trade avec ton argent.
14:02:11 INFO  Solde : 1.2000 SOL
14:02:11 OK    Connexion temps réel (websocket) active.
14:02:11 OK    En écoute du trader 89Hb…mkDi… (Ctrl+C pour arrêter)
14:05:43 TRADER a ACHETÉ 7xKX…9fQp pour 2.5000 SOL via Pump.fun  https://dexscreener.com/solana/...
14:05:44 ACHAT BONK2 : 0.0500 SOL -> 1 523 000 tokens (Jupiter, 1.2 s)  https://solscan.io/tx/...
14:21:09 TRADER a VENDU 50% de ses BONK2 pour 3.1000 SOL via PumpSwap
14:21:10 VENTE BONK2 : 50% vendu (761 500 tokens) -> 0.0310 SOL (Jupiter, 1.1 s)  https://solscan.io/tx/...
14:40:52 TRADER a VENDU 100% de ses BONK2 pour 2.9000 SOL via PumpSwap
14:40:54 VENTE BONK2 : TOUT vendu (761 500 tokens) -> 0.0290 SOL (Jupiter, 1.3 s)  https://solscan.io/tx/...
14:40:54 OK    Position fermée. Résultat total sur BONK2 : +0.0100 SOL (+20%)
```

---

## Comment ça marche (en détail)

**Détection.** Le bot écoute toutes les transactions du wallet du trader. Pour chacune, il compare les soldes du trader **avant et après** :

- un token **augmente** et le trader a **payé** (en SOL, USDC/USDT ou un autre token) sur un DEX → c'est un **ACHAT** ;
- un token **diminue** sur un DEX → c'est une **VENTE**, et le pourcentage vendu = quantité vendue ÷ solde avant la vente ;
- un échange token → token donne une vente du premier token et un achat du second ;
- les transactions que le trader n'a pas signées (airdrops, tokens reçus) et les simples envois de tokens sont ignorés.

**Achat.** À chaque achat détecté, le bot achète le même token pour exactement `BUY_AMOUNT_SOL`, au meilleur prix via Jupiter. Il n'achète pas dans ces cas :

- le trade date de plus de `MAX_TRADE_AGE_SEC` secondes ;
- ton solde descendrait sous `MIN_SOL_RESERVE` ;
- la limite `MAX_BUYS_PER_TOKEN` est atteinte.

**Vente au même pourcentage.** Exemple : le trader a 1 000 000 tokens et en vend 250 000, soit **25 %**. Tu as 40 000 tokens, donc le bot en vend **10 000** (25 % des tiens). Si le trader vend 99 % ou plus, le bot vend **100 %** et ferme le compte du token pour récupérer ~0,002 SOL. Les pourcentages se suivent vente après vente : tu gardes toujours la même proportion que le trader.

**Ordre garanti.** Les trades d'un même token sont traités dans l'ordre, un par un. Si le trader achète puis revend 3 secondes plus tard, le bot attend la fin de son achat avant de vendre.

**Fiabilité.** Chaque transaction est :

- envoyée avec des frais de priorité (`PRIORITY_FEE_SOL` au maximum) ;
- renvoyée toutes les 2 secondes jusqu'à confirmation ;
- retentée `MAX_RETRIES` fois avec un nouveau prix si elle échoue (slippage, réseau chargé).

**Redémarrage.** Le bot enregistre sa progression dans le dossier `data/`. Au redémarrage :

- il rattrape les **ventes** faites par le trader pendant qu'il était éteint ;
- il ne rachète **jamais** de vieux achats, car le prix a changé ;
- un trade déjà copié n'est jamais copié deux fois.

**Coûts par trade :**

- frais réseau Solana : ~0,000005 SOL ;
- frais de priorité : ≤ `PRIORITY_FEE_SOL` ;
- ~0,002 SOL de « loyer » pour chaque nouveau token, récupéré quand tu vends tout ;
- PumpPortal prend ~0,5 %, uniquement quand il est utilisé en secours. Jupiter ne prend pas de commission.

Tout est enregistré dans `logs/bot.log`.

---

## Tous les réglages du fichier `.env`

| Réglage | Par défaut | Rôle |
|---|---|---|
| `PRIVATE_KEY` | — | **Obligatoire.** Clé privée du wallet du bot (format Phantom/Solflare, ou tableau `[1,2,…]`) |
| `TARGET_WALLET` | `89Hb…mkDi` | Wallet du trader à copier |
| `BUY_AMOUNT_SOL` | `0.05` | **Obligatoire.** SOL dépensé à **chaque** achat du trader |
| `RPC_URL` | RPC public | Connexion à Solana. Un RPC Helius gratuit est fortement conseillé |
| `WS_URL` | auto | Websocket temps réel. Laisse vide : il est déduit de `RPC_URL` |
| `JUPITER_API_KEY` | vide | Clé gratuite de https://portal.jup.ag (fortement conseillée) |
| `DRY_RUN` | `true` | `true` = simulation, `false` = vrais trades |
| `SLIPPAGE_PERCENT` | `15` | Écart de prix max accepté à l'achat (%) |
| `SELL_SLIPPAGE_PERCENT` | `20` | Écart de prix max accepté à la vente (%) : plus haut pour être sûr de sortir |
| `PRIORITY_FEE_SOL` | `0.0005` | Frais de priorité **max** par transaction. Monte-les si tes trades expirent |
| `MIN_SOL_RESERVE` | `0.02` | SOL toujours gardé pour payer les frais (le bot n'achète pas en dessous) |
| `COPY_SELLS` | `true` | Copier les ventes (même %) |
| `MAX_BUYS_PER_TOKEN` | `0` | Achats max par token tant que la position est ouverte (`0` = copie chaque achat) |
| `MIN_TRADER_BUY_SOL` | `0` | Ignore les achats du trader inférieurs à ce montant (filtre les petits tests) |
| `MAX_TRADE_AGE_SEC` | `60` | N'achète pas si le trade du trader est plus vieux que ça |
| `ONLY_SELL_BOT_TOKENS` | `true` | Ne vend que les tokens achetés par le bot (protège tes autres tokens) |
| `CATCH_UP_SELLS` | `true` | Au redémarrage, copie les ventes manquées |
| `CLOSE_EMPTY_ACCOUNTS` | `true` | Récupère les ~0,002 SOL des comptes de token vidés |
| `PUMPPORTAL_FALLBACK` | `true` | Secours PumpPortal si Jupiter ne connaît pas encore le token |
| `MAX_RETRIES` | `2` | Nouvelles tentatives si un trade échoue |
| `IGNORE_TOKENS` | vide | Adresses de tokens à ne jamais copier (séparées par des virgules) |
| `POLL_INTERVAL_SEC` | `2` | Vérification de secours (en plus du temps réel) |
| `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` | vide | Notifications Telegram (étape 10) |
| `DEBUG` | `false` | Logs détaillés |

Après chaque modification de `.env`, **redémarre le bot** (Ctrl + C, puis `npm start`).

---

## Problèmes fréquents

| Message / problème | Solution |
|---|---|
| `PRIVATE_KEY : clé privée invalide` | Tu as sans doute collé l'**adresse** au lieu de la **clé privée**. Refais l'étape 3. Pas d'espace ni de guillemets autour. |
| `Le fichier .env n'existait pas` | Normal au premier lancement : ouvre `.env`, remplis-le (étape 5) et relance. |
| `solde insuffisant` | Ajoute du SOL sur le wallet du bot, ou baisse `BUY_AMOUNT_SOL`. N'oublie pas la réserve `MIN_SOL_RESERVE`. |
| `Jupiter refuse la requête (HTTP 401/403)` | Clé Jupiter absente ou fausse : refais l'étape 4. |
| `Le RPC limite les requêtes (429)` / RPC lent | Le RPC public est saturé : prends un RPC Helius gratuit (étape 4). |
| `transaction expirée sans confirmation` | Réseau chargé : monte `PRIORITY_FEE_SOL` (ex : `0.001` ou `0.002`). |
| `probablement slippage dépassé` | Le prix a bougé trop vite. Le bot réessaie tout seul. Si ça arrive souvent, monte `SLIPPAGE_PERCENT`. |
| Le bot n'achète rien | Tu es en simulation (`DRY_RUN=true`) ? Le trader a-t-il vraiment tradé depuis le lancement ? `npm run check` montre ses derniers trades. |
| Le trader vend mais pas le bot | Le bot n'avait pas ce token (achat raté ou fait avant le lancement du bot). Avec `ONLY_SELL_BOT_TOKENS=true`, il ne touche qu'à ce qu'il a acheté. |
| Le fichier s'appelle `.env.txt` | Renomme-le en `.env` (étape 5, piège Windows). |
| Un token est bloqué / invendable | `npm run sell-all`, ou vends-le à la main dans Phantom. |

**Ce qui n'est pas copié :**

- les ordres à cours limité et les DCA du trader : ils sont exécutés par un robot tiers, pas signés par le trader ;
- les tokens qu'il envoie vers un autre wallet ;
- les dépôts de liquidité.

---

## Sécurité

- Ta clé privée reste **sur ton ordinateur**, dans `.env`. Ce fichier est exclu de Git (`.gitignore`). Le bot signe les transactions **localement** et n'envoie à Internet que des transactions déjà signées, jamais la clé.
- Utilise un **wallet dédié** avec un montant limité. N'y mets jamais tes économies.
- Les versions des librairies sont figées (`package-lock.json`). N'installe pas de mises à jour au hasard.
- Si tu penses que ta clé a fuité : transfère **immédiatement** tes fonds vers un nouveau wallet.

---

## Structure du projet

```
.env.example        modèle de configuration (à copier en .env)
src/index.js        lancement du bot (npm start)
src/bot.js          surveillance du trader et copie des trades
src/parser.js       analyse d'une transaction : achat ? vente ? quel % ?
src/executor.js     exécution des achats/ventes (réel ou simulation)
src/swap.js         Jupiter + PumpPortal (secours)
src/solana.js       envoi/confirmation des transactions, soldes
src/state.js        sauvegarde des positions (dossier data/)
src/config.js       lecture et vérification du .env
src/scripts/        npm run check / status / sell-all
test/               tests automatiques (npm test)
```
