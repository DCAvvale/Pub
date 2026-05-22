# Audit Existing Model — Orchestratore

Reference che guida Claude attraverso l'audit completo di un modello Power BI semantic esistente, dalla connessione al modello fino alla generazione del report AS-IS e all'esecuzione delle azioni correttive.

## Attivazione

Questa reference viene richiamata dalla skill principale `pbi-crea-semantic-model` (SKILL.md) quando l'utente chiede di analizzare/auditare un modello esistente.

**Trigger suggeriti:**
- "audit modello"
- "analizza modello esistente"
- "documenta pbip"
- "revisione modello"
- "controlla il mio modello"
- "best practice check"

## Reference richiamate

Questo orchestratore delega logica specifica a:

| Reference | Quando | Cosa produce |
|-----------|--------|--------------|
| `model-scanner.md` | STEP A1-A2 | Metadata strutturato del modello |
| `best-practices.md` | STEP A3 | Elenco violazioni per regola |
| `audit-report.md` | STEP A4 | File MD scaricabile con report AS-IS |
| `refactor-actions.md` | STEP A5-A6 | Esecuzione modifiche approvate |

## Prerequisiti

Verificare con l'utente prima di iniziare:

1. Power BI Desktop aperto con il `.pbip` target caricato.
2. Refresh eseguito almeno una volta (altrimenti metadata incompleto).
3. MCP server `powerbi-mcp-server` attivo.

Se uno di questi manca, istruire l'utente e attendere conferma prima di procedere.

---

## Gestione Context Window

> **⚠️ REGOLA OBBLIGATORIA — applicare in tutta la sessione di audit**

La context window di Claude ha un limite (~200K token). Un audit su modello grande (50+ tabelle) consuma facilmente 60–80% della context window solo nella fase di scan. Senza gestione attiva, il rischio è di saturare il contesto prima di produrre il report.

### Regole vincolanti

1. **Mai `maxReturnCharacters = -1` senza `filePath`** — qualsiasi chiamata `ExportTMDL` deve avere un limite esplicito o salvare su file. Dettaglio in `model-scanner.md`.

2. **Batch per tabella** — le chiamate `table_operations ExportTMDL` vanno eseguite al massimo 5 alla volta con `maxReturnCharacters ≤ 15000` ciascuna. Non caricare mai l'intero TMDL in una singola risposta.

3. **Checkpoint `/compact` obbligatori** — dopo STEP A2 e dopo STEP A4, comunicare all'utente di eseguire `/compact` prima di procedere. `/compact` comprime la cronologia della conversazione riducendo il token count mantenendo il contesto semantico.

4. **Agent subagent per modelli molto grandi (> 80 tabelle)** — se il modello supera 80 tabelle visibili, proporre all'utente di delegare la fase di scan (FASE 2–3 di `model-scanner.md`) a un Agent subagent con contesto isolato. Il subagent restituisce solo la struttura YAML ridotta, non il TMDL grezzo.

### Checkpoint `/compact` — formato comunicazione all'utente

Quando si raggiunge un checkpoint, mostrare:

```
⏸️ Checkpoint context window — prima di procedere, digita /compact in chat
   per comprimere la cronologia. Questo riduce il consumo di token e previene
   errori nelle fasi successive. Quando hai fatto, dimmi "continua".
```

Attendere la conferma dell'utente prima di procedere allo step successivo.

---

## STEP A1 — Connessione

Delega: `model-scanner.md` → **FASE 1**.

1. `ListLocalInstances` per scoprire istanze aperte.
2. Se più istanze: chiedere all'utente quale analizzare.
3. `Connect` con connection string standard.
4. In caso di `No databases found`: istruire l'utente ad aprire `.pbip` e fare Refresh.

Al termine, mostrare all'utente un conferma sintetica:

```
✅ Connesso a: {DatabaseName} (porta {port})
```

---

## STEP A2 — Scan completo del modello

Delega: `model-scanner.md` → **FASE 2, 3, 4**.

> 🛑 **REGOLA OBBLIGATORIA — domanda da porre all'utente, non decidere autonomamente**
>
> Per modelli grandi (> 30 tabelle **OPPURE** > 10M righe sulla fact principale) la
> scelta della modalità di scan è **opt-in dell'utente**: porre la domanda sotto e
> attendere risposta esplicita PRIMA di procedere con FASE 3 di model-scanner.md.
>
> **Vietato decidere autonomamente "faccio rapido"** anche se sembra che il context sia
> già denso, o se l'export TMDL è grande, o se si vuole risparmiare tempo. La modalità
> rapida salta DUE fasi DAX (3.4 cardinalità colonne stringa, 3.5 detection DateTime
> ora-vuota) che impattano la detection di **BPA-M-005** (colonne candidate a Dim) e
> **BPA-P-009** (alta cardinalità) e **BPA-P-007** (DateTime semanticamente Date).
> Saltare la domanda → l'utente riceve un report con detection ridotta senza saperlo.

Domanda da porre all'utente (testo da usare verbatim, sostituendo `{N}`):

```
Il modello ha {N} tabelle. Modalità scan:
  [1] Completo (include cardinalità colonne stringa — più lento, più accurato)
  [2] Rapido (skip cardinalità colonne fact — 30-50% più veloce, detection BPA-M-005 e BPA-P-009 limitata)
```

Durante lo scan, mostrare progress ogni 5 tabelle scansionate:

```
⏳ Scanning... {N}/{tot} tabelle completate
```

Al termine, riepilogo sintetico:

```
✅ Scan completato in {sec}s
  - Tabelle: {N} (errori: {err})
  - Misure: {N}
  - Relazioni: {N}
  - TMDL esportato in: {path}
```

> **⏸️ CHECKPOINT CONTEXT WINDOW** — lo scan ha caricato un volume significativo di metadata in contesto.
> Comunicare all'utente:
> ```
> ⏸️ Scan completato. Prima di procedere con la valutazione BPA, digita /compact
>    per comprimere la cronologia. Quando hai fatto, dimmi "continua".
> ```
> Attendere conferma prima di procedere con STEP A3.

---

## STEP A3 — Valutazione best practice

Iterare su ogni regola di `best-practices.md` e valutarla contro il metadata raccolto da A2.

Raccogliere le violazioni in una lista:

```yaml
violations:
  - ruleId: "BPA-P-001"
    severity: "Warning"
    object: {type: "relationship", path: "Customer ↔ Region"}
    message: "Relazione bidirezionale rilevata"
    fix: "Convertire a singleDirection"
    autoFix: "requires_approval"
```

Aggregare conteggi per severità e categoria per la sezione Executive Summary del report.

**Nessun output utente in questo step** — è preparatorio al report.

---

## STEP A4 — Generazione report AS-IS

Delega: `audit-report.md`.

> 🛑 **REGOLA OBBLIGATORIA — leggere PRIMA di scrivere qualsiasi cosa**
>
> **Leggere `references/audit-report.md` integralmente** prima di produrre il file
> di output. Il template definisce:
> - 9 sezioni fisse e il loro ordine
> - Diagrammi **mermaid** obbligatori (flowchart `Data Lineage`, `erDiagram` relazioni)
> - Sottosezioni dettagliate (es. una entry per ogni calculated column con raccomandazione)
> - La domanda **Redaction PII** che va posta all'utente (passo 1b sotto)
> - Convenzioni di troncamento, emoji semaforo, formato numerico
>
> **Vietato improvvisare la struttura** anche se il dominio è familiare. Saltare il template
> produce un report sotto-standard, non confrontabile con AS-IS/TO-BE futuri, e l'utente
> finale potrebbe accettarlo senza accorgersi delle mancanze. Questo è un errore grave.

1. Chiedere all'utente dove salvare il report:

```
📁 Dove vuoi salvare il report di audit?
   (incolla il path completo della cartella)
```

Salvare come `{CartellaOutput}`. Il file verrà scritto in:
`{CartellaOutput}\audit_AS-IS_{DatasetName}_{YYYY-MM-DD}.md`

1b. **Opt-in redaction PII** — chiedere all'utente:

```
🔒 Redaction PII nel report?
   Il report include nomi di colonne e misure del modello. Se contengono
   identificatori sensibili (CodiceFiscale, IBAN, Email, Stipendio, ecc.)
   posso sostituirli automaticamente con [REDACTED-{tipo}].

   La detection è euristica (basata su pattern nei nomi) — utile come
   primo livello di protezione, NON sostituisce una review del data steward.

   [S] Sì — applica redaction PII (consigliato se condividi il report
        fuori dal team o lo committi su repo esterna)
   [N] No — mostra tutti i nomi (default)
```

Salvare come `{RedactPII}` = true / false. Sopravvive al `/compact`. Passare
il valore al template `audit-report.md` per attivare le sostituzioni descritte
nella sezione "Modalità Redaction PII (opzionale)".

2. Applicare il template producendo il file nel percorso scelto.
2. Chiamare `present_files` sul file generato.
3. Mostrare all'utente un riepilogo testuale (Executive Summary in chat) e proporre il prossimo step:

```
📄 Report AS-IS generato: audit_AS-IS_{DatasetName}_{date}.md

Riepilogo rapido:
  - {N} tabelle, {M} misure, {R} relazioni
  - {E} 🔴 Error, {W} 🟡 Warning, {I} 🔵 Info

Prossimi passi:
  [1] Procedi con le azioni correttive (ti propongo la lista prioritizzata)
  [2] Salvo e basta, mi rivedo il report con calma
  [3] Focus su una categoria specifica (Performance | DAX | Modeling | Maintenance | Naming)
```

> **⏸️ CHECKPOINT CONTEXT WINDOW** — il report è stato generato, il contesto è denso.
> Comunicare all'utente prima di mostrare le opzioni:
> ```
> ⏸️ Report generato. Se intendi procedere con le azioni correttive, digita /compact
>    ora per liberare spazio in contesto. Poi dimmi come vuoi procedere.
> ```

Se l'utente sceglie [2] → terminare. Se [1] o [3] → procedere con STEP A4b.

---

## STEP A4b — Verifica formato file (PBIX vs PBIP)

Rilevare automaticamente il formato dal path del modello — **senza chiedere nulla all'utente**.

**Logica di rilevamento:**

- Se il path noto contiene `.pbix` come estensione → formato **PBIX**
- Se esiste una cartella con struttura `*.SemanticModel/definition/` → formato **PBIP**
- Se il path non è noto (scan avviato da porta senza path esplicito): controllare tramite MCP se esiste una cartella `definition/` associata all'istanza corrente

**Se PBIP rilevato:** skip silenzioso, procedere con STEP A4c.

**Se PBIX rilevato:** è necessario convertire in PBIP **prima** di procedere con le azioni correttive, perché ogni gruppo di azioni produrrà un commit git separato — questo richiede che i file TMDL siano su disco dal primo momento.

> ⚠️ **VINCOLO CRITICO — MCP non può fare questa conversione autonomamente**
> `ExportToTmdlFolder` esporta solo il semantic model. Le **pagine report e i visual**
> sono nella parte `.pbix` non accessibile via MCP. L'unico modo corretto è usare
> Power BI Desktop nativamente. Non tentare la conversione via MCP.

Mostrare all'utente questa spiegazione e istruzioni passo per passo:

```
📦 Il modello è in formato .pbix.

Per tracciare ogni azione correttiva con git (un commit per gruppo di modifiche)
ho bisogno che il progetto sia in formato .pbip su disco prima di iniziare.

Il MCP server non può fare questa conversione autonomamente perché esporta
solo il semantic model — le tue pagine report andrebbero perse.
L'unico modo sicuro è usare Power BI Desktop:

  1. In Power BI Desktop: File → Salva con nome
  2. Tipo file: Power BI Project (.pbip)
  3. Cartella di destinazione: {CartellaProgetto richiesta}

Dove vuoi salvare il progetto .pbip? (incolla il path completo della cartella)
```

Attendere il path dall'utente → salvare come `{CartellaProgetto}`.

Poi attendere che l'utente confermi di aver salvato. Verificare la struttura:

```bash
ls "{CartellaProgetto}"
# atteso: {NomeProgetto}.pbip, {NomeProgetto}.SemanticModel/, {NomeProgetto}.Report/
```

Aggiornare `{CartellaProgetto}` e procedere con STEP A4c.

---

## STEP A4c — Git integration

Delegare integralmente a `git-integration.md` → **STEP G1**, passando queste variabili:

- `{CartellaProgetto}` = cartella del `.pbip` (esistente o appena creato in A4b)
- `{NomeProgetto}` = `{DatasetName}` (da `scanMetadata.datasetName`)

**Unica differenza rispetto al flusso creazione:** il nome del branch è:

```
audit/refactor-{DatasetName}-{YYYY-MM-DD}
```

(es. `audit/refactor-manufacturing-prod-2026-04-23`) invece di `feature/{NomeProgetto}`. Questo è definito nelle convenzioni audit di `git-integration.md`.

Al termine del STEP G1, eseguire il **commit baseline** dello stato AS-IS:

```bash
git add .
git commit -m "audit: baseline AS-IS {DatasetName} — {E} errors, {W} warnings, {I} info"
```

Questo fissa lo stato del modello prima di qualsiasi modifica e rende il diff delle azioni correttive leggibile nel log git.

---

## STEP A5 — Proposta azioni correttive

Delega: `refactor-actions.md`.

1. Costruire l'elenco azioni dalle violazioni raccolte in A3, filtrando per categoria se l'utente ha scelto focus specifico.
2. Prima di presentare l'elenco, ricordare **una volta sola**:

```
⚠️ Prima di procedere con modifiche strutturali, raccomando di fare
   un backup del `.pbip` (copia la cartella del progetto).
   Confermi di aver fatto un backup o di procedere senza?
```

3. Mostrare la lista azioni raggruppata per priorità (Error → Warning → Info), numerata progressivamente. Formato come Sezione 9 del report.

4. Chiedere all'utente quali azioni eseguire:

```
Quali azioni vuoi eseguire?
  - "tutte" → eseguo nell'ordine
  - "1, 3, 5" → solo quelle
  - "tutte tranne 2, 4" → tutte escluse
  - "safe" → solo auto-fix ✅ safe (nessun rischio funzionale)
  - "nessuna" → termino senza modifiche
```

---

## STEP A6 — Esecuzione iterativa

Per ogni azione approvata, seguire il flusso della categoria corrispondente in `refactor-actions.md`:

1. **Preview** dell'azione (oggetti coinvolti, diff, rischi).
2. **Conferma** se l'azione è `⚠️ requires_approval` o `❌ manuale`.
   - Le azioni `✅ safe` possono essere applicate senza ulteriore conferma se l'utente ha scelto "tutte" o "safe".
3. **Esecuzione** via MCP (comandi specifici in `refactor-actions.md`).
4. **Esito**: mostrare successo/errore e passare alla successiva.

Se un'azione fallisce:
- Loggare errore
- Chiedere all'utente se proseguire con le azioni successive o interrompere

**Azioni con fix manuale (es. snowflake refactor, calculated columns → PQ):**
Claude genera il codice / istruzioni e le presenta. L'utente applica in Power Query Editor e conferma il completamento. Claude procede solo dopo conferma.

Le azioni sono raggruppate in **milestone** — al completamento di ogni milestone eseguire un commit via `git-integration.md → G-COMMIT` (vedi tabella milestone audit in quella reference):

| Milestone | Azioni incluse | Eseguire commit se... |
|-----------|---------------|----------------------|
| M1 — Critical fixes | BPA-P-003, BPA-M-001 | almeno una applicata |
| M2 — Relationships | BPA-P-001, BPA-M-003 | almeno una applicata |
| M3 — DAX quality | BPA-D-001 | almeno una misura modificata |
| M4 — Measures org. | BPA-N-001, BPA-X-003, BPA-X-004 | almeno una applicata |
| M5 — Naming & visibility | BPA-P-008, BPA-N-005 | almeno una applicata |

Le azioni manuali (BPA-P-002, BPA-P-004, BPA-P-006, BPA-M-006) non producono commit — vengono documentate nel PR body come "pending manual actions".

Al termine del loop, riepilogo esecuzione:

```
✅ Completate: {N} azioni ({C} commit git)
⚠️ Richiedono azione manuale utente: {N}
❌ Fallite: {N}
```

---

## STEP A6b — Commit finale + push + PR

Delegare a `git-integration.md` → **STEP G-COMMIT** poi **STEP G-PUSH-PR**, passando:

**G-COMMIT:**
- `{FilesPattern}` = `"*.tmdl"` (solo file modello modificati)
- `{CommitMessage}` = messaggio strutturato (convenzione audit in `git-integration.md`):

```
audit: apply {N} corrective actions on {DatasetName}

- fix: {azione 1 in formato conventional commit}
- fix: {azione 2}
- refactor: {azione 3}
- style: {azione 4}
...
```

**G-PUSH-PR:** il template del PR body per il flusso audit è definito in `git-integration.md` (sezione "Convenzioni audit"). Include il delta violazioni AS-IS → TO-BE e la lista azioni applicate.

Se `{GitEnabled}` = false (utente ha saltato il STEP A4c): questo step è silenzioso.

---

## STEP A7 — Report TO-BE (opzionale)

Dopo l'esecuzione delle azioni, proporre:

```
Rigenero il report per confrontare AS-IS vs TO-BE?
  [sì] → rieseguo scan + report (nome file audit_TO-BE_{date}.md)
  [no] → chiudo
```

Se sì:
1. Rieseguire STEP A2, A3, A4 producendo un nuovo file con suffisso `TO-BE`.
2. Produrre in chat un **delta sintetico**:

```
Delta violazioni rispetto ad AS-IS:
  🔴 Error:   {E_as-is} → {E_to-be}  ({diff})
  🟡 Warning: {W_as-is} → {W_to-be}  ({diff})
  🔵 Info:    {I_as-is} → {I_to-be}  ({diff})
```

---

## Flowchart sintetico

```
┌──────────────────────┐
│  Trigger audit       │
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ A1: Connessione      │──► model-scanner FASE 1
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ A2: Scan metadata    │──► model-scanner FASE 2,3,4
└──────────┬───────────┘      ⏸️ /compact checkpoint
           ▼
┌──────────────────────┐
│ A3: Valutazione BPA  │──► best-practices
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ A4: Report AS-IS     │──► audit-report → file MD
└──────────┬───────────┘      ⏸️ /compact checkpoint
           ▼
        ┌──┴──┐
        │ ok? │ [no] ───► END
        └──┬──┘
           ▼ [sì]
┌──────────────────────────────┐
│ A4b: Verifica formato        │  auto-detect PBIX/PBIP
│      (conversione se PBIX)   │──► templates/ + ImportFromTmdlFolder
└──────────┬───────────────────┘
           ▼
┌──────────────────────────────┐
│ A4c: Git integration         │──► git-integration.md G1
│      (setup + commit AS-IS)  │  branch: audit/refactor-{name}-{date}
└──────────┬───────────────────┘
           ▼
┌──────────────────────┐
│ A5: Proposta azioni  │──► refactor-actions
└──────────┬───────────┘
           ▼
┌──────────────────────┐
│ A6: Loop esecuzione  │──► refactor-actions (MCP)
└──────────┬───────────┘
           ▼
┌──────────────────────────────┐
│ A6b: Commit + push + PR      │──► git-integration.md G-COMMIT + G-PUSH-PR
└──────────┬───────────────────┘
           ▼
        ┌──┴──┐
        │TO-BE│ [no] ───► END
        └──┬──┘
           ▼ [sì]
┌──────────────────────┐
│ A7: Report TO-BE     │──► audit-report
└──────────┬───────────┘
           ▼
          END
```

## Principi operativi

### Iterazione e approvazione

Rispettare il pattern iterativo del progetto: ogni modifica invasiva richiede conferma esplicita dell'utente. Azioni raggruppate come "safe" possono essere applicate in batch dopo approvazione iniziale.

### Trasparenza

Dichiarare sempre all'utente:
- Quali regole sono state valutate (contatori)
- Quali limitazioni ha la detection (es. misure inutilizzate: limite ai report)
- Quali azioni sono reversibili vs irreversibili

### Riusabilità

Tutta la logica specifica vive nelle reference delegate. Questo file resta un orchestratore puro — se serve modificare una singola regola o una singola azione, lo si fa nelle reference corrispondenti senza toccare l'orchestratore.

### Separazione creazione vs audit

Questa reference è indipendente dal flusso di creazione (STEP 1-15 di `SKILL.md`). Richiama logica condivisa (calendar STEP 12, dimensioni STEP 13) tramite rimandi, ma non duplica.

Nota TODO — refactor futuro: estrarre `calendar-creation.md` e `dim-generation.md` come reference condivise tra creazione e audit.

## Attivazione dalla skill principale

Nella SKILL.md, aggiungere una sezione di routing iniziale del tipo:

```markdown
## Routing

Se l'utente dice "genera/crea modello / nuovo pbip" → procedi con STEP 1-15 (creazione)
Se l'utente dice "audit / analizza / documenta modello esistente" → delega a `references/audit-existing-model.md`
```

L'utente si occuperà di questa modifica in un secondo momento.
