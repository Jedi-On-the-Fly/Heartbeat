# HeartBeat — Méthode d'orchestration agent pour NanoClaw

## Qu'est-ce que c'est ?

HeartBeat est une méthode d'orchestration de projets IA à long cours. Elle résout le problème fondamental des agents LLM sur des projets complexes : comment faire travailler un agent de façon autonome pendant des heures ou des jours, sans supervision, sans perdre le fil, sans consommer des tokens inutilement ?

La réponse : séparer le scheduling (bash, rapide, déterministe, 0 token) de l'exécution (LLM, coûteux, activé seulement quand il y a du vrai travail).

```
tick.sh (toutes les 15-30 min)          ← Stage A — bash pur, 6 vérifications
  │
  ├─ wakeAgent: false → rien, on attend
  └─ wakeAgent: true  → Claude activé   ← Stage B — LLM, uniquement si nécessaire
```

Le projet est décrit comme un DAG (graphe acyclique orienté) : phases, tâches, dépendances, gates qualité. Claude exécute les tâches une à une, valide les gates, met à jour l'état, et libère le lock. Le tick suivant décide quoi faire ensuite.

## Ce qui est dans ce ZIP

```
heartbeat-nanoclaw/
  README-SETUP.md          ← ce fichier
  bootstrap.sh             ← initialise un projet HeartBeat dans n'importe quel dossier
  SKILL.md                 ← skill NanoClaw (à copier dans ~/.claude/skills/heartbeat/)
  CLAUDE-MD-SNIPPET.md     ← section à ajouter dans CLAUDE.md du groupe
  templates/
    tick.sh                ← Stage A : 6 vérifications, sort { wakeAgent, data }
    gate.sh                ← validation de gate (critères bash)
    hb-next-task.js        ← résout la prochaine tâche (gate-aware, diagnostic deadlock)
    hb-lint.js             ← validation statique du DAG
    hb-report.js           ← rapport d'avancement (texte / --json)
    hb-viz.js              ← génère dag-view.html (visualisation autonome)
    dag.json               ← template de DAG (à remplir par projet)
    state.json             ← état initial
  tests/
    run-tests.sh           ← suite de régression (43 assertions)
    fixtures/              ← fixtures de test
```

---

## Prérequis

- Node.js (v18+)
- NanoClaw avec schedule_task disponible
- Un groupe NanoClaw actif

---

## Procédure d'installation (une seule fois)

### Étape 1 — Copier les fichiers dans le workspace NanoClaw

Déposer le contenu de ce ZIP dans le workspace du groupe NanoClaw, par exemple :

```
/workspace/group/projects/heartbeat/
```

Structure attendue :
```
/workspace/group/projects/heartbeat/
  bootstrap.sh
  templates/
  tests/
  SKILL.md
  README-SETUP.md
```

### Étape 2 — Installer le skill

Copier `SKILL.md` dans le répertoire des skills globaux :

```bash
mkdir -p ~/.claude/skills/heartbeat
cp SKILL.md ~/.claude/skills/heartbeat/SKILL.md
```

Le skill `/heartbeat` est maintenant disponible dans NanoClaw.

### Étape 3 — Ajouter l'intégration système dans CLAUDE.md

Ouvrir `CLAUDE-MD-SNIPPET.md` et copier son contenu à la fin de `CLAUDE.md` du groupe (le fichier `/workspace/group/CLAUDE.md`).

Cela permet à Claude d'agir automatiquement sur les ticks sans qu'on lui explique le protocole à chaque session.

### Étape 4 — Vérifier l'installation

```bash
bash /workspace/group/projects/heartbeat/tests/run-tests.sh
# → 43 passés, 0 échoués ✅
```

---

## Procédure de démarrage d'un projet

### 1. Bootstrapper le projet

Dans NanoClaw, envoyer :
> "Lance un projet HeartBeat pour [description du projet]"

Ou directement :
```
/heartbeat init /workspace/group/mon-projet
```

Cela crée :
```
mon-projet/
└── .hb/
    ├── tick.sh
    ├── gate.sh
    ├── hb-next-task.js
    ├── hb-lint.js
    ├── hb-report.js
    ├── hb-viz.js
    ├── dag.json       ← À REMPLIR
    ├── state.json
    └── events.jsonl
```

### 2. Co-écrire le DAG avec Claude

Décrire le projet en langage naturel :
> "Mon projet a 3 phases : recherche, développement, livraison. Chaque phase doit passer une gate avant de continuer."

Claude propose le dag.json, on itère jusqu'à validation.

### 3. Valider le DAG

```
/heartbeat lint /workspace/group/mon-projet
```

Détecte cycles, IDs dupliqués, dépendances cassées, gates non définies.

### 4. Planifier l'exécution autonome

```
/heartbeat schedule /workspace/group/mon-projet
```

Claude génère et soumet le `schedule_task` nanoclaw. Le projet tourne seul.

### 5. Suivre l'avancement

```
/heartbeat status /workspace/group/mon-projet
```

Ou visuellement :
```
/heartbeat viz /workspace/group/mon-projet
```

---

## Pendant l'exécution

Claude se réveille automatiquement et exécute les tâches. Il ne vous sollicite que pour :
- Une gate bloquée (critères qualité non remplis)
- Un blocage (build_stuck) nécessitant une décision humaine
- La fin du projet (all_done)

Pour arrêter proprement : annuler le scheduled task dans NanoClaw.

---

## Cas d'usage

| Type | Exemple |
|---|---|
| App / dev | API backend, migration DB, refactor, CI/CD setup |
| Contenu | Série d'articles, pitch deck, documentation |
| Recherche | Veille concurrentielle, analyse de marché |
| Ops | Audit de sécurité, migration d'infrastructure |
| Data | Pipeline ETL, entraînement de modèle |

---

## Références

- README complet : `README.md` dans le repo heartbeat
- Changelog v1.1 / v1.2 : voir README.md
- Tests de régression : `tests/run-tests.sh`
