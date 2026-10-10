# Loot & Forge — un jeu Roblox inspiré de « +1 Loot To Forge »

Un simulateur de donjon : tu bats des monstres → chaque kill donne **+1 minerai** →
tu **forges** des armes avec tes minerais → tu deviens plus fort → tu débloques les
étapes suivantes → tu fais un **Rebirth** pour un multiplicateur permanent.

## Ce qu'il y a dans le jeu

| Élément | Détail |
|---|---|
| **Hub** | Point d'apparition, 7 tapis d'entraînement, enclume (forge), marchand, armurerie, boutique, autel de rebirth, portail du donjon |
| **Donjon** | 12 étapes (arènes) : 4 monstres + 1 boss 👑 chacune. Battre le boss débloque l'étape suivante |
| **Minerais** | 13 minerais, de *Pierre* (×1) à *Apex* (×1000), 7 raretés |
| **Forge** | 4 à 12 minerais = **Katana** (rapide, 1 cible) · 13+ minerais = **Espadon** (lent, dégâts de zone). Max 4 types de minerais. Qualité aléatoire : Commun → Mythique (×3.5) |
| **Entraînement** | Reste sur un tapis pour gagner de la puissance (+1/s → +25 000/s) |
| **Boutique** | Capacité de minerais (+5 places), Chance (minerais plus rares) |
| **Rebirth** | Remet puissance et étapes à zéro, mais donne ×2, ×3, ×4… sur l'entraînement **et** les dégâts |
| **Sauvegarde** | Automatique (DataStore) toutes les 90 s et quand on quitte |
| **Interface** | Boutons arrondis animés, compteurs en pastilles, barre de menus en tuiles, s'adapte au téléphone |

**Formule des dégâts :** `Puissance × Multiplicateur de l'arme × Multiplicateur de rebirth`

## Les fichiers

`LootForge.rbxlx` est le jeu complet, prêt à ouvrir dans Roblox Studio. Les 3 scripts
ci-dessous sont les mêmes, pour ceux qui préfèrent copier-coller.

| Fichier | Type dans Studio | Où le mettre | Nom exact |
|---|---|---|---|
| `ReplicatedStorage/GameConfig.lua` | **ModuleScript** | ReplicatedStorage | `GameConfig` ⚠️ obligatoire |
| `ServerScriptService/GameServer.server.lua` | **Script** | ServerScriptService | `GameServer` |
| `StarterPlayerScripts/GameClient.client.lua` | **LocalScript** | StarterPlayer → StarterPlayerScripts | `GameClient` |

Pas besoin de construire la carte ni l'interface à la main : **les scripts créent tout
automatiquement** au lancement (hub, arènes, monstres, menus).

## Méthode la plus simple : ouvrir le fichier du jeu (recommandé)

Le fichier **`LootForge.rbxlx`** contient déjà les 3 scripts, rangés au bon endroit.
Aucun copier-coller, aucune erreur de nom possible.

1. Télécharge **`LootForge.rbxlx`** (dans ce dossier).
2. Double-clique dessus, ou dans Roblox Studio : **File → Open from File…** et choisis-le.
3. Le monde est vide avec juste le texte « appuie sur Play » : **c'est normal**,
   la carte est construite par les scripts au lancement.
4. Clique sur **▶ Play** (F5). Tu apparais dans le hub. 🎉

## Installation à la main (copier-coller)

> Ajoute les scripts **en mode édition**, pas pendant un test (pas de bouton Stop
> rouge visible) : tout ce qui est ajouté pendant un test disparaît quand on l'arrête.

1. **Ouvre Roblox Studio** → *New* → choisis le modèle **Baseplate**.
2. **Affiche l'Explorer et les Propriétés** : onglet *View* (Affichage) → clique sur
   *Explorer* et *Properties*. L'Explorer est la liste à droite (Workspace,
   ReplicatedStorage, ServerScriptService…).
3. *(Conseillé)* Dans l'Explorer, ouvre **Workspace** et supprime **Baseplate**
   (clic droit → *Delete*). Le jeu est construit en hauteur, il n'en a pas besoin.
4. **Script 1 — la config :**
   - Passe la souris sur **ReplicatedStorage** → clique sur le **+** → choisis **ModuleScript**.
   - Clic droit dessus → *Rename* → tape exactement `GameConfig`.
   - Double-clique dessus pour l'ouvrir, **efface tout** (Ctrl+A puis Suppr), puis
     colle le contenu de `GameConfig.lua` (Ctrl+V).
5. **Script 2 — le serveur :**
   - Passe la souris sur **ServerScriptService** → **+** → **Script**.
   - Renomme-le `GameServer`, efface le `print("Hello world!")` et colle `GameServer.server.lua`.
6. **Script 3 — l'interface :**
   - Dans l'Explorer, ouvre **StarterPlayer** (clique sur la petite flèche) →
     passe la souris sur **StarterPlayerScripts** → **+** → **LocalScript**.
   - Renomme-le `GameClient`, efface tout et colle `GameClient.client.lua`.
7. Clique sur **▶ Play** (ou F5). Tu apparais dans le hub. 🎉

### Activer la sauvegarde (facultatif pour tester)

Sans ça, le jeu marche quand même, mais ta progression est perdue quand tu arrêtes.

1. *File* → **Publish to Roblox** (publie ton jeu, même en privé).
2. Onglet *Home* → **Game Settings** → **Security** → active
   **Enable Studio Access to API Services** → *Save*.

## Comment jouer

1. Entre dans le **portail violet** (🌀 Donjon) → choisis l'**étape 1**.
2. **Clique** (ou tape sur l'écran) pour frapper avec ton épée. Chaque monstre tué = **+1 minerai** et des pièces.
3. Avec 4 minerais ou plus, va à l'**enclume** (⚒ Forge) : choisis tes minerais avec **+ / − / Max** puis **FORGER**.
4. Bats le **boss 👑** pour débloquer l'étape suivante.
5. Trop dur ? Reste sur les **tapis d'entraînement** du hub pour gagner de la puissance.
6. Vends tes minerais en trop au **marchand**, achète de la **capacité** à la boutique.
7. Quand la barre de **Rebirth** est pleine → Rebirth pour un multiplicateur permanent !

Les boutons en bas de l'écran ouvrent aussi tous les menus depuis n'importe où.

## Personnaliser ton jeu

Tout se règle dans **GameConfig** (les commentaires expliquent chaque valeur) :

- `Config.GameTitle` : le nom affiché dans le hub
- `Config.Ores` : ajoute/modifie des minerais (nom, couleur, multiplicateur, prix)
- `Config.Stages` : noms des étapes, couleurs, noms des monstres et des boss
- `Config.EnemyHPGrowth` : difficulté (PV ×5 par étape par défaut)
- `Config.TrainingPads`, `Config.Upgrades`, `Config.RebirthBaseCost`…

Pour changer le **look de l'interface** (couleurs des boutons, des menus, polices),
ouvre `GameClient` et regarde la partie **STYLE** tout en haut : `THEME` (couleurs de
base), `ACCENT` (une couleur par menu) et les polices `FONT_TITLE` / `FONT_BODY`.

> ⚠️ Si tu ajoutes des étapes, ajoute aussi des minerais (une étape N lâche
> surtout le minerai N), sinon les dernières étapes donneront toutes le même.

## Si ça ne marche pas

Le jeu vérifie son installation tout seul :

- Si un script est **mal nommé ou mal rangé** (ex : la config s'appelle encore
  `ModuleScript`, ou l'interface est dans StarterGui), il est **réparé
  automatiquement** et un message jaune l'indique dans l'Output.
- Sinon, un **message rouge** s'affiche en haut de l'écran et dit exactement quoi
  corriger (script manquant, mauvais type de script, code mal collé…).
- En mode édition (avant Play), le monde est vide : c'est normal, tout est créé au lancement.

Dans la fenêtre **Output** (*View → Output*), quand tout va bien, tu dois lire
`[LootForge] Serveur prêt !` au lancement. Si tu ne vois ni le jeu, ni de message rouge,
ni cette ligne, alors les scripts ne sont pas la dernière version, ou ils ont été ajoutés
pendant un test (ils ont disparu au Stop).

Autres pistes :

- Ouvre la fenêtre **Output** (*View* → *Output*) : les erreurs y sont écrites en rouge.
- `Infinite yield possible on 'ReplicatedStorage:WaitForChild("GameConfig")'`
  → le ModuleScript n'est pas nommé exactement `GameConfig` ou pas dans ReplicatedStorage.
- **Ni carte ni menus** → c'est presque toujours **GameConfig** : il doit être un
  **ModuleScript** nommé exactement `GameConfig` dans ReplicatedStorage, et il ne doit
  rester ni `local module = {}` ni `return module` (le script se termine par `return Config`).
  Dans l'Output, on voit alors `Requested module experienced an error while loading`.
- **La carte est là mais pas les menus** → vérifie que `GameClient` est bien un
  **LocalScript** (pas un Script) dans **StarterPlayerScripts**.
- Pas de carte / pas de monstres → vérifie que `GameServer` est un **Script** dans
  **ServerScriptService**.
- Le plus sûr : utilise le fichier **`LootForge.rbxlx`** (méthode la plus simple, plus haut).
- La dernière ligne du script 2 doit être `print("[LootForge] Serveur prêt !")` : sinon
  il n'a pas été copié en entier.
- Si tu tombes dans le vide en arrivant dans une étape lointaine : sélectionne
  **Workspace** et décoche **StreamingEnabled** dans les Properties (déjà fait dans
  `LootForge.rbxlx`).
- Message « Sauvegarde désactivée » → normal dans Studio tant que l'accès API n'est
  pas activé (voir plus haut).

## Idées pour aller plus loin

- Codes promo (ex : `BIENVENUE` → 500 pièces), classement global, Game Pass ×2 dégâts
- Animations d'attaque perso, sons de kill, effets de particules sur les armes
- Pets qui ramassent les minerais, quêtes quotidiennes, tour infinie de boss
