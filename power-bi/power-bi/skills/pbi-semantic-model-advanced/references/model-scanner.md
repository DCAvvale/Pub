# Model Scanner Reference

Procedura operativa per connettersi a un modello Power BI esistente e raccogliere tutto il metadata necessario alla fase di audit. Usata da `audit-existing-model.md` nello STEP A2.

## Scopo

Produrre una struttura dati completa e deterministica del modello AS-IS che sarà consumata da:
- `best-practices.md` per la valutazione delle regole BPA
- `audit-report.md` per la generazione del report
- `refactor-actions.md` per la proposta delle azioni correttive

## Prerequisiti

Prima di iniziare lo scan:

1. **Power BI Desktop deve essere aperto** con il file `.pbip` target caricato.
2. **Il modello deve essere stato refreshato almeno una volta** — senza un refresh iniziale le tabelle non hanno colonne popolate e lo scan restituirà metadata incompleto.
3. **Il MCP server `powerbi-mcp-server` deve essere attivo**.

Se l'utente segnala l'errore `No databases found` durante `Connect`, significa che Power BI Desktop è in esecuzione ma nessun modello è caricato. Istruirlo ad aprire il `.pbip` e fare Refresh prima di riprovare.

## Sequenza di scan

### FASE 1 — Discovery e connessione

**Step 1.1 — Listare istanze locali**

Chiamare `ListLocalInstances` per ottenere tutte le istanze Power BI Desktop aperte.

Possibili esiti:
- **0 istanze** → chiedere all'utente di aprire Power BI Desktop con il `.pbip` target.
- **1 istanza** → procedere con quella.
- **>1 istanze** → mostrare l'elenco con `DatabaseName` e `Port`, chiedere all'utente quale analizzare.

**Step 1.2 — Connessione**

Usare la porta identificata al passo precedente:

```
Connect con:
connectionString = "Data Source=localhost:{port};Application Name=MCP-PBIModeling"
```

Verificare il successo della connessione prima di procedere.

### FASE 2 — Dump completo del modello

> **⚠️ REGOLA CONTEXT WINDOW — leggere prima di procedere**
> Il TMDL di un modello grande può superare i 3M caratteri e saturare la context window in un'unica chiamata.
> Regola obbligatoria: **non usare mai `maxReturnCharacters = -1` senza `filePath`**.
> Strategia preferita: export su file + query mirate per tabella.

**Step 2.1 — Esportare TMDL completo su file**

```
ExportTMDL con:
maxReturnCharacters = 0        ← non restituire nulla in chat
filePath = "{CartellaOutput}/tmdl_scan_{DatasetName}.txt"
```

Il file viene salvato su disco e usato come fonte di verità. Claude legge solo le sezioni necessarie tramite Grep/Read mirati invece di caricare tutto in context.

Se il modello ha ≤ 20 tabelle visibili, è accettabile usare `maxReturnCharacters = 30000` senza filePath.

**Step 2.1b — Raccolta metadata strutturata via MCP mirate (preferita per modelli grandi)**

Invece di parsare il TMDL grezzo, usare chiamate MCP specifiche in parallelo:

```
IN PARALLELO:
- model_operations GetStats          → contatori (N tabelle, misure, relazioni)
- relationship_operations List       → tutte le relazioni (nessun limite testo)
- measure_operations List            → lista misure con nomi
```

Poi, per ogni tabella con misure o colonne calcolate:
```
table_operations ExportTMDL con:
maxReturnCharacters = 15000    ← limite per tabella
```

Processare le tabelle in batch da 5 in parallelo. Non superare 15.000 caratteri per chiamata.

Questo produce la rappresentazione TMDL di tutto il modello (tabelle, colonne, misure, relazioni, perspectives, ruoli, cultures). È la fonte primaria di verità per tutto lo scan successivo.

Parsare il TMDL estraendo:
- **Tabelle**: nome, tipo partizione (`m`, `calculated`, `entity`), query M source (se partizione M)
- **Colonne**: nome, `dataType`, `sourceColumn`, `expression` (se calculated), `isHidden`, `isKey`, `formatString`, `dataCategory`, `sortByColumn`, `displayFolder`
- **Misure**: nome, `expression`, `displayFolder`, `isHidden`, `formatString`, `description`
- **Relazioni**: `fromTable`, `fromColumn`, `toTable`, `toColumn`, `cardinality`, `crossFilteringBehavior`, `isActive`
- **Gerarchie**: nome, livelli, tabella
- **Ruoli sicurezza**: nome, membri, filtri DAX per tabella
- **Perspectives**: nome e oggetti inclusi
- **Proprietà modello**: `culture`, `autoDateTimeEnabled` (se presente), `dataCategory` per tabelle (cerca `Time`)

**Step 2.2 — Dettaglio colonne (verifica)**

Per ogni tabella rilevata, chiamare `column_operations` con comando `List` per ottenere eventuali proprietà non presenti nel TMDL (es. `summarizeBy` di default).

### FASE 3 — Statistiche runtime via DAX

Queste query forniscono dati che il TMDL statico non contiene (row count, cardinalità, sanity check).

**Step 3.1 — Sanity check per tabella**

Per ogni tabella non-calculated, eseguire:

```dax
EVALUATE TOPN(1, 'NomeTabella')
```

Se la query fallisce, marcare la tabella come `scanError: true` e registrare il messaggio. Tabelle che falliscono il sanity check non devono bloccare lo scan ma vanno segnalate nel report.

**Step 3.2 — Row count per tabella**

Per ogni tabella con sanity check OK:

```dax
EVALUATE ROW("RowCount", COUNTROWS('NomeTabella'))
```

**Step 3.3 — Cardinalità colonne chiave**

Per ogni colonna identificata come chiave (usata in relazioni come `fromColumn` o `toColumn`, oppure con `isKey == true`):

```dax
EVALUATE ROW("Card", DISTINCTCOUNT('NomeTabella'[NomeColonna]))
```

Questo permette di rilevare duplicati sul lato "one" delle relazioni (BPA-M-004).

**Step 3.4 — Cardinalità colonne stringa sospette (eseguibile solo in modalità Completa)**

Per colonne stringa su tabelle fact, eseguire `DISTINCTCOUNT` per identificare candidati a estrazione in dimensione (BPA-M-005) o colonne ad altissima cardinalità (BPA-P-009).

Limitare a prime ~20 colonne per evitare scan eccessivo su modelli grandi.

> ⚠️ **Quando eseguire questo step:**
> - SOLO se l'utente ha scelto modalità **Completa** allo STEP A2 di `audit-existing-model.md`.
> - Se l'utente ha scelto **Rapida**, saltare interamente questo step e segnalare nel
>   report finale (sezione metadata scan) che `BPA-M-005` e `BPA-P-009` sono state
>   valutate solo per euristica sui nomi colonna, non sui dati.
> - **Vietato eseguire in autonomia il "rapido" senza che l'utente l'abbia scelto:** la
>   domanda allo STEP A2 è opt-in obbligatorio.

**Step 3.5 — Rilevamento colonne DateTime con ora vuota**

Per ogni colonna con `dataType == "dateTime"`:

```dax
EVALUATE ROW(
  "HasTime",
  COUNTROWS(
    FILTER(
      'NomeTabella',
      HOUR('NomeTabella'[NomeColonna]) > 0
      || MINUTE('NomeTabella'[NomeColonna]) > 0
      || SECOND('NomeTabella'[NomeColonna]) > 0
    )
  )
)
```

Se il risultato è `0` o `BLANK`, la colonna è candidata a conversione Date (BPA-P-007).

### FASE 4 — Analisi derivata

Queste analisi non richiedono chiamate MCP aggiuntive, si svolgono sul metadata già raccolto.

**Step 4.1 — Classificazione tabelle (fact vs dim vs altro)**

Euristica:
- **Fact**: tabella con ≥ 2 relazioni in cui è sul lato "many" (tipicamente nel mezzo dello star schema)
- **Dim**: tabella con almeno 1 relazione in cui è sul lato "one"
- **Calendar**: tabella con `dataCategory == "Time"` oppure con colonna chiave date + nome riconducibile a `Date`/`Calendar`/`Dim_Date`
- **Bridge**: tabella con 2+ relazioni lato "many" e poche colonne descrittive
- **Disconnected**: tabella senza relazioni (potenziale parameter table o isolata)
- **Calculated**: tabella con partizione `calculated`

Il ruolo inferito è un'euristica — indicarlo come `inferredRole` nel metadata, non come verità assoluta.

**Step 4.2 — Rilevamento snowflake**

Per ogni relazione, verificare se entrambe le tabelle coinvolte sono classificate come `dim`. Se sì, marca come `snowflake: true` per applicare BPA-M-002.

**Step 4.3 — Analisi riferimenti misure**

Per ogni misura, scansionare il testo dell'espressione DAX cercando riferimenti a:
- Altre misure: pattern `[NomeMisura]` dove `NomeMisura` è in elenco misure
- Colonne calcolate: pattern `'Tabella'[Colonna]` o `Tabella[Colonna]` dove la colonna è calculated
- Tabelle calcolate: menzione del nome tabella calculated in `CALCULATE`/`CALCULATETABLE`/iterators

Costruire un `dependencyGraph`:

```yaml
measureName:
  referencedBy: [altraMisura1, altraMisura2, ...]
  references: [misuraX, ...]
```

Misure con `referencedBy == []` E non referenziate in colonne/tabelle calcolate sono candidate per BPA-X-001 (inutilizzate a livello modello).

**Step 4.4 — Analisi pattern misure per display folder**

Per ogni misura, identificare il pattern dal nome:
- Contiene `YTD`, `MTD`, `QTD`, `To Date` → folder proposto: `To Date`
- Contiene `PY`, `LY`, `Prev`, `Previous`, `Precedente` → folder proposto: `Previous Period`
- Altrimenti → `Base Measures`

Serve a `refactor-actions.md` per la riorganizzazione folder.

## Output atteso

La fine dello scan produce una struttura dati unica (in memoria o come YAML/JSON) con questo schema:

```yaml
scanMetadata:
  scanTimestamp: "2026-04-22T10:00:00Z"
  datasetName: str
  port: int
  tmdlExportPath: str
  scanDurationSeconds: int
  rapidScan: bool        # true se skipped step 3.4

model:
  culture: str
  autoDateTimeEnabled: bool | null
  hasMarkedDateTable: bool

tables:
  - name: str
    type: "import" | "calculated" | "directQuery"
    source: str           # descrittivo: "Dataflow: X", "SQL Server: Y", "Calculated"
    sourceExpression: str | null   # query M se presente
    isHidden: bool
    dataCategory: str | null
    rowCount: int | null
    inferredRole: "fact" | "dim" | "calendar" | "bridge" | "disconnected" | "calculated"
    scanError: bool
    scanErrorMessage: str | null
    columns:
      - name: str
        dataType: str
        type: "data" | "calculated"
        expression: str | null
        sourceColumn: str | null
        isHidden: bool
        isKey: bool
        formatString: str | null
        dataCategory: str | null
        sortByColumn: str | null
        displayFolder: str | null
        cardinality: int | null
        hasTimeComponent: bool | null    # solo per dateTime
    measures:
      - name: str
        expression: str
        displayFolder: str | null
        isHidden: bool
        formatString: str | null
        description: str | null
        suggestedFolder: str              # da step 4.4
        referencedBy: [str]
        references: [str]

relationships:
  - fromTable: str
    fromColumn: str
    toTable: str
    toColumn: str
    cardinality: "oneToOne" | "oneToMany" | "manyToMany"
    crossFilteringBehavior: "singleDirection" | "bothDirections"
    isActive: bool
    isSnowflake: bool

hierarchies:
  - table: str
    name: str
    levels: [{name: str, column: str}]

securityRoles:
  - name: str
    members: [str]
    tableFilters: [{table: str, filterExpression: str}]

perspectives:
  - name: str
    includedObjects: [str]
```

## Gestione errori comuni

| Errore MCP | Causa | Azione |
|------------|-------|--------|
| `No databases found` | PBI Desktop aperto ma nessun modello caricato | Chiedere all'utente di aprire `.pbip` e fare Refresh |
| `Connection failed` | Porta cambiata o istanza chiusa | Rieseguire `ListLocalInstances` |
| DAX query fallita su tabella | Tabella con errori di refresh o calculated table rotta | Marcare `scanError: true` e continuare |
| `ExportToTmdlFolder` troncato | `maxReturnCharacters` non `-1` | Riconfigurare la chiamata |
| Timeout su `DISTINCTCOUNT` | Colonna ad altissima cardinalità su modello grande | Skippare colonna, registrare come `cardinality: null` |

## Performance e ottimizzazioni

Per modelli grandi (> 30 tabelle o > 10M righe fact):

- **Scan rapido**: offrire all'utente l'opzione di saltare step 3.4 (cardinalità stringhe fact) e step 3.5 (DateTime ora vuota).
- **Batch DAX queries**: quando possibile, raggruppare più `DISTINCTCOUNT` in un'unica `EVALUATE ROW(...)`.
- **Timeout per query**: impostare limite esplicito (es. 30s) e skippare con warning.

Al termine dello scan, riportare all'utente:
- Tempo totale scan
- Tabelle scansionate con successo vs errori
- Eventuali skip dovuti a ottimizzazioni
