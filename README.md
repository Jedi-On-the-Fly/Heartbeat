# HeartBeat — Guide de démarrage (v1.2)

> Orchestration d'agent par tick. Le Stage A (bash) tourne toutes les 15-30 min. Le Stage B (agent IA) ne se réveille que s'il y a du travail réel.

---

## Installation sur Claude Code

HeartBeat s'installe comme **plugin Claude Code** (recommandé) ou via un
**script de secours**. Détails complets : [`INSTALL.md`](INSTALL.md).

```
# Plugin (rien n'est publié — marketplace locale)
/plugin marketplace add <chemin-vers-ce-dossier>
/plugin install heartbeat

# — ou — script de secours
bash scripts/install.sh
```

Puis `/heartbeat help`. Planification : `/heartbeat schedule <dir>` génère une
routine `/schedule` (voir la section Scheduling d'`INSTALL.md` pour les limites
cloud/git et les alternatives locales `/loop` et cron système).

---

## Démarrage rapide

```bash
# 1. Initialiser un nouveau projet
bash /workspace/group/projects/heartbeat/bootstrap.sh /workspace/group/mon-projet
#    (ajouter --force pour écraser un .hb/ existant sans prompt)

# 2. Éditer le DAG
nano /workspace/group/mon-projet/.hb/dag.json

# 3. Tester le tick manuellement
bash /workspace/group/mon-projet/.hb/tick.sh

# 4. Planifier (nanoclaw)
# → utiliser schedule_task avec tick.sh comme script
```

---

## Structure après bootstrap

```
mon-projet/
└── .hb/
    ├── tick.sh            ← Stage A : 6 vérifications, sort { wakeAgent, data }
    ├── gate.sh            ← Validation de gate : bash gate.sh GATE_P0
    ├── hb-next-task.js    ← Résout la prochaine tâche (gate-aware, diagnostic deadlock)
    ├── hb-lint.js         ← Validation statique du DAG (bootstrap + à la demande)
    ├── hb-report.js       ← Rapport d'avancement (texte / --json)
    ├── hb-viz.js          ← Génère dag-view.html (visualisation autonome)
    ├── dag.json           ← TON PROJET : phases, tâches, dépendances, critères de gate
    ├── state.json         ← État runtime (phase courante, tâches complétées, etc.)
    ├── events.jsonl       ← Journal d'audit append-only
    ├── architecture.hash  ← Baseline de drift (auto-créée si WATCH_PATHS défini)
    └── .lock              ← Verrou de session (répertoire — voir "Lock" ci-dessous)
```

---

## Structure de dag.json

```json
{
  "gates": {
    "GATE_P0": {
      "desc": "Description lisible",
      "criteria": [
        {
          "id": "G0_1",
          "desc": "Ce que ce critère vérifie",
          "cmd": "commande bash qui retourne exit 0 si OK"
        }
      ]
    }
  },
  "phases": [
    {
      "id": "P0",
      "title": "Nom de la phase",
      "desc": "Ce que cette phase produit",
      "gate_entry": null,
      "gate_exit": "GATE_P0",
      "tasks": [
        { "id": "P0T1", "title": "Nom de la tâche", "description": "Ce que l'agent doit faire", "requires": [] },
        { "id": "P0T2", "title": "Deuxième tâche", "description": "Ce que cette tâche produit", "requires": ["P0T1"] }
      ]
    }
  ]
}
```

**Règles :**
- Les IDs de tâches doivent être uniques dans tout le DAG
- `requires` = liste d'IDs de tâches devant être `done` avant que cette tâche soit éligible
- **`gate_entry` est appliquée par le resolver** (v1.1) : aucune tâche d'une phase n'est servie tant que la phase portant la `gate_exit` correspondante n'est pas dans `completed_phases`. Les gates ne sont plus contournables.
- Les `cmd` de gate s'exécutent avec `eval` **dans un sous-shell** — `$PROJECT_DIR` et `$HB_DIR` sont disponibles ; une variable inconnue = critère ✗ (plus de crash silencieux). Gardez-les déterministes, sur une ligne, rapides (< 5s)
- Les critères de gate valident le **comportement** (fichier existe, JSON parse) pas la structure

---

## Structure de state.json

```json
{
  "current_phase": "P0",
  "active_tasks": [],
  "completed_tasks": [],
  "completed_phases": [],
  "build_stuck_count": 0,
  "gate": { "errors": 0 },
  "last_event": "initialized",
  "last_updated": "2026-07-06T..."
}
```

**L'agent met à jour ce fichier** après chaque tâche — **toujours en écriture atomique** (un state.json tronqué à mi-écriture réveillera le système en `state_corrupted`) :

```bash
node -e "
  const fs=require('fs');
  const s=JSON.parse(fs.readFileSync('.hb/state.json','utf8'));
  s.completed_tasks.push('P0T1');            // vos modifications
  s.last_updated=new Date().toISOString();
  fs.writeFileSync('.hb/state.json.tmp', JSON.stringify(s,null,2));
  fs.renameSync('.hb/state.json.tmp', '.hb/state.json');   // rename = atomique
"
```

---

## tick.sh — 6 vérifications prioritaires (Stage A)

```
1. Lock              mkdir atomique — session en cours → dort (already_running).
                     Lock périmé (> LOCK_STALE_S, défaut 30 min) → auto-cassé.
2. Intégrité         state.json corrompu → RÉVEIL state_corrupted (l'agent
                     reconstruit depuis events.jsonl) ; dag.json corrompu →
                     RÉVEIL dag_corrupted (restaurer depuis backup/git)
3. Circuit breaker   build_stuck_count ≥ 5 → réveil UNE seule fois pour revue
                     humaine, puis silence (stuck_waiting_human) jusqu'au reset
4. Drift detection   SHA256 de WATCH_PATHS — baseline auto-gelée au 1er run ;
                     changement non sanctionné → réveil unsanctioned_drift
5. Gate errors       gate précédente en échec → réveil immédiat (gate_blocked)
6. Next task         tâche pending éligible → réveil ; tâches finies mais gate
                     pas passée → réveil gate_pending ; projet fini → UN réveil
                     all_done puis silence (project_complete) ; rien d'actionnable
                     sur un projet NON fini → UN réveil deadlock avec diagnostic
                     (active_orphan | dag_invalid | unsatisfiable), puis silence
```

La sortie est toujours : `{ "wakeAgent": true/false, "data": { "reason": "...", ... } }`

### Lock — cycle de vie (v1.1)

Le lock protège la **session agent**, pas seulement le tick. Quand `wakeAgent:true`,
le tick **laisse le lock en place** : c'est à l'agent de le libérer en fin de session
avec `rm -rf .hb/.lock`. Si l'agent meurt, le seuil de staleness (`LOCK_STALE_S`,
défaut 1800s, surchargeable en variable d'environnement) casse le lock au tick suivant.

### Drift — sanctionner un refactoring

```bash
bash .hb/tick.sh --freeze   # re-gèle la baseline après un changement volontaire
```

---

## Validation de gate (Stage A ou manuel)

```bash
bash .hb/gate.sh GATE_P0

# === Gate: GATE_P0 ===
#   ✓ [G0_1] Le répertoire projet existe
#   ✓ [G0_2] state.json est un JSON valide
# === Result: 2 passed, 0 failed ===
# ✅ GATE PASSED — proceed to next phase.
```

Les gates écrivent dans `events.jsonl` à chaque passage ou échec.

---

## Planification nanoclaw

```
schedule_task :
  prompt: |
    Tu exécutes un tick HeartBeat pour le projet mon-projet.
    Le résultat du script est dans {{data}}.
    Agis selon {{data.reason}} :
      - next_task        → exécute {{data.next_task.title}} — {{data.next_task.description}}
      - gate_pending     → lance bash .hb/gate.sh {{data.next_task.gate}} et clôture la phase
      - gate_blocked     → corrige les critères en échec puis relance la gate
      - state_corrupted  → reconstruis .hb/state.json depuis events.jsonl et dag.json
      - dag_corrupted    → restaure .hb/dag.json depuis backup/git (structure immuable)
      - deadlock         → agis selon data.next_task.cause : active_orphan = retire
        les IDs de active_tasks ; dag_invalid = signale les erreurs pour revue humaine
      - unsanctioned_drift → examine les changements ; si voulus : bash .hb/tick.sh --freeze
      - build_stuck      → produis un rapport de blocage pour revue humaine
      - all_done         → rédige le rapport final du projet
    Mets à jour .hb/state.json en écriture ATOMIQUE (tmp + rename).
    OBLIGATOIRE en fin de session : rm -rf .hb/.lock

  script: |
    bash /workspace/group/mon-projet/.hb/tick.sh

  schedule_type: cron
  schedule_value: "*/20 * * * *"   # toutes les 20 min
  context_mode: isolated
```

---

## Responsabilités de l'agent (Stage B)

Quand réveillé par tick.sh, l'agent doit :

1. Lire `data.reason` et `data.next_task` depuis la sortie du tick
2. Exécuter la tâche (écrire du code, créer des fichiers, lancer des tests, etc.)
3. Mettre à jour `state.json` **atomiquement** (voir plus haut) :
   - Ajouter l'ID de la tâche à `completed_tasks`
   - Remettre `build_stuck_count` à 0 en cas de succès (incrémenter en cas d'échec, y compris échec répété de gate)
4. Sur `gate_pending` : `bash .hb/gate.sh <GATE>` ;
   passée → ajouter la phase à `completed_phases`, avancer `current_phase` ;
   échouée → `gate.errors = 1` dans state (le tick réveillera au prochain cycle)
5. Sur `state_corrupted` : reconstruire state.json depuis `events.jsonl` + `dag.json` ;
   sur `deadlock` cause `active_orphan` : retirer les IDs de `active_tasks` (reprise)
6. **Convention v1.2** : appender `{"ts":"...","event":"task_done","task":"ID"}` dans
   `events.jsonl` à chaque tâche terminée — hb-report s'en sert
7. Sur `unsanctioned_drift` : examiner ; si le changement est voulu → `bash .hb/tick.sh --freeze`
8. **Toujours, en fin de session : `rm -rf .hb/.lock`**

---

## Tests

```bash
bash tests/run-tests.sh   # suite de régression complète (24 assertions)
```

---

## Retours d'expérience — vizcore-demo (26 phases, 115 tâches)

| Règle | Détail |
|---|---|
| Gates comportementales, pas structurelles | `test -f output.js` casse au renommage ; `node -e "require('./output')"` résiste |
| Phases ≤ 8 tâches | Au-delà, risque de perte de contexte entre sessions |
| Planifier le DAG avant de coder | Révèle les problèmes d'intégration avant de les rencontrer |
| `requires` sparse | Éviter les cascades de blocage — ne déclarer que les vraies dépendances |
| stuck_count = signal d'alerte précoce | S'il monte, arrêter et réviser manuellement |
| WATCH_PATHS pour les modules critiques | Détecte les refactorings accidentels qui cassent les gates |

---

## Changelog v1.1 (2026-07-06)

| # | Correctif | Sévérité |
|---|---|---|
| 1 | gate.sh : `$PROJECT_DIR` non défini + `set -u` → crash silencieux sur le template | 🔴 bug |
| 2 | Resolver : `gate_entry` ignorée → tâches servies avant validation de gate | 🔴 bug |
| 3 | state.json corrompu → `wakeAgent:false` silencieux ; devient réveil `state_corrupted` | 🔴 bug |
| 4 | Lock : libéré à la fin du tick au lieu de la session agent ; devient lock de session (mkdir atomique, staleness 30 min, `stat` portable GNU/BSD) | 🟠 design |
| 5 | `architecture.hash` jamais créé → drift inopérant ; auto-freeze + `--freeze` | 🟠 design |
| 6 | Circuit breaker : réveil à chaque tick une fois déclenché ; devient alerte unique | 🟠 design |
| 7 | `all_done` : boucle de réveil en fin de projet ; devient alerte unique + `gate_pending` explicite | 🟠 design |
| 8 | Pipeline drift : `pipefail` + find en échec tuait le tick (bug latent découvert en cours) | 🟠 latent |
| 9 | bootstrap : `read -p` crashait en contexte non-interactif ; EOF-safe + `--force` | 🟡 mineur |
| 10 | gate.sh : parsing en 1 appel node, gate ID en argv (fix injection), critères en sous-shell | 🟡 mineur |


---

## Outils v1.2

```bash
node .hb/hb-lint.js .hb/dag.json          # valider le DAG (exit 1 si erreurs)
node .hb/hb-report.js .hb                 # rapport d'avancement (ajouter --json)
node .hb/hb-viz.js .hb                    # génère .hb/dag-view.html (autonome)
```

Le lint tourne automatiquement au bootstrap. Lancez-le après CHAQUE édition de
dag.json — il attrape à l'édition ce qui, avant v1.2, devenait un deadlock
silencieux au tick N.

---

## Changelog v1.2 (2026-07-06)

| # | Évolution | Type |
|---|---|---|
| 1 | hb-lint.js : validation statique du DAG (IDs dupliqués, requires cassés, cycles, gates non définies ou inatteignables), intégré au bootstrap | 🔴 fiabilité |
| 2 | Resolver : plus jamais `null` sur un projet non fini — `{type:"deadlock", cause, detail}` avec diagnostic (active_orphan / dag_invalid / unsatisfiable) | 🔴 fiabilité |
| 3 | tick.sh : dag.json corrompu → réveil `dag_corrupted` ; deadlock en alerte unique (flag `.deadlock-alerted`) | 🔴 fiabilité |
| 4 | hb-report.js : avancement, stats gates, incidents, durées de phase depuis events.jsonl — texte + `--json` | 🟠 observabilité |
| 5 | Convention `task_done` dans events.jsonl (responsabilité agent) | 🟠 observabilité |
| 6 | hb-viz.js : visualisation HTML 100% autonome du DAG et de son état | 🟡 visualisation |
| 7 | Suite de régression : 43 assertions (T11-T14 ajoutés) | 🟢 qualité |

Développé en dogfooding : ce plan v1.2 a été exécuté par HeartBeat v1.1
(dag.json de 5 phases / 9 tâches / 5 gates, 25 critères exécutables).

---

## Changelog v1.3 — durcissement fiabilité (2026-07-10)

| # | Évolution | Type |
|---|---|---|
| 1 | **State événementiel (`hb.js`)** : `events.jsonl` fait autorité, `state.json` est une projection déterministe. L'agent mute l'état UNIQUEMENT via `hb` (`start`/`done`/`fail`/`rebuild`/`state`/`import`) — plus d'édition JSON à la main. | 🔴 fiabilité |
| 2 | **Auto-réparation** : `state.json` corrompu → le tick reprojette depuis le log (`hb rebuild`) ; ne réveille `state_corrupted` que si le log est inutilisable. | 🔴 fiabilité |
| 3 | **Détection no-progress objective** : un agent réveillé N fois sans progresser → `build_stuck` (`signal: no_progress`), indépendamment de son auto-report. | 🔴 fiabilité |
| 4 | **Timeout des critères de gate** (`GATE_TIMEOUT_S`, 5s) : un critère qui pend bloque la gate au lieu de figer le tick. | 🟠 robustesse |
| 5 | **Leases par tâche + concurrence bornée** (`HB_MAX_CONCURRENCY`, défaut 1 = série) : les branches indépendantes du DAG tournent en parallèle ; leases périmées réclamées automatiquement. Le lock de session devient un lock de handout court. | 🟠 design |
| 6 | **Heartbeat mi-session** (`hb heartbeat <id>`, `HEARTBEAT_STALE_S`, défaut 180s) : une lease pendue est réclamée en minutes (cadence du tick) au lieu de `LOCK_STALE_S` ; les leases sans heartbeat gardent le fallback lent. | 🟠 fiabilité |
| 7 | Suite de régression : 69 assertions (T16-T20 ajoutés ; T4/T5 réécrits). | 🟢 qualité |

### Le CLI `hb` (Stage B)

```bash
node .hb/hb.js start <id>   # claim (lease) + task_started
node .hb/hb.js done  <id>   # task_done  → libère la lease, remet stuck à 0
node .hb/hb.js fail  <id>   # task_failed → libère la lease, incrémente stuck
node .hb/hb.js heartbeat <id> # tâche longue : rafraîchit la lease (anti-reclaim)
node .hb/hb.js rebuild      # reprojette state.json depuis le log (sync / recovery)
node .hb/hb.js state        # affiche l'état projeté
node .hb/hb.js import       # migre un projet pré-v1.3 (state.json → événements)
```

### Config (env, overridable)

| Variable | Défaut | Rôle |
|---|---|---|
| `GATE_TIMEOUT_S` | 5 | Timeout par critère de gate |
| `STUCK_TICKS` | 3 | Réveils no-progress avant `build_stuck` |
| `HB_MAX_CONCURRENCY` | 1 | Tâches en vol simultanées (leases) |
| `HEARTBEAT_STALE_S` | 180 | Silence toléré d'une lease heartbeatée avant reclaim |
| `LOCK_STALE_S` | 1800 | Péremption lock / lease sans heartbeat / write-lock |