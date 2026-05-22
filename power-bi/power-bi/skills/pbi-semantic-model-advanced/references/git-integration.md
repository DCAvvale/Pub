# Git Integration — Reference

Questo file gestisce l'integrazione git nel flusso di creazione del semantic model.
Viene invocato da skill.md negli STEP G1 (setup) e G-COMMIT (commit per milestone).

---

## STEP G1 — Setup git (invocato da STEP 6b di skill.md)

### G1.1 — Opt-in
Chiedi:
```
Vuoi abilitare la git integration per questo progetto?
[S] Sì — inizializzo o connetto una repo e creo una feature branch
[N] No — procedo senza git
```
Salva come {GitEnabled} = true / false.
Se false: termina qui, torna a skill.md STEP 7.

### G1.2 — Provider
Chiedi:
```
Quale provider git stai usando?
1. GitHub        (gh CLI — supportato ora)
2. Azure DevOps  (az CLI + devops extension — supportato ora)
3. Altro         (GitLab, Bitbucket…) — solo git locale, no PR automatica
```
Salva come {GitProvider} = "github" | "azuredevops" | "other".

#### Provider GitHub

Se {GitProvider} = "github", verifica subito gh installato e autenticato:
```bash
"C:/Program Files/GitHub CLI/gh.exe" auth status 2>&1
```
- Se il comando non esiste: avvisa "Installa gh CLI da https://cli.github.com, poi dimmi quando è pronto." e aspetta.
- Se già autenticato (`✓ Logged in`) → prosegui.
- Se non autenticato (`not logged in`): lancia il flusso OAuth:
```bash
"C:/Program Files/GitHub CLI/gh.exe" auth login --web --skip-ssh-key 2>&1 &
sleep 3
```
Mostra all'utente il codice one-time e il link `https://github.com/login/device`.
Aspetta che l'utente confermi il login completato, poi verifica con `auth status`.

#### Provider Azure DevOps

Se {GitProvider} = "azuredevops", verifica subito Azure CLI + devops extension:

```bash
# 1) az CLI installato?
az --version 2>&1 | head -3
```
- Se manca: installa con `winget install --id Microsoft.AzureCLI --silent --accept-package-agreements --accept-source-agreements`. Dopo l'installazione esporta il PATH: `export PATH="/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin:$PATH"`.

```bash
# 2) Estensione azure-devops presente?
az extension list 2>&1 | grep -i devops || az extension add --name azure-devops --yes
```

```bash
# 3) Login attivo?
az account show 2>&1 | head -3
```
- Se non autenticato: `az login` (apre il browser per autenticazione Microsoft 365). Aspetta che l'utente confermi il login completato.
- Se l'utente non ha accesso al browser locale: usa `az login --use-device-code` e mostra il codice/link.

```bash
# 4) Imposta org default per evitare di passarla a ogni comando
az devops configure --defaults organization=https://dev.azure.com/{Org}
```

**Gestione errori autenticazione Azure DevOps:**
- Errore HTTP 401/403 su push o PR → token scaduto: rilancia `az login`.
- Errore "TF400813" (utente senza permessi) → l'utente deve essere membro del progetto Azure DevOps con permessi Contributor minimi.
- Errore git push autenticazione fallita → al primo push, Git Credential Manager apre un prompt browser. In alternativa configura un PAT: Azure DevOps Portal → User Settings → Personal Access Tokens (scope: `Code: Read & Write`).

**Gestione errori autenticazione:**

- Se l'utente non completa in tempo (codice scaduto) o vuole riprovare: rilancia
  lo stesso comando `auth login --web --skip-ssh-key` senza chiedere conferma.
- Se dopo il login `auth status` mostra ancora `not logged in`: chiedi:
  ```
  Il login via browser non è riuscito. Come vuoi procedere?
  [1] Riprova con browser
  [2] Inserisci un Personal Access Token (PAT) manualmente
  ```
  - Opzione 2: esegui `gh auth login --with-token` e chiedi all'utente di incollare
    il PAT (scope minimi richiesti: `repo`, `read:org`).
- Se durante push o PR ricevi errore HTTP 401/403 (token scaduto o revocato): avvisa
  "Token GitHub scaduto o non valido." e proponi:
  ```
  [1] Rinnova con: gh auth refresh
  [2] Reinserisci un nuovo PAT
  ```
  Poi riprova automaticamente l'operazione fallita.

> **Nota per il futuro:** per aggiungere un nuovo provider, aggiungi una sezione
> "Provider: X" in fondo a questo file con le istruzioni specifiche per
> autenticazione e creazione PR. Il resto del flusso (init, branch, commit) è identico.

### G1.3 — Repo: esistente o nuova
Chiedi:
```
La cartella {CartellaProgetto} è già una git repo oppure devo inizializzarla?
1. Inizializza nuova repo locale (git init)
2. Collega a repo remota esistente (incolla URL)
3. Repo locale già inizializzata (git già presente nella cartella)
```

**Caso 1 — Init nuova:**
```bash
cd "{CartellaProgetto}"
git init
git branch -M main
```

Se {GitProvider} = "github": non chiedere se vuole una remote — crearla direttamente su GitHub.

⚠️ **PRIMA di chiedere il nome repo, mostrare questo warning e attendere conferma esplicita:**

```
⚠️  ATTENZIONE — Push su servizio esterno (github.com)

Stai per creare una repository su GitHub.com. Questo significa che i seguenti
contenuti del modello Power BI usciranno dal perimetro aziendale e finiranno
sui server di GitHub (Microsoft):

  • File TMDL — nomi tabelle, colonne, misure
  • Query M — server SQL, URL SharePoint, schema DB, ID workspace Fabric
  • Formule DAX — business logic, KPI, regole di calcolo
  • Documentazione tecnica (se generata a STEP 16)

Anche con repository PRIVATA, i dati sono fuori dal tuo tenant aziendale.

PRIMA di procedere verifica che:
  ☐ La tua azienda consenta il push di IP aziendale su GitHub
  ☐ Il livello di classificazione del dato lo permetta (no dati classificati,
    no contenuti soggetti a NDA o vincoli regolatori specifici)
  ☐ Stai usando un account GitHub aziendale (non personale) se richiesto

Vuoi procedere?
  [S] Sì — ho verificato, crea la repo su GitHub
  [N] No  — torna indietro e scelgo Azure DevOps o solo locale
```

Se l'utente risponde [N]: torna a G1.2 per riselezionare il provider.

Se l'utente risponde [S], chiedere il nome della repo (suggerire il nome del progetto in lowercase con trattini):

```
Come vuoi chiamare la repo su GitHub? (suggerimento: {NomeProgetto-kebab-case})
Pubblica come:
  [1] Privata (default consigliato per modelli Power BI aziendali)
  [2] Pubblica
```

Poi creare e collegare in un colpo solo:
```bash
cd "{CartellaProgetto}"
"C:/Program Files/GitHub CLI/gh.exe" repo create {RepoName} --{private|public} --source=. --remote=origin --push
```

Questo crea la repo su GitHub, imposta la remote `origin` e fa il primo push di `main` in automatico.
Salvare l'URL restituita come {GitRemoteURL} e ricavare {GitRepoPath} = `owner/repo`.

Se {GitProvider} = "azuredevops": chiedere se la repo esiste già su Azure DevOps o crearla via CLI.

Per creare la repo via CLI servono `Org`, `Project`, `RepoName`:
```bash
az repos create --name "{RepoName}" --project "{ProjectName}" --organization "https://dev.azure.com/{Org}" 2>&1
```
Salvare la `remoteUrl` dal JSON di risposta come {GitRemoteURL}, poi:
```bash
git remote add origin {GitRemoteURL}
git push -u origin main
```

Se la repo esiste già: chiedere all'utente la URL HTTPS clone della repo Azure DevOps (formato `https://{user}@dev.azure.com/{Org}/{Project}/_git/{RepoName}` oppure `https://dev.azure.com/{Org}/{Project}/_git/{RepoName}`).
```bash
git remote add origin {URL}
git push -u origin main 2>&1
```
Se la remote è vuota, il primo push pubblica `main`. Se la remote ha già commit, fare prima `git pull origin main --allow-unrelated-histories`.

Se {GitProvider} = "other": chiedere "Vuoi collegare una remote? (incolla URL o lascia vuoto per solo locale)"
Se URL fornita: `git remote add origin {URL}`

**Caso 2 — Clone/collega remota:**
```bash
git remote add origin {URL}
git fetch origin
git checkout main 2>/dev/null || git checkout -b main
```

**Caso 3 — Già inizializzata:** leggi la remote esistente:
```bash
git remote get-url origin 2>/dev/null || echo "NO_REMOTE"
```
Mostra l'URL trovato all'utente e chiedi conferma: "Ho trovato la remote: {URL} — è corretta?"

Salva {GitRemoteURL} (può essere vuota se solo locale).

### G1.3b — Ricava {GitRepoPath}

#### GitHub
Estrai `owner/repo` da {GitRemoteURL}:
- `https://github.com/owner/repo.git` → `owner/repo`
- `git@github.com:owner/repo.git` → `owner/repo`

Salva come {GitRepoPath}. Mostra all'utente: "Repo GitHub: {GitRepoPath} — corretto?"
Se sbagliato, chiedi la correzione prima di proseguire.

#### Azure DevOps
Estrai `Org`, `Project`, `RepoName` da {GitRemoteURL} (URL-decodificati). Esempi:
- `https://user@dev.azure.com/MyOrg/My%20Project/_git/My%20Repo` → Org=`MyOrg`, Project=`My Project`, RepoName=`My Repo`
- `https://dev.azure.com/MyOrg/My%20Project/_git/My%20Repo` → idem (senza prefisso utente)

Salva come {GitOrg}, {GitProject}, {GitRepoName}. Mostra all'utente:
```
Azure DevOps:
  Organization: {GitOrg}
  Project:      {GitProject}
  Repository:   {GitRepoName}
È corretto?
```
Se sbagliato, chiedi la correzione prima di proseguire.

### G1.4 — .gitignore
Verifica se esiste `{CartellaProgetto}/.gitignore`:
```bash
test -f "{CartellaProgetto}/.gitignore" && echo EXISTS || echo MISSING
```
- **Se MISSING:** crea `.gitignore` copiando il contenuto da `templates/gitignore.txt`
  (attualmente: `**/.pbi/localSettings.json` e `**/.pbi/cache.abf`)
- **Se EXISTS:** non sovrascrivere — verifica che le righe del template siano già presenti,
  se mancano aggiungile in append.

### G1.5 — Branch di lavoro

Il nome del branch è passato dal chiamante come `{BranchName}`:
- Flusso **creazione** (skill.md): `feature/{NomeProgetto}` (lowercase, spazi → trattini)
- Flusso **audit** (audit-existing-model.md): `audit/refactor-{DatasetName}-{YYYY-MM-DD}`

```bash
cd "{CartellaProgetto}"
git checkout -b {BranchName}
```

Conferma all'utente: "Branch `{BranchName}` creato."

---

## STEP G-COMMIT — Esegui un commit (chiamato dopo ogni milestone)

Parametri ricevuti da skill.md:
- `{CommitMessage}` — il messaggio da usare
- `{FilesPattern}` — pattern o lista file da aggiungere (es. `"."` per tutto)

```bash
cd "{CartellaProgetto}"
git add {FilesPattern}
git commit -m "{CommitMessage}"
```

Se {GitEnabled} = false: salta silenziosamente, non eseguire nulla.

---

## STEP G-PUSH-PR — Push e Pull Request

Parametri ricevuti dal chiamante:
- `{BranchName}` — branch da pushare (es. `feature/progetto` o `audit/refactor-...`)
- `{PRTitle}` — titolo della PR
- `{PRBody}` — body della PR (Markdown)

I valori concreti di `{PRTitle}` e `{PRBody}` sono definiti nelle sezioni
"Convenzione commit" (flusso creazione) e "Convenzioni audit" (flusso audit).

Se {GitEnabled} = false: salta.

### Push
```bash
cd "{CartellaProgetto}"
git push -u origin {BranchName}
```
Se {GitRemoteURL} è vuota (repo solo locale): avvisa l'utente che non è possibile
fare push senza remote e offri di aggiungerne una ora.

### Pull Request

**Se {GitProvider} = "github":**
```bash
cd "{CartellaProgetto}"
"C:/Program Files/GitHub CLI/gh.exe" pr create \
  --title "{PRTitle}" \
  --body "{PRBody}" \
  --base main \
  --head {BranchName}
```
Mostra l'URL della PR creata all'utente.

**Se {GitProvider} = "azuredevops":**
```bash
cd "{CartellaProgetto}"
az repos pr create \
  --organization "https://dev.azure.com/{GitOrg}" \
  --project "{GitProject}" \
  --repository "{GitRepoName}" \
  --source-branch "{BranchName}" \
  --target-branch main \
  --title "{PRTitle}" \
  --description "{PRBody}" 2>&1
```
Estrai la URL della PR dal JSON di risposta (campo `_links.web.href` o ricavata da `pullRequestId`) e mostrala all'utente.

**Se {GitProvider} = "other":**
Avvisa: "PR automatica non supportata per questo provider. Esegui il push
e apri la PR manualmente da {GitRemoteURL}."

---

## Convenzione commit — flusso creazione (skill.md)

### Parametri G1.5 e G-PUSH-PR per il flusso creazione

```
{BranchName} = feature/{NomeProgetto}   (lowercase, spazi → trattini)
{PRTitle}    = feat: {NomeProgetto} semantic model
{PRBody}     = (vedi template sotto)
```

**Template {PRBody} creazione:**
```markdown
## Semantic Model — {NomeProgetto}

### Tabelle
- Fact: {lista fact}
- Dimension: {lista dimension}
- Calendar, Calcs

### Relazioni
{N} relazioni — Star Schema validato

### Misure
{N} misure nella tabella Calcs

🤖 Generato con Claude Code + pbi-semantic-model-advanced skill
```

### Tabella milestone commit creazione

| Milestone (STEP skill.md) | CommitMessage | FilesPattern |
|---|---|---|
| STEP 7 — scaffold file | `feat: scaffold {NomeProgetto} — {N} tables, {connettore}` | `.` |
| STEP 10 — relazioni | `feat: add relationships ({N} total)` | `*.tmdl` |
| STEP 11 — star schema fix | `fix: resolve star schema issues` | `*.tmdl` |
| STEP 12 — calendario | `feat: add Calendar table` | `*.tmdl` |
| STEP 13 — dimensioni calcolate | `feat: add computed dimensions ({lista})` | `*.tmdl` |
| STEP 14 — misure | `feat: add Calcs table and measures ({N} total)` | `*.tmdl` |
| STEP 16 — documentazione (opzionale) | `docs: add technical-functional documentation` | `docs/{NomeProgetto}.md` |

I commit degli STEP 11, 13, 16 vanno eseguiti **solo se ci sono state modifiche effettive**.
Il push avviene UNA SOLA VOLTA nello STEP G-PUSH-PR invocato da STEP 17 di SKILL.md.

---

---

## Convenzioni audit — flusso `audit-existing-model.md`

Queste convenzioni si applicano quando G1 e G-PUSH-PR vengono invocati dal flusso audit
(STEP A4c e A6b). Tutto il resto del flusso (auth, init, .gitignore, push) è identico.

### Parametri G1.5 e G-PUSH-PR per il flusso audit

```
{BranchName} = audit/refactor-{DatasetName}-{YYYY-MM-DD}
               (DatasetName: lowercase, spazi e caratteri speciali → trattini)
               Esempio: audit/refactor-manufacturing-prod-2026-04-23

{PRTitle}    = audit: {N} BPA fixes on {DatasetName}

{PRBody}     = (vedi template sotto)
```

**Template {PRBody} audit:**
```markdown
## Audit Refactor — {DatasetName}

| | AS-IS | TO-BE |
|--|-------|-------|
| 🔴 Error | {E} | {E'} |
| 🟡 Warning | {W} | {W'} |
| 🔵 Info | {I} | {I'} |

### Azioni applicate ({N})

{lista azioni in formato `- fix/refactor/style/chore: descrizione (BPA-XXX)`}

### Azioni manuali pendenti ({M})

{lista azioni che richiedono intervento utente fuori MCP, se presenti}

🤖 Generato con Claude Code + pbi-semantic-model-advanced skill (audit mode)
```

### Tabella milestone commit audit

Un commit per milestone, non uno solo alla fine. Saltare il commit se nessuna azione del milestone è stata applicata.

| Milestone | Azioni BPA | CommitMessage | FilesPattern |
|-----------|-----------|---------------|--------------|
| A4c — baseline AS-IS | — | `audit: baseline AS-IS {DatasetName} — {E} errors, {W} warnings, {I} info` | `.` |
| M1 — Critical fixes | BPA-P-003, BPA-M-001 | `fix: resolve critical BPA errors on {DatasetName}` | `*.tmdl` |
| M2 — Relationships | BPA-P-001, BPA-M-003 | `fix: relationships — {N} bidirectional converted, {N} inactive removed` | `relationships.tmdl` |
| M3 — DAX quality | BPA-D-001 | `refactor: apply DIVIDE() to {N} measures` | `*.tmdl` |
| M4 — Measures org. | BPA-N-001, BPA-X-003, BPA-X-004 | `refactor: measures organization — Calcs table, display folders, format strings` | `*.tmdl` |
| M5 — Naming & visibility | BPA-P-008, BPA-N-005 | `style: naming and visibility — hide {N} key columns, rename special chars` | `*.tmdl` |

**Formato commit message milestone con body (opzionale, per M1-M5):**

```
fix: resolve critical BPA errors on {DatasetName}

- fix: disable Auto Date/Time (BPA-P-003)
- fix: mark Date table as Date Table (BPA-M-001)
```

Includere solo le righe corrispondenti alle azioni effettivamente applicate nel milestone.

### PR body audit

```markdown
## Audit Refactor — {DatasetName}

| | AS-IS | TO-BE |
|--|-------|-------|
| 🔴 Error | {E} | {E'} |
| 🟡 Warning | {W} | {W'} |
| 🔵 Info | {I} | {I'} |

### Azioni applicate ({N})

{lista azioni in formato `- fix/refactor/style/chore: descrizione (BPA-XXX)`}

### Azioni manuali pendenti ({M})

{lista azioni che richiedono intervento utente fuori MCP, se presenti}

🤖 Generato con Claude Code + pbi-semantic-model-advanced skill (audit mode)
```

---

## Note operative

- Usa sempre `git add` con path espliciti o pattern — mai `-A` globale
- Non usare `--no-verify` salvo esplicita richiesta dell'utente
- Se un commit fallisce per hook, segnala l'errore e chiedi istruzioni
- I messaggi commit seguono Conventional Commits (feat/fix/docs/chore)
