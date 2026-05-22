# Documentazione tecnico-funzionale — Reference

> 🛑 **Se stai leggendo questo file mentre stai per generare la documentazione:**
> leggilo INTEGRALMENTE prima di scrivere qualsiasi cosa nel file di output. La struttura
> delle sezioni, i diagrammi e le convenzioni sono parte del deliverable. Saltare sezioni
> o improvvisare "perché si conosce il dominio" produce documentazione sotto-standard che
> l'utente finale potrebbe accettare senza accorgersi delle mancanze — errore grave.

Questo file è invocato dallo **STEP 16** di `SKILL.md` (flusso CREAZIONE),
**solo quando l'utente conferma Sì alla richiesta opzionale**. Se l'utente
sceglie No, questo file non viene letto e si passa direttamente a STEP 17.

---

## Scopo

Generare un file Markdown di documentazione tecnico-funzionale del semantic
model appena creato, salvato in:

```
{CartellaProgetto}/docs/{NomeProgetto}.md
```

Il file ha due audience parallele:

| Audience | Sezioni |
|---|---|
| **Technical** (data engineer / BI dev / manutenzione) | Architettura, schema tabelle, relazioni, sorgenti, refresh, dipendenze |
| **Functional** (business analyst / utente finale / stakeholder) | Diagramma star schema, catalogo misure con descrizione in linguaggio naturale, catalogo KPI per dominio business |

---

## STEP D1 — Raccolta metadata via MCP

Prima di generare il file, raccogli lo stato finale e completo del modello:

| Operazione MCP | Output da catturare |
|---|---|
| `database_operations.ExportTMDL` (modello intero) | TMDL completo — usalo come fallback per dettagli mancanti |
| `relationship_operations.List` | Lista relazioni con `fromTable/Column`, `toTable/Column`, `fromCardinality`, `toCardinality`, `isActive`, `crossFilteringBehavior` |
| `measure_operations.List` (tableName=`Calcs`) | Tutte le misure con `name`, `expression`, `displayFolder`, `formatString` |
| `column_operations.List` per ogni tabella | Colonne con `name`, `dataType`, `isHidden`, `isKey`, `dataCategory`, `summarizeBy` |
| `table_operations.List` | Tutte le tabelle con `name`, `dataCategory` (per identificare la Date Table) |
| Query DAX `EVALUATE ROW("Min", MIN({DateTable}[Date]), "Max", MAX({DateTable}[Date]), "Rows", COUNTROWS({DateTable}))` | Range effettivo Calendar e numero righe |

Raccogli anche dalle variabili di sessione (vedi SKILL.md):
- `{NomeProgetto}`, `{ModalitaStorage}`, `{TipoConnettore}` + parametri connettore
- `{GitProvider}`, `{GitRemoteURL}`, `{GitRepoPath}` (solo per la sezione "Repository")

---

### STEP D1b — Data Quality probes via DAX

Esegui le query DAX seguenti via `dax_query_operations.Execute` per popolare la
sezione **Data Quality** del documento. Tutte le query sono read-only e veloci
(< 1s su modelli con < 10M righe). Lanciale **in parallelo** per ridurre il
tempo totale.

#### Probe 1 — Row count per tabella

```dax
EVALUATE
UNION(
    ROW("Table", "{T1}", "Rows", COUNTROWS({T1})),
    ROW("Table", "{T2}", "Rows", COUNTROWS({T2}))
)
```

Una riga per ogni tabella del modello (Fact, Dim, Calendar, Calcs).

#### Probe 2 — Duplicati PK nelle Dimension

Per ogni tabella Dim e per la PK identificata (colonna `*_sk`, `*_id`, `*_key`
o suggerita da MCP):

```dax
EVALUATE
UNION(
    ROW("Dim", "{Dim1}", "PK", "{PK1}",
        "Rows", COUNTROWS({Dim1}),
        "DistinctPK", DISTINCTCOUNT({Dim1}[{PK1}]),
        "Duplicates", COUNTROWS({Dim1}) - DISTINCTCOUNT({Dim1}[{PK1}]),
        "BlankPK", COUNTBLANK({Dim1}[{PK1}]))
)
```

#### Probe 3 — Orfani per relazione

Per ogni relazione Fact → Dim, conta righe Fact con FK non presente nella PK Dim
e righe Fact con FK blank:

```dax
EVALUATE
UNION(
    ROW("From", "{Fact}.{FK1}", "To", "{Dim1}.{PK1}",
        "FactRows", COUNTROWS({Fact}),
        "Orphans", COUNTROWS(FILTER({Fact}, NOT({Fact}[{FK1}] IN VALUES({Dim1}[{PK1}])))),
        "BlankFK", COUNTBLANK({Fact}[{FK1}]))
)
```

#### Probe 4 — Calendar coverage e gaps

```dax
EVALUATE ROW(
    "FactMin", MIN({Fact}[{DateCol}]),
    "FactMax", MAX({Fact}[{DateCol}]),
    "CalMin", MIN('Calendar'[Date]),
    "CalMax", MAX('Calendar'[Date]),
    "CalCoversFact", IF(
        MIN('Calendar'[Date]) <= MIN({Fact}[{DateCol}])
        && MAX('Calendar'[Date]) >= MAX({Fact}[{DateCol}]),
        "OK", "ISSUE"
    ),
    "ExpectedDays", DATEDIFF(MIN('Calendar'[Date]), MAX('Calendar'[Date]), DAY) + 1,
    "ActualDays", COUNTROWS('Calendar'),
    "Gaps", DATEDIFF(MIN('Calendar'[Date]), MAX('Calendar'[Date]), DAY) + 1 - COUNTROWS('Calendar')
)
```

#### Probe 5 — Colonne numeriche (min, max, blank, distinct, avg)

Per ogni colonna numerica (`int64`, `double`, `decimal`) di tutte le tabelle —
esclude PK e FK già coperte sopra:

```dax
EVALUATE
UNION(
    ROW("Table", "{T}", "Column", "{C1}",
        "Min", MIN({T}[{C1}]),
        "Max", MAX({T}[{C1}]),
        "Avg", AVERAGE({T}[{C1}]),
        "Blanks", COUNTBLANK({T}[{C1}]),
        "Distinct", DISTINCTCOUNT({T}[{C1}]))
)
```

#### Probe 6 — Colonne date/datetime (min, max, blank, range)

```dax
EVALUATE
UNION(
    ROW("Table", "{T}", "Column", "{C1}",
        "Min", MIN({T}[{C1}]),
        "Max", MAX({T}[{C1}]),
        "Blanks", COUNTBLANK({T}[{C1}]),
        "RangeDays", DATEDIFF(MIN({T}[{C1}]), MAX({T}[{C1}]), DAY))
)
```

#### Probe 7 — Colonne string (cardinalità, blank, lunghezza)

```dax
EVALUATE
UNION(
    ROW("Table", "{T}", "Column", "{C1}",
        "Distinct", DISTINCTCOUNT({T}[{C1}]),
        "Blanks", COUNTBLANK({T}[{C1}]),
        "MinLen", MINX(VALUES({T}[{C1}]), LEN({T}[{C1}])),
        "MaxLen", MAXX(VALUES({T}[{C1}]), LEN({T}[{C1}])))
)
```

#### Probe 8 — Anomalie tipo dato (date come string)

Per ogni colonna `string` con nome contenente `*_date`, `*_dt`, `birth*`,
`data_*`, `dt_*` (case-insensitive) campiona 1 valore:

```dax
EVALUATE TOPN(1, VALUES({T}[{StringCol}]))
```

Se il valore restituito matcha regex `^\d{1,2}[/-]\d{1,2}[/-]\d{2,4}$` o
`^\d{4}-\d{2}-\d{2}$` → **anomalia** 🟡 Warning: data conservata come string,
non filtrabile via Calendar — segnalare di convertire a `dateTime` lato sorgente.

#### Probe 9 — Cardinalità anomala

Calcola % cardinalità per colonna (Distinct / Rows × 100). Soglie di warning:

| Condizione | Severità | Messaggio |
|---|---|---|
| Distinct = 1 | 🟡 Warning | Colonna single-value, candidata a rimozione |
| Distinct < 1% di Rows in Fact | 🔵 Info | Candidata Dimension (vedi STEP 13 di SKILL.md) |
| Distinct > 90% di Rows in Dim (e non è PK) | 🟡 Warning | Cardinalità innaturale per Dim — verificare se è PK reale o errore di modeling |
| % Blank > 50% | 🟡 Warning | Colonna sparsamente popolata |
| % Blank tra 10–50% | 🔵 Info | Da monitorare |

---

### STEP D1c — Aggregazione esiti DQ

Costruisci internamente un dizionario di issues con severità:

| Severità | Esempi |
|---|---|
| 🔴 **Error** | Duplicati PK > 0 in Dim; orfani > 0; Calendar non copre Fact; FK blank in Fact |
| 🟡 **Warning** | Date come string; cardinalità anomala; colonne single-value; % blank > 50% |
| 🔵 **Info** | % blank tra 1–50%; gaps Calendar attesi (es. weekend); Distinct < 1% in Fact |

Conteggia errori, warning, info — questi numeri popolano il box "Sintesi DQ"
del template.

---

## STEP D2 — Generazione descrizioni in linguaggio naturale

Per ogni misura, genera una descrizione **funzionale** (1 riga) basata sul DAX
e sul `displayFolder`. Esempi:

| Pattern DAX | Descrizione funzionale |
|---|---|
| `SUM(Fact[col])` | "Somma totale di {col} su tutte le righe della Fact." |
| `SUMX(Fact, Fact[a] * Fact[b])` | "Somma del prodotto {a} × {b} riga per riga." |
| `DIVIDE([X], [Y])` | "Rapporto medio tra {X} e {Y}." |
| `COUNTROWS(Fact)` | "Numero di righe nella Fact." |
| `DISTINCTCOUNT(Fact[col])` | "Numero di valori distinti di {col}." |
| `TOTALYTD([X], Calendar[Date])` | "Valore di {X} cumulato dall'inizio dell'anno corrente." |
| `TOTALMTD([X], …)` | "Valore di {X} cumulato dall'inizio del mese corrente." |
| `TOTALQTD([X], …)` | "Valore di {X} cumulato dall'inizio del trimestre corrente." |
| `CALCULATE([X], SAMEPERIODLASTYEAR(…))` | "Valore di {X} nello stesso periodo dell'anno precedente." |
| `CALCULATE([X], PREVIOUSMONTH(…))` | "Valore di {X} nel mese precedente." |
| `CALCULATE([X], PREVIOUSQUARTER(…))` | "Valore di {X} nel trimestre precedente." |

Per pattern non riconosciuti scrivi: "Misura calcolata via {DAX sintetizzato}."
Mantieni le descrizioni in italiano se i nomi delle misure sono in italiano,
altrimenti adattati alla lingua delle misure.

---

## STEP D3 — KPI Catalog (sezione funzionale)

Mappa le misure a domande business comuni. Logica:

1. Prendi le misure della cartella **Base Measures** come "KPI primari"
2. Per ogni KPI primario, trova le sue varianti temporali (To Date, Previous Period)
3. Genera una riga per ogni domanda business naturale:

| Domanda business naturale | Misura |
|---|---|
| "Quanto abbiamo {KPI} totale?" | `[Totale {KPI}]` |
| "Quanto abbiamo {KPI} da inizio anno?" | `[YTD {KPI}]` |
| "Quanto abbiamo {KPI} nel mese?" | `[MTD {KPI}]` |
| "Quanto abbiamo {KPI} nel trimestre?" | `[QTD {KPI}]` |
| "Come va il {KPI} rispetto allo stesso periodo dell'anno scorso?" | `[PY {KPI}]` |
| "Come va il {KPI} rispetto al mese precedente?" | `[PM {KPI}]` |
| "Come va il {KPI} rispetto al trimestre precedente?" | `[PQ {KPI}]` |
| "Quante righe abbiamo nei dati?" | `[Conteggio Righe]` |
| "Quanti elementi distinti?" | `[Distinti {Chiave}]` |

Se mancano misure (es. niente Previous Period), salta le righe corrispondenti.

---

## STEP D4 — Genera il file Markdown

Crea la cartella `{CartellaProgetto}/docs/` se non esiste, poi scrivi il file
`{NomeProgetto}.md` usando il **template completo** qui sotto. Sostituisci
TUTTI i placeholder `{...}` con i dati reali.

### Template documentazione

````markdown
# {NomeProgetto} — Documentazione tecnico-funzionale

> Generato automaticamente il **{DataGenerazione}** con `pbi-semantic-model-advanced`.
> Per modifiche al modello rieseguire la skill o aggiornare manualmente il file.

---

## 1. Overview

| Proprietà | Valore |
|---|---|
| Nome modello | `{NomeProgetto}` |
| Tipologia | Semantic Model Power BI (.pbip) |
| Modalità storage | {ModalitaStorage} |
| Connettore primario | {TipoConnettore} |
| Compatibility level | 1600 |
| Tabelle totali | {N_tot} ({N_fact} Fact, {N_dim} Dimension, Calendar, Calcs) |
| Relazioni totali | {N_rel} |
| Misure totali | {N_meas} |
| Repository | {GitProvider}: `{GitRepoPath}` (branch `feature/{NomeProgetto}`) |

---

## 2. Architettura — Star Schema

```mermaid
erDiagram
{righe-erDiagram}
```

**Legenda relazioni:** `||--o{` indica cardinalità *one-to-many* (Dim → Fact).
La direzione di filtro va sempre da Dim a Fact.

> 💡 **Come visualizzare il diagramma**
>
> Il blocco ` ```mermaid ` viene renderizzato **automaticamente** come immagine quando questo file è aperto in:
> - **GitHub** (web UI) — repo browser e Pull Request
> - **Azure DevOps Repos** (web UI, dal 2023) — repo browser e Pull Request
> - **GitLab** — repo browser
> - **VS Code** con l'estensione [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid) (preview con `Ctrl+Shift+V`)
> - **Obsidian / Notion / Typora** — supporto nativo
>
> Se invece vedi il **codice grezzo** (es. apertura del .md in un editor base):
> 1. Copia il contenuto del blocco ` ```mermaid ` (solo le righe tra i delimitatori)
> 2. Incollalo su [**Mermaid Live Editor**](https://mermaid.live) — rendering immediato + export in **PNG / SVG / PDF**
> 3. Per **draw.io**: menu *Arrange → Insert → Advanced → Mermaid…* e incolla il codice (l'editor lo converte in shape modificabili)

---

## 3. Sorgenti dati

### {TipoConnettore}
{dettagli-connettore}

| Tabella | Entità sorgente | Modalità partizione |
|---|---|---|
{righe-tabella-sorgenti}

---

## 4. Schema tabelle (technical)

{per-ogni-tabella-fact-dim-genera-blocco}

### `{NomeTabella}` ({Fact|Dimension})

| Colonna | Tipo | Chiave | Hidden | Note |
|---|---|---|---|---|
{righe-colonne-tabella}

{se-Fact: "**Misure aggregate**: vedi sezione 7."}

---

## 5. Relazioni

| # | Da (Many) | A (One) | Stato | Cross filter |
|---|---|---|---|---|
{righe-relazioni}

**Note:**
- Tutte le relazioni sono attive di default.
- Cross-filter `OneDirection` = i filtri vanno solo da Dim a Fact (raccomandato).
- Eventuali relazioni `BothDirections` sono evidenziate.

---

## 6. Calendar Table

| Proprietà | Valore |
|---|---|
| Tipo | Calculated table DAX (auto-genera al refresh) |
| Range | {MinDate} → {MaxDate} |
| Righe | {N_calendar_rows} |
| Marcata Date Table | ✅ (`dataCategory: Time`) |
| Colonne | Date, Anno, Mese, NomeMese, Trimestre, AnnoMese, GiornoSettimana, NomeGiorno, IsWeekend |
| Sort | `NomeMese` ordinata per `Mese` |

**Espressione DAX:**
```dax
{daxExpression-Calendar}
```

> **Manutenzione:** il range si estende automaticamente quando arrivano nuovi
> dati nella Fact (`MIN/MAX(fact[date])`). Non serve aggiornare manualmente.

---

## 7. Catalogo misure (Calcs)

Tutte le misure sono raccolte nella tabella placeholder `Calcs` (la colonna
`Value` è nascosta). Le misure sono organizzate in tre cartelle (`displayFolder`).

### 7.1 Base Measures

| Misura | Format | Descrizione funzionale | DAX |
|---|---|---|---|
{righe-base-measures}

### 7.2 To Date (cumulati)

| Misura | Format | Descrizione funzionale | DAX |
|---|---|---|---|
{righe-todate-measures}

### 7.3 Previous Period (confronti temporali)

| Misura | Format | Descrizione funzionale | DAX |
|---|---|---|---|
{righe-prevperiod-measures}

---

## 8. KPI catalog — domande business

Domande tipiche e misura corrispondente. Pensata per analisti e utenti finali
che costruiscono dashboard o pongono domande al modello.

| Domanda business | Misura |
|---|---|
{righe-kpi-catalog}

---

## 9. Dipendenze e refresh

### Catena di refresh
1. **Sorgente esterna** ({TipoConnettore}) — owner: dati upstream
2. **Tabelle base** caricate in modalità Import → necessario refresh
3. **Calculated tables** (`Calendar`, `Calcs`) — ricalcolate automaticamente
4. **Misure** — calcolate runtime, nessun refresh richiesto

### Permessi richiesti
{permessi-richiesti-per-connettore}

---

## 10. Data Quality

> Sezione generata automaticamente da probe DAX al momento della creazione doc.
> Per rieseguire i check: rilancia STEP 16 della skill o esegui le query in
> `references/documentation.md` STEP D1b.

### 10.1 Sintesi

| Severità | Conteggio | |
|---|---|---|
| 🔴 Error | {N_error} | {se >0: "vedi sezioni sotto evidenziate in rosso"; altrimenti "nessun problema critico"} |
| 🟡 Warning | {N_warning} | {messaggio sintetico se >0} |
| 🔵 Info | {N_info} | {messaggio sintetico se >0} |

{se-tutto-ok: "✅ Modello pulito — nessuna anomalia rilevata."}

### 10.2 Tabelle — Integrità chiavi primarie

| Tabella | Righe | PK | PK distinti | Duplicati | PK blank | Esito |
|---|---|---|---|---|---|---|
{righe-pk-check — formato: |{Dim}|{Rows}|{PK}|{DistinctPK}|{Duplicates}|{BlankPK}|{✅|🔴}|}

### 10.3 Integrità relazioni (orfani)

| Da (Fact) | A (Dim) | Righe Fact | Orfani | FK blank | % | Esito |
|---|---|---|---|---|---|---|
{righe-orphans-check}

> **Soglia:** Esito 🔴 Error se `Orphans > 0` OR `BlankFK > 0`. Altrimenti ✅.

### 10.4 Coverage Calendar vs Fact

| Metrica | Valore |
|---|---|
| Range Fact ({DateCol}) | {FactMin} → {FactMax} |
| Range Calendar | {CalMin} → {CalMax} |
| Calendar copre Fact | {✅ OK \| 🔴 ISSUE} |
| Date previste (giorni) | {ExpectedDays} |
| Date effettive | {ActualDays} |
| Gaps | {Gaps} {se >0: "🔴" altrimenti "✅"} |

### 10.5 Colonne numeriche — Statistiche

| Tabella | Colonna | Min | Max | Avg | Blank | % Blank | Distinct | Note |
|---|---|---|---|---|---|---|---|---|
{righe-numeric-stats}

### 10.6 Colonne date/datetime — Statistiche

| Tabella | Colonna | Min | Max | Range (gg) | Blank | % Blank | Esito |
|---|---|---|---|---|---|---|---|
{righe-date-stats}

### 10.7 Colonne string — Cardinalità e lunghezza

| Tabella | Colonna | Distinct | % Card. | Blank | Min len | Max len | Note |
|---|---|---|---|---|---|---|---|
{righe-string-stats — colonna Note: ⚠️ "data come string" / "single-value" / vuota}

### 10.8 Anomalie tipo dato

{se-non-trovate: "✅ Nessuna anomalia tipo dato rilevata."}
{se-trovate:}

| Tabella | Colonna | Tipo attuale | Tipo sospetto | Sample valore | Azione consigliata |
|---|---|---|---|---|---|
{righe-anomalie-tipo}

### 10.9 Cardinalità anomale

{lista-cardinalità-anomale: bullet points per ogni colonna con cardinalità sospetta}

---

## 11. Limitazioni e caveat noti

Note funzionali e architetturali non rilevabili automaticamente dalle probe DQ:

{lista-caveat-architetturali}

Caveat tipici da considerare quando applicabili:
- Misure Previous Period restituiscono BLANK per il primo periodo del dataset (atteso).
- `DISTINCTCOUNT` su colonne ad alta cardinalità impatta le performance — monitorare al crescere del dataset.
- Colonne `*_sk` (surrogate key) sono visibili — best practice è nasconderle (`isHidden: true`).
- Surrogate key non collegate a Dim (es. `sales_sk` interno alla Fact) restano visibili ma sono inutilizzabili come filtro — considerare hide.
- Refresh schedulato richiede credenziali persistite lato Power BI Service / Fabric.

---

## 12. File del progetto

```
{NomeProgetto}.pbip                                 # entrypoint Power BI
{NomeProgetto}.SemanticModel/
  .platform                                         # metadata Fabric Git
  definition.pbism                                  # config semantic model
  definition/
    database.tmdl                                   # compatibility level
    model.tmdl                                      # culture, annotations
    relationships.tmdl                              # tutte le relazioni
    cultures/en-US.tmdl
    tables/
      *.tmdl                                        # una per tabella
{NomeProgetto}.Report/
  .platform
  definition.pbir                                   # link al SemanticModel
docs/
  {NomeProgetto}.md                                 # questo file
```

---

*Fine documentazione.*
````

---

## STEP D5 — Commit (NO push)

⚠️ **Il push NON viene eseguito qui** — il push è centralizzato nello STEP 17
di SKILL.md, dopo questo step. Qui si esegue **solo** il commit locale.

Solo se `{GitEnabled} = true`:

```bash
cd "{CartellaProgetto}"
git add "docs/{NomeProgetto}.md"
git commit -m "docs: add technical-functional documentation"
```

Conferma all'utente:
```
✅ Documentazione generata: {CartellaProgetto}/docs/{NomeProgetto}.md
✅ Commit creato sulla feature branch (push posticipato a STEP 17)
```

Se `{GitEnabled} = false`: crea solo il file localmente, salta il commit,
e avvisa: "File generato in {CartellaProgetto}/docs/{NomeProgetto}.md (nessun commit — git disabilitato)."

Termina qui e torna a SKILL.md per proseguire con STEP 17.

---

## Note operative

- Mantieni il template Markdown stabile: future modifiche al modello rigenerano
  il file con la stessa struttura, facilitando i diff in PR.
- Se l'utente ha messo descrizioni custom su misure o colonne (`description: …`
  in TMDL), usale nelle tabelle invece di rigenerarle dal pattern DAX.
- Per modelli grandi (>50 misure o >20 tabelle) considera di splittare il file
  in più pagine sotto `docs/` (es. `docs/{NomeProgetto}/measures.md`,
  `docs/{NomeProgetto}/tables.md`). Comportamento di default: file singolo.
- Mermaid renderizza nativamente su GitHub e Azure DevOps Wiki/repo (>2023).
