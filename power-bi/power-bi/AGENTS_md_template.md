# pbi-semantic-model-advanced — Skill per Claude Code

> **Versione:** 2.0
> **Aggiornato:** 2026-04-29
> **Requisiti:** Claude Code · powerbi-mcp-server · Power BI Desktop
> **Opzionali:** git · GitHub CLI (`gh`) · Azure CLI (`az`) + estensione `azure-devops`

---

## Cos'è questa skill

Skill per **Claude Code** che gestisce due flussi distinti su Semantic Model Power BI (`.pbip`):

- **CREAZIONE** — guida la creazione di un nuovo modello da zero, in modo interattivo e controllato. Claude raccoglie le informazioni step-by-step, genera i file TMDL, l'utente apre il `.pbip` in Power BI Desktop, Claude valida e arricchisce il modello via MCP (relazioni, star schema, calendario, misure) e opzionalmente esegue commit/PR su GitHub o Azure DevOps.
- **AUDIT** — connette a un modello esistente, raccoglie metadata via MCP, applica un catalogo di best-practice (BPA), genera un report Markdown AS-IS e propone azioni correttive.

Nessuna azione irreversibile senza conferma esplicita.

### Cosa fa in concreto

**Comuni a entrambi i flussi:**

- **Preflight** — verifica MCP, Power BI Desktop, git, gh, az all'avvio (5 check stratificati: bloccanti / warning / informativi)
- **Privacy disclaimer** — opt-in esplicito prima di processare metadati del modello
- **Git integration** — commit per milestone + Pull Request finale su GitHub o Azure DevOps (opzionale)
- **Compact checkpoint** — la skill suggerisce `/compact` ai punti densi del flusso e mantiene le variabili di sessione

**CREAZIONE:**

- Modalità storage **Import** + **Direct Lake** (Fabric Lakehouse / Warehouse)
- Connettori: **SharePoint** (Excel/CSV) · **Fabric Warehouse / Lakehouse** (endpoint) · **SQL Server** (on-premise) · **Dataflow Fabric / Power BI** · **Altro** (cercato in connectors.md o on-line)
- Tabelle Fact con unifica (append/union) opzionale
- Sorgenti multiple (loop iterativo per multi-connector)
- Validazione tabelle via MCP **metadata-only** (`COUNTROWS` — nessun dato di riga restituito al provider AI)
- Relazioni proposte automaticamente analizzando colonne (suffisso ID/Key/Cod/FK)
- Star Schema validato — snowflake denormalizzato, m2m gestito con bridge / `CROSSFILTER`
- Calendar DAX con range anno intero dinamico, marcata come Date Table
- Dimensioni calcolate da colonne categoriche orfane nelle Fact
- Tabella `Calcs` con misure organizzate in cartelle: `Base Measures` · `To Date` · `Previous Period`
- **Documentazione tecnico-funzionale** opzionale (mermaid star schema, KPI catalog, dipendenze refresh)

**AUDIT:**

- Scan completo del modello via MCP (tabelle, colonne, misure, relazioni, M Query, espressioni DAX)
- Report MD strutturato in 9 sezioni (Executive Summary, Inventario, PQ vs DAX, Relazioni, Misure, Organizzazione, Star Schema, Violazioni BPA, Azioni)
- Diagrammi Mermaid: Data Lineage + ER Diagram
- **Redaction PII opzionale** — sostituzione automatica nomi colonne/misure che matchano pattern (CF, IBAN, Email, Phone, Stipendio, Indirizzo, DOB, SSN, Carta credito, P. IVA, ecc.) con `[REDACTED-{tipo}]`
- Refactor automatico delle violazioni BPA confermate dall'utente, raggruppate in 5 milestone (Critical / Relationships / DAX quality / Measures org / Naming & visibility)

---

## Flusso CREAZIONE

| # | Step | Cosa succede |
|---|---|---|
| 0 | **Preflight** | Verifica MCP, PBI Desktop, git, gh, az — disclaimer privacy con opt-in |
| 1 | **Nome progetto** | Diventa il nome della cartella `.pbip` |
| 1b | **Modalità storage** | Import (standard) o Direct Lake (Fabric — flusso separato in `directlake.md`) |
| 2 | **Connettore** | SharePoint · Fabric WH/LH · SQL Server · Dataflow · Altro |
| 3 | **Parametri connessione** | URL, server, DB, ID workspace, ecc. |
| 4 | **Tabelle Fact** | Lista + opzione unifica (append/union) |
| 5 | **Tabelle Dimension** | Lista |
| 5b | **Sorgenti aggiuntive** | Loop iterativo per multi-sorgente con riepilogo cumulativo |
| 6 | **Cartella destinazione** | Path completo, nessun default proposto |
| 6b | **Git integration** | Provider (GitHub / Azure DevOps / locale), repo, branch — warning push esterno |
| 7 | **Generazione file** | Genera 2 UUID v4, scaffold completo `.pbip` su disco — primo commit |
| 8 | **Apertura `.pbip`** | **L'utente apre il file manualmente** in PBI Desktop + alert su refresh fallito |
| 9 | **Validazione tabelle** | `COUNTROWS` su ogni tabella — solo conteggi, nessun dato di riga |
| 10 | **Relazioni** | Analizza struttura via `ExportTMDL`, propone, applica — commit |
| 11 | **Star Schema** | Snowflake → denormalizzazione · m2m → bridge / `CROSSFILTER` |
| 12 | **Calendar DAX** | Tabella Calendar dinamica, marcata DateTable, collegata alle Fact — commit |
| 13 | **Dim aggiuntive** | Una per volta da colonne categoriche orfane — commit se applicate |
| 14 | **Calcs + Misure** | Tabella `Calcs` + misure in 3 cartelle — commit |
| 15 | **Riepilogo finale** | Vista completa: tabelle, relazioni, calendario, misure |
| 16 | **Documentazione** *(opzionale)* | `docs/{NomeProgetto}.md` — overview, mermaid, KPI catalog, dipendenze refresh |
| 17 | **Push + PR** | Push branch + Pull Request automatica (solo se `GitEnabled`) |

---

## Flusso AUDIT

| # | Step | Cosa succede |
|---|---|---|
| 0 | **Preflight** | Stesso del flusso creazione |
| A1 | **Connessione** | Lista istanze locali via `ListLocalInstances`, scelta del modello |
| A2 | **Scan modello** | Scan completo via MCP (delegato a `model-scanner.md`) |
| A3 | **Valutazione BPA** | Applica catalogo regole best-practice (`best-practices.md`) |
| A4 | **Report AS-IS** | Genera MD strutturato + diagrammi mermaid · opt-in **redaction PII** |
| A4b | **Verifica formato** | PBIX vs PBIP — se PBIX guida la conversione |
| A4c | **Git integration** | Setup git per il branch refactor (es. `audit/refactor-{model}-{date}`) |
| A5 | **Proposta azioni** | Utente conferma quali violazioni BPA correggere |
| A6 | **Refactor iterativo** | Applica modifiche per milestone via MCP — un commit per milestone |
| A6b | **Commit finale + push + PR** | Push branch audit + Pull Request |
| A7 | **Report TO-BE** *(opzionale)* | Riepilogo: errori risolti, azioni pendenti |

---

## Installazione

### Prerequisiti

| Componente | Obbligatorio? | Verifica |
|---|---|---|
| **Claude Code** | Sì | [docs.anthropic.com/claude-code](https://docs.anthropic.com/en/docs/claude-code/getting-started) |
| **powerbi-mcp-server** | Sì | `claude mcp list` deve mostrare il server connesso |
| **Power BI Desktop** | Sì | Installato localmente (Microsoft Store o standalone) |
| **git** | Opzionale | Solo se vuoi git integration |
| **GitHub CLI (`gh`)** | Opzionale | Solo se provider = GitHub |
| **Azure CLI (`az`)** + ext. `azure-devops` | Opzionale | Solo se provider = Azure DevOps |

> Il preflight allo STEP 0 verifica automaticamente tutti questi componenti e segnala cosa manca prima di iniziare.

---

### Struttura della skill

```
pbi-semantic-model-advanced/
  SKILL.md                              ← orchestratore principale
  references/
    preflight.md                        ← STEP 0 — verifica prerequisiti + privacy disclaimer
    connectors.md                       ← template M per ogni connettore
    directlake.md                       ← flusso Direct Lake (Fabric)
    calendar.md                         ← template Calendar DAX
    measures.md                         ← struttura tabella Calcs e misure
    git-integration.md                  ← setup git, commit, push, PR
    documentation.md                    ← generazione doc tecnico-funzionale
    audit-existing-model.md             ← orchestratore flusso audit (A1-A7)
    model-scanner.md                    ← scan MCP del modello esistente
    best-practices.md                   ← catalogo regole BPA
    audit-report.md                     ← template report AS-IS + redaction PII
    refactor-actions.md                 ← azioni correttive BPA
  templates/
    pbip.json
    gitignore.txt
    SemanticModel/
      platform.json
      definition.pbism
      definition/
        database.tmdl
        model.tmdl
        relationships.tmdl
        table_csv.tmdl
        table_excel.tmdl
        cultures/
          en-US.tmdl
    Report/
      platform.json
      definition.pbir
    Live Mode/                          ← template per Live Connection
```

---

### Dove installare

Due modalità:

**Personale** — disponibile su tutti i progetti:
```
~/.claude/skills/pbi-semantic-model-advanced/
```

**Di progetto** — solo per uno specifico progetto:
```
<Tuo-Progetto>/.claude/skills/pbi-semantic-model-advanced/
```

Se la cartella `.claude/skills/` non esiste, creala.

---

### Come attivare

Apri Claude Code e scrivi una di queste frasi.

**Per CREAZIONE:**
```
genera semantic model
crea modello
crea pbip
crea semantic model
nuovo pbip
nuovo modello
```

**Per AUDIT:**
```
audit modello
analizza modello esistente
documenta pbip
revisione modello
best practice check
controlla il mio modello
auditare modello
```

Claude eseguirà il preflight, mostrerà il disclaimer privacy e procederà col flusso scelto.

---

## Sicurezza e privacy

La skill applica controlli espliciti per ridurre l'esposizione di dati al provider AI:

- **Validazione metadata-only** — nessuna query restituisce righe di dati reali nel contesto (solo `COUNTROWS`, schema, `INFO.*`)
- **Disclaimer privacy** allo STEP 0 con opt-in `[S/N]` prima di processare metadati
- **Warning push esterno** prima di creare repo GitHub — checklist compliance da confermare esplicitamente
- **Redaction PII opzionale** nel report audit — pattern per CF, IBAN, Email, Phone, Stipendio, Indirizzo, DOB, SSN, CC, P. IVA
- **Credenziali sorgenti dati** mai nei file TMDL (gestite localmente da PBI Desktop Credential Manager)

> ⚠️ Le query M (server names, URL SharePoint, schemi DB) e le espressioni DAX **fluiscono nel contesto del provider AI** durante l'esecuzione della skill. Verifica con il tuo data steward la classificazione dei modelli prima di usare la skill su contenuti sensibili.

---

## Note importanti

- **Apertura `.pbip` manuale** — allo STEP 8 sei tu ad aprire il file in PBI Desktop (la skill NON apre automaticamente)
- **Refresh fallito** — verifica connessioni esistenti, login PBI Desktop e credenziali sorgente prima di rilanciare
- **Snowflake non supportato** — il flusso star-schema propone sempre la denormalizzazione
- **Calendar marcata come DateTable** — necessario per Time Intelligence DAX
- **Misure Time Intelligence** (`To Date`, `Previous Period`) create come placeholder, da personalizzare
- **Git commit per milestone** — niente push automatico fino allo STEP 17 (push + PR insieme)
- **Direct Lake** — gli STEP 2-15 standard non si applicano, segui interamente `references/directlake.md`
- **Redaction PII è euristica** — basata sui nomi colonne, NON sostituisce review del data steward

---

## Documentazione di riferimento

Ogni file `references/<nome>.md` è auto-contenuto e descrive in dettaglio il proprio step. La SKILL.md applica **lazy loading**: legge ogni reference solo nel momento in cui serve, mantenendo basso il consumo di context window.
