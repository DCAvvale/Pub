---
name: pbi-crea-semantic-model
description: Crea, audita e documenta semantic model Power BI (.pbip). Due flussi distinti. CREAZIONE - attivare quando l'utente dice "genera semantic model", "crea modello", "nuovo pbip", "crea pbip" o simili guida l'utente passo per passo, genera i file TMDL corretti, li importa via MCP in Power BI Desktop e valida il modello. AUDIT - attivare quando l'utente dice "audit modello", "analizza modello esistente", "documenta pbip", "revisione modello", "best practice check", "controlla il mio modello" o simili connette a un modello esistente, produce un report AS-IS in Markdown e propone azioni correttive. Usare SEMPRE i template in templates senza modificare schemi o versioni.
---

# Skill — Power BI Semantic Model (Crea + Audit)

## REGOLE FONDAMENTALI
1. Completa TUTTI gli step in ordine prima di generare file
2. Copia i template ESATTAMENTE — non modificare $schema o version
3. I file .tmdl usano TAB per indentare, MAI spazi
4. Genera sempre 2 UUID v4 casuali per i file .platform
5. Chiedi conferma esplicita prima di ogni azione irreversibile
6. Per i dettagli dei connettori leggi references/connectors.md
7. Per la modalità Direct Lake leggi references/directlake.md
8. Per l'audit di un modello esistente delega interamente a references/audit-existing-model.md — NON eseguire gli STEP 1-15 di creazione
9. Per la git integration leggi references/git-integration.md — il flag {GitEnabled} determina se i commit vengono eseguiti
10. **Lazy loading reference:** leggi ogni reference FILE SOLO allo step che la usa — non caricarle in anticipo. Ordine creazione: preflight.md → STEP 0, connectors.md → STEP 2, git-integration.md → STEP 6b, calendar.md → STEP 12, measures.md → STEP 14, documentation.md → STEP 16. Ordine audit: audit-existing-model.md → routing audit, model-scanner.md → STEP A2, best-practices.md → STEP A3, audit-report.md → STEP A4, refactor-actions.md → STEP A5–A6.

    ⚠️ **Lazy ≠ skip.** Quando arrivi allo step di una reference, leggila INTEGRALMENTE prima di produrre qualsiasi output o file. Vale soprattutto per i **template di rendering/output** (`audit-report.md`, `documentation.md`): definiscono struttura obbligatoria, sezioni con diagrammi mermaid, domande da porre all'utente (es. flag redaction PII, scope), convenzioni di troncamento. NON improvvisare la struttura "perché si conosce il dominio" — produrre report sotto-standard è un errore grave perché l'utente finale potrebbe non accorgersi delle mancanze. Se il context è già denso, leggere comunque: il costo di 200-500 righe extra è trascurabile rispetto a un deliverable da rifare.
11. **Preflight obbligatorio:** prima di qualsiasi altra azione (welcome, routing, domande), esegui STEP 0 leggendo `references/preflight.md`. Salta solo se nel contesto è già presente la riga `✓ Preflight: ...` di questa conversazione.

12. **Mai decidere autonomamente per opt-in dell'utente.** Quando una reference o uno step prescrive di **chiedere** all'utente, porre la domanda **verbatim** e attendere risposta esplicita. Esempi (non esaustivi):
    - Modalità scan completo/rapido → STEP A2 (audit)
    - Redaction PII → STEP A4 (audit)
    - Focus su categoria specifica → STEP A4 (audit)
    - Conferma backup prima di refactor → STEP A5 (audit)
    - Quali azioni eseguire ("tutte" / "1,3,5" / "safe" / ...) → STEP A5 (audit)
    - Generazione documentazione tecnico-funzionale → STEP 16 (creazione)
    - Scelta provider git e nome repo → STEP G1.2 / G1.3
    - Modalità storage (Import / Direct Lake) → STEP 1b (creazione)
    - Unifica fact via Table.Combine → STEP 4 (creazione)
    - Sorgenti aggiuntive da altri connettori → STEP 5b (creazione)

    **Vietato:**
    - Decidere "rapido" / "no PII" / "tutte le azioni" perché il context sembra denso
    - Saltare la domanda perché "tanto la risposta è ovvia"
    - Procedere senza il path di output perché "lo capisco dal trigger iniziale"
    - Assumere default impliciti senza dirlo

    Anche se la domanda sembra ridondante, è un opt-in **dell'utente**. Decidere al posto suo è un errore grave perché l'utente potrebbe accettare l'output senza accorgersi che una scelta è stata fatta sopra la sua testa, e perché le scelte hanno effetti concreti sulla detection BPA, sulla privacy del report, sull'esposizione di dati sensibili nella conversazione.

---

## VARIABILI DI SESSIONE

Queste variabili devono sopravvivere a ogni `/compact`. Dopo il compact, includile nel primo messaggio di ripresa se non sono già visibili nel contesto.

| Variabile | Settata in | Note |
|---|---|---|
| {NomeProgetto} | STEP 1 | |
| {ModalitaStorage} | STEP 1b | |
| {TipoConnettore} + parametri connettore | STEP 2–3 | URL, server, ID, ecc. |
| Tabelle Fact / Dimension (lista nomi) | STEP 4–5 | |
| {CartellaProgetto} | STEP 6 | |
| {GitEnabled} | STEP 6b | |
| {GitProvider}, {GitRemoteURL}, {GitRepoPath} | STEP 6b | Solo se GitEnabled=true |

---

## STEP 0 — Preflight prerequisiti di sistema

**Eseguire SEMPRE come prima azione della skill, prima del routing.**

Leggi `references/preflight.md` e applica la sequenza di controlli descritta:
- Check 1: MCP `powerbi-mcp-server` raggiungibile (bloccante)
- Check 2: Power BI Desktop installato (warning, l'utente può proseguire)

Mostra l'output formattato definito nel reference. Se il Check 1 fallisce, **interrompi
la skill** e non procedere al routing.

Se nel contesto è già presente la riga `✓ Preflight: ...` di questa conversazione, salta
questo step (preflight già eseguito).

---

## ROUTING INIZIALE

In base al trigger usato dall'utente, seleziona il flusso corretto prima di procedere.

### Flusso CREAZIONE (modello nuovo da zero)

**Trigger:** "genera semantic model", "crea modello", "nuovo pbip", "crea pbip", "crea semantic model", "nuovo modello"

→ Prosegui con STEP 1 di questo file.

### Flusso AUDIT (modello esistente)

**Trigger:** "audit modello", "analizza modello esistente", "documenta pbip", "revisione modello", "best practice check", "controlla il mio modello", "auditare modello"

→ **Non seguire gli STEP 1-15.** Leggi integralmente `references/audit-existing-model.md` e segui il flusso A1-A7 descritto lì. Le reference coinvolte sono:
- `references/audit-existing-model.md` (orchestratore)
- `references/model-scanner.md` (raccolta metadata MCP)
- `references/best-practices.md` (catalogo regole BPA)
- `references/audit-report.md` (template report AS-IS)
- `references/refactor-actions.md` (azioni correttive)

### Trigger ambiguo

Se il trigger è ambiguo (es. solo "aiutami con il mio modello" senza precisare se crearne uno nuovo o analizzare quello esistente), chiedi esplicitamente all'utente:

```
Vuoi:
  [1] Creare un nuovo semantic model da zero
  [2] Analizzare un modello esistente (audit + report + azioni correttive)
```

---

## STEP 1 — Nome progetto
Chiedi: "Come si chiama il progetto?"
Salva come {NomeProgetto}.

---

## STEP 1b — Modalità storage
Chiedi:

```
Quale modalità di storage vuoi usare?
1. Import       (dati caricati nel modello — flusso standard)
2. Direct Lake  (lettura diretta da OneLake / Lakehouse / Warehouse — solo Fabric)
```

Salva la scelta come {ModalitaStorage}.

Diramazione:
- **Import** → prosegui con STEP 2 di questo file (flusso standard)
- **Direct Lake** → leggi references/directlake.md e segui interamente quel flusso.
  Gli STEP 2–15 di questo file NON si applicano in modalità Direct Lake.

---

## STEP 2 — Scelta connettore
Mostra le opzioni disponibili:

```
Quale connettore vuoi usare?
1. SharePoint (file Excel o CSV)
2. Fabric Warehouse / Lakehouse (endpoint)
3. SQL Server (on-premise)
4. Dataflow Fabric / Power BI
5. Altro (descrivi)
```

Salva la scelta come {TipoConnettore}.

**Regola di risoluzione connettore:**
- Se l'utente sceglie 1–4 → usa il template corrispondente in references/connectors.md
- Se l'utente sceglie 5 o inserisce qualsiasi testo non corrispondente alle opzioni 1–4
  (es. "live connection", "Snowflake", "API REST") → trattalo come "Altro":
  1. Cerca prima in references/connectors.md se il connettore è già documentato
  2. Se non trovato, cerca su internet il template M Query corretto per Power BI Desktop
  3. Non interrompere il flusso: adatta i parametri e prosegui con STEP 3

**Leggi references/connectors.md SOLO ora** — e solo la sezione del connettore scelto (es. se SharePoint, leggi solo `## 1. SharePoint` + `## Template relazioni`). Non caricare le sezioni degli altri connettori.

---

## STEP 3 — Parametri connessione
In base al connettore scelto, chiedi i parametri descritti in references/connectors.md.
Salva tutti i parametri raccolti.

---

## STEP 4 — Tabelle dei fatti
Chiedi:
- "Quali sono le tabelle dei **fatti** (Fact - se presenti in questa sorgente)? Elencale con il nome esatto come appare nella sorgente."
- "Le tabelle dei fatti vanno **unificate** in un'unica tabella tramite append/union, oppure rimangono tabelle separate?"

Mostra riepilogo Fact / Unifica e aspetta conferma esplicita.

---

## STEP 5 — Tabelle dimensione
Chiedi:
- "Quali sono le tabelle **dimensione** (Dimension)? Elencale con il nome esatto come appare nella sorgente."

Mostra riepilogo Dimension e aspetta conferma esplicita.

---

## STEP 5b — Sorgenti aggiuntive (loop iterativo)

Dopo aver raccolto Fact e Dimension dalla sorgente principale, mostra:

> ⚠️ **Best practice:** È consigliabile centralizzare tutte le sorgenti dati in un unico layer
> (es. Dataflow, Lakehouse o SharePoint) prima di collegarle al semantic model.
> Connettori multipli aumentano la complessità di manutenzione e il rischio di problemi di refresh.
>
> "Hai altre tabelle da aggiungere da una sorgente diversa?"

**Se l'utente risponde Sì — ripeti in loop per ogni sorgente aggiuntiva:**

1. **Scelta connettore** — stesso menu dello STEP 2
2. **Parametri connessione** — stesso flusso dello STEP 3
3. **Tabelle da questa sorgente** — chiedi:
   - Sono tabelle Fact o Dimension?
   - Nomi esatti come appaiono nella sorgente
   - Se Fact: vanno unificate con quelle esistenti o rimangono separate?
4. Aggiorna il riepilogo cumulativo e mostralo:

```
Sorgenti configurate finora:

[1] SharePoint — https://contoso.sharepoint.com/...
    Fact:      FactOrdini, FactResi
    Dimension: DimCliente, DimProdotto

[2] Azure SQL — contoso.database.windows.net
    Fact:      FactBudget
    Dimension: DimScenario
```

5. Chiedi di nuovo: "Hai altre sorgenti da aggiungere?"
   - **Sì** → ripeti il loop
   - **No** → prosegui con STEP 6

**Se l'utente risponde No al primo giro:** prosegui direttamente con STEP 6.

---

## STEP 6 — Cartella di destinazione
Chiedi: "Incolla il path completo della cartella dove salvare il progetto:"
Non proporre mai un percorso di default. Accetta esattamente cio che l'utente incolla.
Salva come {CartellaProgetto}.

---

## STEP 6b — Git integration setup
**Leggi references/git-integration.md SOLO ora** ed esegui il flusso STEP G1 (G1.1 → G1.5).
Salva {GitEnabled}, {GitProvider}, {GitRemoteURL}.
Procedi con STEP 7 solo dopo aver completato il setup git (o dopo che l'utente ha scelto No).

---

## STEP 7 — Genera UUID e file
Genera 2 UUID v4 casuali (formato: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
Salva come {UUID_SEMANTIC} e {UUID_REPORT}.

Crea questa struttura in {CartellaProgetto}:

```
{NomeProgetto}.pbip                              <- da templates/pbip.json
{NomeProgetto}.SemanticModel/
  .platform                                      <- da templates/SemanticModel/platform.json
  definition.pbism                               <- da templates/SemanticModel/definition.pbism
  definition/
    database.tmdl                                <- da templates/SemanticModel/definition/database.tmdl
    model.tmdl                                   <- da templates/SemanticModel/definition/model.tmdl
    relationships.tmdl                           <- vuoto per ora (verra popolato da MCP)
    cultures/
      en-US.tmdl                                 <- da templates/SemanticModel/definition/cultures/en-US.tmdl
    tables/
      {NomeTabella}.tmdl                         <- uno per tabella, da references/connectors.md
{NomeProgetto}.Report/
  .platform                                      <- da templates/Report/platform.json
  definition.pbir                                <- da templates/Report/definition.pbir
```

Sostituzioni in tutti i file:
- {NomeProgetto} -> nome del progetto
- {UUID_SEMANTIC} -> UUID generato per il semantic model
- {UUID_REPORT} -> UUID generato per il report
- Parametri connettore -> da references/connectors.md

Per le tabelle dei fatti con unifica: genera un'unica tabella con query M che usa
Table.Combine (o Append) sulle sorgenti indicate.

**Git commit (STEP G-COMMIT):**
- CommitMessage: `feat: scaffold {NomeProgetto} — {N} tables, {TipoConnettore}`
- FilesPattern: `.`

**→ Checkpoint `/compact`** (esegui subito dopo il commit):
Usa `/compact` e nel messaggio successivo includi questo blocco di stato:
```
Semantic model "{NomeProgetto}" in corso — Import, {TipoConnettore}.
Completato: STEP 7 (scaffold in {CartellaProgetto}).
Tabelle: Fact=[{lista}], Dim=[{lista}].
Git: {GitEnabled} | remote: {GitRemoteURL}.
Prossimo: STEP 8 — import in Power BI Desktop.
```

---

## STEP 8 — Apertura file .pbip e primo refresh

⚠️ **L'apertura del file .pbip deve essere fatta manualmente dall'utente.**
La skill NON apre il file in automatico.

1. Avvisa l'utente:
   "Lo scaffold del progetto è pronto in {CartellaProgetto}.
   Apri tu il file:

       {CartellaProgetto}\{NomeProgetto}.pbip

   con un doppio click (si aprirà in Power BI Desktop).
   Esegui il primo refresh, poi dimmi quando sei pronto."

2. Aspetta conferma esplicita dell'utente.

3. ⚠️ **ALERT — se il refresh fallisce:**
   Prima di rilanciare, verifica:
   • Tutte le connessioni esistenti in Power BI Desktop
     (File → Opzioni e impostazioni → Impostazioni origine dati)
   • Il login a Power BI Desktop (in alto a destra,
     deve mostrare l'account aziendale corretto)
   • Le credenziali della sorgente dati siano state inserite

   Solo dopo aver controllato questi tre punti, riprova il refresh.

---

## STEP 9 — Connetti e valida tabelle via MCP

🔒 **Privacy: validazione metadata-only.** Le query in questo step NON devono
restituire righe di dati reali — usare solo conteggi / metadata.

1. Usa connection_operations ListConnections per trovare la connessione attiva
2. Valida il modello con:
   EVALUATE ROW("Test", 1)
3. Per ogni tabella valida con (metadata-only — non ritorna dati di riga):
   EVALUATE ROW("rows", COUNTROWS('{NomeTabella}'))
   - Se ritorna un numero (anche 0) -> tabella OK
   - Se ritorna errore di autenticazione -> avvisa l'utente di completare
     l'autenticazione in Power BI Desktop
   - Se ritorna altro errore -> tabella non valida, segnala
4. Mostra riepilogo validazione tabelle (solo nome tabella + conteggio righe,
   nessun valore di colonna).

⚠️ **NON usare** `EVALUATE TOPN(N, {tabella})` o `EVALUATE {tabella}` per la
validazione: restituiscono righe di dati reali (potenziali PII) che fluirebbero
nel contesto del provider AI senza necessità.

---

## STEP 10 — Analisi colonne e relazioni via MCP

1. Usa database_operations ExportTMDL per leggere il modello completo
2. Analizza automaticamente le colonne di tutte le tabelle cercando:
   - Colonne con nomi identici o simili tra Fact e Dimension
   - Colonne con suffisso ID, Key, Cod, Code, FK
   - Pattern tipici (es. CustomerID in Fact -> CustomerID in DimCustomer)
3. Proponi le relazioni rilevate in tabella:

| Da (Tabella.Colonna) | A (Tabella.Colonna) | Cardinalita |
|---|---|---|

4. Aspetta approvazione esplicita. Se l'utente modifica, aggiorna e riconferma.
5. Applica le relazioni approvate al modello via MCP aggiornando relationships.tmdl
   e re-importando con ImportFromTmdlFolder.

**Git commit (STEP G-COMMIT):**
- CommitMessage: `feat: add relationships ({N} total)`
- FilesPattern: `*.tmdl`

**→ Checkpoint `/compact`** (esegui subito dopo il commit):
Usa `/compact` e nel messaggio successivo includi questo blocco di stato:
```
Semantic model "{NomeProgetto}" in corso — Import, {TipoConnettore}.
Completato: STEP 10 ({N} relazioni create in {CartellaProgetto}).
Tabelle: Fact=[{lista}], Dim=[{lista}].
Git: {GitEnabled} | remote: {GitRemoteURL}.
Prossimo: STEP 11 — verifica Star Schema.
```

---

## STEP 11 — Verifica Star Schema via MCP

Usa ExportTMDL per analizzare la struttura del modello. Applica questi controlli in ordine:

### Controllo 1 — Snowflake detection (PRIORITARIO)
Regola: le Dimension non devono avere relazioni verso altre Dimension.
Se una Dimension punta a un'altra Dimension (es. DimProdotto -> DimCategoria):
- Segnala esplicitamente: "Ho rilevato uno snowflake: {DimA} -> {DimB}."
- Proponi la denormalizzazione: collasso delle due tabelle in un'unica dimensione piatta
- Aspetta conferma (la regola e SEMPRE preferire la denormalizzazione)
- Se confermato: applica via MCP, ri-valida con ExportTMDL
- Ripeti per ogni snowflake trovato, uno alla volta

### Controllo 2 — Many-to-many non gestiti
Se esistono relazioni molti-a-molti senza bridge table:
- Segnala il problema con le tabelle coinvolte
- Proponi la soluzione (bridge table o misura DAX con CROSSFILTER)
- Aspetta conferma, applica via MCP

### Controllo 3 — Colonne categoriche ridondanti in Fact
Se una colonna string nelle Fact ha bassa cardinalita e non e collegata a una Dimension:
- Segnala come candidata a Dimension
- Rimanda al STEP 13 per la gestione

Al termine dei controlli conferma: "Struttura Star Schema validata." oppure
elenca i problemi residui non ancora risolti.

**Git commit (STEP G-COMMIT) — solo se sono state applicate modifiche (snowflake/m2m):**
- CommitMessage: `fix: resolve star schema issues`
- FilesPattern: `*.tmdl`

---

## STEP 12 — Calendario DAX via MCP

**Leggi references/calendar.md SOLO ora** per le istruzioni complete su verifica preventiva,
template DAX della Calendar, marcatura come Date Table, colonne standard e
gestione delle relazioni via MCP.

**Git commit (STEP G-COMMIT):**
- CommitMessage: `feat: add Calendar table`
- FilesPattern: `*.tmdl`

**→ Checkpoint `/compact`** (esegui subito dopo il commit):
Usa `/compact` e nel messaggio successivo includi questo blocco di stato:
```
Semantic model "{NomeProgetto}" in corso — Import, {TipoConnettore}.
Completato: STEP 12 (Calendar aggiunta in {CartellaProgetto}).
Tabelle: Fact=[{lista}], Dim=[{lista}], Calendar.
Git: {GitEnabled} | remote: {GitRemoteURL}.
Prossimo: STEP 13 — dimensioni aggiuntive.
```

---

## STEP 13 — Dimensioni aggiuntive via MCP

1. Usa ExportTMDL per analizzare le colonne di tipo string nelle tabelle Fact
   che non sono gia collegate a nessuna Dimension
2. Per ognuna valuta: bassa cardinalita, descrive un'entita, usata per filtro/slicing
3. Propone ogni dimensione suggerita singolarmente:
   "Ho trovato la colonna [{Colonna}] in [{FactTable}]. Vuoi creare una {DimNome}?"
4. Per ogni dimensione approvata:
   - Crea la tabella calcolata DAX via MCP (DISTINCT + SELECTCOLUMNS)
   - Aggiunge la relazione con la Fact table
   - Ri-valida con ExportTMDL

**Git commit (STEP G-COMMIT) — solo se almeno una dimensione è stata creata:**
- CommitMessage: `feat: add computed dimensions ({lista nomi})`
- FilesPattern: `*.tmdl`

---

## STEP 14 — Tabella Calcs + Misure via MCP

**Leggi references/measures.md SOLO ora** per le istruzioni complete su struttura della
tabella Calcs, template DAX delle misure e modalità di applicazione via MCP.

**Git commit (STEP G-COMMIT):**
- CommitMessage: `feat: add Calcs table and measures ({N} total)`
- FilesPattern: `*.tmdl`

**→ Checkpoint `/compact`** (esegui subito dopo il commit):
Usa `/compact` e nel messaggio successivo includi questo blocco di stato:
```
Semantic model "{NomeProgetto}" in corso — Import, {TipoConnettore}.
Completato: STEP 14 (Calcs + {N} misure in {CartellaProgetto}).
Tabelle: Fact=[{lista}], Dim=[{lista}], Calendar, Calcs.
Git: {GitEnabled} | remote: {GitRemoteURL}.
Prossimo: STEP 15 — riepilogo finale.
```

---

## STEP 15 — Riepilogo finale

Usa ExportTMDL per generare il riepilogo finale. Mostra:

Modello completato: {NomeProgetto}

Tabelle ({N} totali)
  Fact:        {lista}
  Dimension:   {lista}
  Calendario:  Calendar (Date Table)
  Placeholder: Calcs

Relazioni ({N} totali)
  {lista relazioni con cardinalita}

Misure ({N} totali) — tabella Calcs
  Base Measures:   {lista}
  To Date:         {lista}
  Previous Period: {lista}

Calendario
  Range: {MinYear}/01/01 -> {MaxYear}/12/31 (dinamico, si aggiorna al refresh)
  Marcata come Date Table: si
  Colonne: Anno, Mese, NomeMese, Trimestre, AnnoMese, GiornoSettimana, NomeGiorno, IsWeekend

Struttura: Star Schema validato

**→ Prossimo:** STEP 16 — generazione documentazione tecnico-funzionale (opzionale).

---

## STEP 16 — Documentazione tecnico-funzionale (opzionale)

Chiedi all'utente:

```
Vuoi generare la documentazione tecnico-funzionale del modello?
La documentazione include: overview, diagramma star schema (mermaid),
schema tabelle, catalogo misure con descrizioni in linguaggio naturale,
KPI catalog per domande business, dipendenze refresh.
File output: {CartellaProgetto}/docs/{NomeProgetto}.md

[S] Sì — genera la documentazione (richiede ~30 secondi)
[N] No  — salta e procedi al push finale
```

**Se l'utente sceglie No:** prosegui direttamente con STEP 17. Nessun commit
relativo alla doc verrà aggiunto.

**Se l'utente sceglie Sì:**

**Leggi references/documentation.md SOLO ora** ed esegui il flusso STEP D1 → D4
per generare il file `{CartellaProgetto}/docs/{NomeProgetto}.md`.

**Git commit (STEP G-COMMIT) — solo se {GitEnabled} = true e doc generata:**
- CommitMessage: `docs: add technical-functional documentation`
- FilesPattern: `docs/{NomeProgetto}.md`

⚠️ **NON eseguire il push qui** — il push è centralizzato nello STEP 17.

Conferma intermedia:
```
✅ Documentazione: {CartellaProgetto}/docs/{NomeProgetto}.md
✅ Commit creato sulla feature branch (push posticipato a STEP 17)
```

---

## STEP 17 — Push + Pull Request

**Git push + PR (STEP G-PUSH-PR):**
Leggi references/git-integration.md e segui il flusso STEP G-PUSH-PR per
eseguire il push della feature branch e creare la Pull Request verso main.

Il push include tutti i commit della feature branch — compreso quello della
documentazione se generato in STEP 16. La PR sarà quindi creata già completa
di doc al primo invio (nessun aggiornamento successivo necessario).

Se `{GitEnabled} = false`: salta interamente questo step.
