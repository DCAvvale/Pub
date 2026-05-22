# Refactor Actions Reference

Catalogo delle azioni correttive proponibili dopo l'audit. Usato da `audit-existing-model.md` nello STEP A5 e A6.

## Scopo

Per ogni categoria di problema rilevato, definire:
- Quando proporla (trigger da violazioni BPA)
- Cosa mostrare all'utente come preview
- Come eseguirla via MCP (comandi esatti dove applicabile)
- Auto-fix policy (safe / approval / manuale)

## Flusso generale (STEP A5/A6 dell'orchestratore)

1. Dopo la generazione del report, costruire l'elenco di azioni proponibili filtrando le violazioni BPA per categoria.
2. Mostrare l'elenco numerato raggruppato per priorità (come in Sezione 9 del report).
3. Chiedere all'utente quali azioni eseguire. L'utente può rispondere:
   - `tutte` → esegui nell'ordine proposto
   - `1, 3, 5` → esegui solo quelle
   - `tutte tranne 2, 4` → esegui tutto escluse quelle
   - `safe` → esegui solo le azioni con auto-fix ✅ safe
   - `nessuna` → termina senza modifiche
4. Per ogni azione approvata:
   - Mostrare preview dettagliato (oggetti coinvolti, diff, rischi)
   - Chiedere conferma finale (se azione `⚠️ requires_approval` o `❌ manuale`)
   - Eseguire via MCP
   - Mostrare esito (successo / errore)
5. Al termine di tutte le azioni, proporre di rigenerare il report TO-BE.

## Regola generale di sicurezza

**Prima di qualsiasi modifica strutturale** (tabelle, relazioni, colonne calcolate/calculated tables), raccomandare all'utente di fare un backup del `.pbip` (copia cartella). Questo va detto **una sola volta** all'inizio della fase refactor, non prima di ogni azione.

---

## Catalogo azioni

### Azione A — Misure inutilizzate

**Trigger:** violazioni `BPA-X-001`
**Severità fix:** Maintenance
**Auto-fix:** ⚠️ richiede approval

**Preview all'utente:**

```
🧹 Trovate {N} misure non referenziate a livello modello:

1. Sales Amount Old (Calcs)
2. Customer Count Draft (Calcs)
...

⚠️ Limitazione: non posso verificare l'uso nei visual dei report.

Scegli l'azione:
  [A1] CONSIGLIATO — Sposta tutte in display folder `_ToBeDeleted`
       → reversibile, dà tempo di verificare nei report prima del delete
  [A2] SCONSIGLIATO — Elimina definitivamente
       → irreversibile senza backup
  [A3] Review una per una (chiedo conferma per ogni misura)
```

**Esecuzione MCP:**

- **Opzione A1 (sposta in folder):**
  ```
  batch_measure_operations con operations = [
    {action: "Update", table: "Calcs", name: "Sales Amount Old",
     properties: {displayFolder: "_ToBeDeleted"}},
    ...
  ]
  useTransaction: true
  continueOnError: false
  ```

- **Opzione A2 (delete):**
  ```
  batch_measure_operations con operations = [
    {action: "Delete", table: "Calcs", name: "Sales Amount Old"},
    ...
  ]
  ```
  Richiedere conferma **esplicita** aggiuntiva: mostrare elenco nomi e chiedere "Confermi eliminazione irreversibile? (yes/no)".

- **Opzione A3:** iterare una misura alla volta, chiedere conferma, applicare.

---

### Azione B — Riorganizzazione display folder standard

**Trigger:** violazioni `BPA-X-004`
**Auto-fix:** ⚠️ richiede approval

**Preview:**

```
📁 Trovate {N} misure con folder non standard o senza folder.

Proposta riassegnazione basata su pattern del nome:
  - Contiene YTD/MTD/QTD → `To Date`
  - Contiene PY/LY/Prev/Previous/Precedente → `Previous Period`
  - Altrimenti → `Base Measures`

| Misura                | Tabella | Folder attuale  | Folder proposto  |
|-----------------------|---------|-----------------|------------------|
| Sales YTD             | Calcs   | (nessuno)       | To Date          |
| Sales PY              | Calcs   | Altro           | Previous Period  |
| Total Sales           | Calcs   | Altro           | Base Measures    |

Procedere con riassegnazione?
  [B1] Applica tutte le proposte
  [B2] Review una per una
  [B3] Annulla
```

**Esecuzione MCP:**

```
batch_measure_operations con operations = [
  {action: "Update", table: "Calcs", name: "Sales YTD",
   properties: {displayFolder: "To Date"}},
  ...
]
useTransaction: true
```

---

### Azione C — Consolidamento misure in tabella `Calcs`

**Trigger:** violazioni `BPA-X-003`
**Auto-fix:** ⚠️ richiede approval

**Preview:**

```
📦 Trovate {N} misure sparse su {M} tabelle dati.

Proposta: spostare tutte nella tabella `Calcs` dedicata.

{Se Calcs NON esiste:}
  ⚠️ Tabella `Calcs` non esistente. Verrà creata come:
    - Calculated table: `Calcs = ROW("_", BLANK())`
    - Colonna `_` nascosta (hidden)
  Le misure saranno spostate mantenendo folder e format.

Misure da spostare:
  - [Sales] Total Revenue → [Calcs] Total Revenue
  - [Customer] Customer Count → [Calcs] Customer Count
  ...

Procedere?
```

**Esecuzione MCP:**

**Se `Calcs` non esiste**, prima crearla:

```
table_operations con:
  action: "Create"
  table: {
    name: "Calcs",
    type: "calculated",
    expression: 'ROW("_", BLANK())',
    columns: [{name: "_", dataType: "string", isHidden: true}]
  }
```

Poi per ogni misura, ricreare in `Calcs` e rimuovere dall'originale:

```
batch_measure_operations con operations = [
  {action: "Create", table: "Calcs", name: "Total Revenue",
   properties: {expression: "SUM(Sales[Amount])",
                displayFolder: "Base Measures",
                formatString: "#,0"}},
  {action: "Delete", table: "Sales", name: "Total Revenue"},
  ...
]
useTransaction: true
continueOnError: false
```

L'uso di `useTransaction: true` garantisce rollback se una creazione fallisce, evitando di perdere misure.

---

### Azione D — Refactor snowflake

**Trigger:** violazioni `BPA-M-002`
**Auto-fix:** ❌ manuale (proposta codice, applicazione utente)

**Preview:**

```
❄️ Rilevate {N} catene snowflake:

Chain #1: Customer → Country → Continent

Proposta di refactor:
  1. Denormalizzare Country e Continent dentro Customer via merge in PQ
  2. Rimuovere relazioni dim→dim
  3. (Opzionale) Rimuovere tabelle Country e Continent se non più referenziate

Codice Power Query proposto (da applicare in Power Query Editor):

```m
let
    Source = ...,  // query Customer originale
    MergeCountry = Table.NestedJoin(Source, {"CountryKey"}, Country, {"CountryKey"}, "_c", JoinKind.LeftOuter),
    ExpandCountry = Table.ExpandTableColumn(MergeCountry, "_c", {"CountryName", "ContinentKey"}),
    MergeContinent = Table.NestedJoin(ExpandCountry, {"ContinentKey"}, Continent, {"ContinentKey"}, "_k", JoinKind.LeftOuter),
    ExpandContinent = Table.ExpandTableColumn(MergeContinent, "_k", {"ContinentName"}),
    Cleanup = Table.RemoveColumns(ExpandContinent, {"CountryKey", "ContinentKey"})
in
    Cleanup
```

⚠️ Questa modifica richiede l'applicazione manuale in Power Query Editor:
  1. Aprire Power Query (Transform Data)
  2. Selezionare la query Customer
  3. Sostituire con il codice sopra (adattando le colonne se necessario)
  4. Apply & Close

Devo solo generare il codice, oppure procedo anche con:
  [D1] Rimozione relazioni dim→dim dopo conferma del refactor M?
  [D2] Rimozione tabelle Country/Continent se non più referenziate?
  [D3] Solo generazione codice M, agisco solo dopo conferma manuale
```

**Esecuzione MCP (solo dopo conferma che utente ha applicato il merge M):**

- **D1 (rimuovi relazioni):**
  ```
  relationship_operations action="Delete" per ogni relazione dim→dim interessata
  ```

- **D2 (rimuovi tabelle):**
  ```
  table_operations action="Delete" (richiedere conferma esplicita)
  ```

---

### Azione E — Relazioni bidirezionali → single direction

**Trigger:** violazioni `BPA-P-001`
**Auto-fix:** ⚠️ richiede approval

**Preview:**

```
↔️ Trovate {N} relazioni bidirezionali:

1. Customer[RegionKey] ↔ Region[RegionKey]

Proposta: convertire a singleDirection.

⚠️ Verifica: ci sono misure che fanno affidamento sulla direzione inversa?
Controllo automatico: {nessun USERELATIONSHIP rilevato | misure X, Y usano questo pattern}

Se confermi, dopo il cambio potrebbe essere necessario aggiungere CROSSFILTER()
in alcune misure per ripristinare il filtro inverso dove serve.

Procedere con la conversione?
  [E1] Applica a tutte
  [E2] Review una per una
  [E3] Annulla
```

**Esecuzione MCP:**

```
relationship_operations con:
  action: "Update"
  fromTable: "Customer"
  fromColumn: "RegionKey"
  toTable: "Region"
  toColumn: "RegionKey"
  properties:
    crossFilteringBehavior: "singleDirection"
```

Dopo la modifica, segnalare all'utente di testare i visual che dipendevano dal filtro inverso.

---

### Azione F — Relazioni inattive review

**Trigger:** violazioni `BPA-M-003`
**Auto-fix:** ⚠️ richiede approval

**Preview:**

```
⏸️ Trovate {N} relazioni inattive:

1. Sales[ShipDateKey] → Date[DateKey]
   Analisi automatica: trovata misura "Ship Sales" che usa
     USERELATIONSHIP(Sales[ShipDateKey], Date[DateKey])
   → Giustificata ✅

2. Sales[OldKey] → OldDim[Key]
   Analisi automatica: nessun USERELATIONSHIP trovato
   → Candidata rimozione

Per ogni relazione senza giustificazione, scegli:
  [F-keep] Mantieni (l'utente sa che serve)
  [F-delete] Elimina
```

**Esecuzione MCP:**

```
relationship_operations action="Delete" con chiavi from/to
```

---

### Azione G — Calculated columns → Power Query

**Trigger:** violazioni `BPA-P-004`
**Auto-fix:** ❌ manuale

**Preview:**

```
🧮 Trovate {N} colonne calcolate candidate a spostamento in PQ:

| Tabella  | Colonna    | Espressione                          | Complessità |
|----------|------------|--------------------------------------|-------------|
| Sales    | Margin     | Sales[Price] - Sales[Cost]           | Semplice    |
| Customer | FullName   | Customer[First] & " " & Customer[L.] | Semplice    |
| Sales    | Category   | SWITCH(...) complesso                | Media       |

Per le "semplici" posso generare il codice M equivalente.
Per le "medie/complesse" richiede review manuale del mapping DAX→M.

Devo procedere con:
  [G1] Genera codice M per le semplici (applicazione manuale in PQ Editor)
  [G2] Lista completa con suggerimenti per ciascuna (solo analisi)
  [G3] Salta
```

**Esecuzione MCP:** nessuna diretta. Generare codice M e istruzioni testuali per l'utente.

---

### Azione H — Generazione dimensioni aggiuntive

**Trigger:** violazioni `BPA-M-005`
**Auto-fix:** ⚠️ richiede approval

**Delega:** riusa la logica dello STEP 13 di `SKILL.md` (generazione dimensioni da colonne categoriche su fact). Non duplicare qui: richiamare lo STEP 13 passando l'elenco di colonne candidate identificate dallo scanner.

**Preview:**

```
📊 Su {fact table} trovate {N} colonne stringa a bassa cardinalità candidate a estrazione in dimensione:

| Colonna      | Distinct | Esempi           |
|--------------|----------|------------------|
| ProductLine  | 5        | Mountain, Road...|
| OrderStatus  | 4        | New, Shipped... |

Per ciascuna, posso creare una dimensione dedicata (procedura come STEP 13 di creazione modello).

Quali estrarre?
  [H-all] Tutte
  [H-select] Selezione (indica numeri)
  [H-skip] Salta
```

**Nota TODO:** valutare estrazione di STEP 13 in reference condivisa `dim-generation.md` riutilizzabile sia dalla creazione che dall'audit.

---

### Azione I — Creazione Date Table marcata

**Trigger:** violazione `BPA-M-001`
**Auto-fix:** ⚠️ richiede approval

**Delega:** riusa la logica dello STEP 12 di `SKILL.md` (calendar DAX dinamica full-year, auto-espande). Non duplicare.

**Preview:**

```
📅 Nessuna Date Table marcata rilevata.

Opzioni:
  [I1] Crea calendar DAX dinamica (STEP 12 del flusso creazione)
       → copre MIN → MAX delle date nelle fact, auto-espande su refresh
  [I2] Ho già una tabella date ma non è marcata — marcala come Date Table
       (richiede nome tabella)
  [I3] Salta
```

**Esecuzione MCP:**

- **I1:** chiamare la procedura STEP 12 (vedi `SKILL.md`).
- **I2:**
  ```
  table_operations action="Update"
  properties: {dataCategory: "Time"}
  column_operations action="Update" sulla colonna chiave date
  properties: {isKey: true}
  ```

---

### Azione L — Fix rapidi BPA (bulk)

**Trigger:** violazioni con auto-fix ✅ safe (vari BPA)
**Auto-fix:** ✅ safe → può essere applicata automaticamente su conferma batch unica

**Preview:**

```
⚡ Fix rapidi disponibili (bulk apply):

1. [BPA-N-001] Format string mancanti: {N} misure
   Default: "#,0.00" per numeriche, "0.0%" se nome contiene % o Perc
2. [BPA-N-002] Format date mancanti: {N} colonne → "dd/MM/yyyy"
3. [BPA-P-008] Nascondi colonne chiave: {N} colonne
4. [BPA-X-002] Nascondi colonne tecniche inutilizzate: {N} colonne
5. [BPA-N-003] Rimuovi spazi in testa/coda: {N} oggetti
6. [BPA-P-003] Disabilita Auto Date/Time (se attivo)

Applicare tutti? [sì/no/selezione]
```

**Esecuzione MCP (bulk):**

- **Format string misure:**
  ```
  batch_measure_operations operations=[
    {action: "Update", table: "Calcs", name: "X",
     properties: {formatString: "#,0.00"}},
    ...
  ]
  ```

- **Format string / hide colonne:**
  ```
  batch_column_operations operations=[
    {action: "Update", table: "Date", column: "Date",
     properties: {formatString: "dd/MM/yyyy"}},
    {action: "Update", table: "Sales", column: "CustomerKey",
     properties: {isHidden: true}},
    ...
  ]
  ```

- **Rimozione spazi:** scan nomi, rename via operation `Update` con nuovo nome `.strip()`.

- **Auto Date/Time:**
  ```
  model_operations action="Update"
  properties: {autoDateTimeEnabled: false}
  ```

---

## Dopo l'esecuzione delle azioni

### Report di esecuzione

Al termine, produrre un riepilogo testuale con:

```
✅ Azioni completate: {N}
⚠️ Azioni saltate (richiedono review manuale): {N}
❌ Azioni fallite: {N}

Dettaglio:
- Azione A1 (misure inutilizzate → _ToBeDeleted): 12 misure spostate ✅
- Azione E (bidirezionali): 2/2 convertite ✅
- Azione D (snowflake): codice M generato, applicazione manuale richiesta ⚠️
```

### Rigenerazione report TO-BE

Proporre all'utente:

```
Vuoi rigenerare il report di audit per confrontare AS-IS vs TO-BE?
  [sì] Rigenero scan completo + report → audit_TO-BE_{DatasetName}_{date}.md
  [no] Termina
```

Se sì, rieseguire STEP A2, A3, A4 dell'orchestratore e produrre nuovo file. Mostrare delta principali rispetto all'AS-IS (riduzione violazioni per categoria).

## Policy di sicurezza sintetica

| Auto-fix | Comportamento |
|----------|---------------|
| ✅ safe | Può essere applicata automaticamente dopo approvazione batch iniziale dell'Azione L |
| ⚠️ requires_approval | Richiede conferma esplicita **per singola azione** prima dell'esecuzione |
| ❌ manuale | Claude produce solo codice/istruzioni, l'utente applica fuori dal MCP |

## Nota TODO — refactor futuro

Le azioni **H** e **I** duplicano parzialmente la logica degli STEP 13 e 12 di `SKILL.md`. In un refactor futuro conviene estrarre:
- `dim-generation.md` — logica generazione dimensioni (usata da creazione STEP 13 e audit H)
- `calendar-creation.md` — logica creazione calendar DAX (usata da creazione STEP 12 e audit I)

Lasciare inizialmente i rimandi espliciti a `SKILL.md`, refactor quando i flussi saranno stabilizzati.
