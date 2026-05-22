# Best Practices Reference

Catalogo di regole ispirate a Best Practice Analyzer (BPA) di Tabular Editor, filtrate e adattate per Power BI Desktop / Fabric. Usato da Claude durante l'audit di un modello esistente (`audit-existing-model.md`) per rilevare violazioni e proporre azioni correttive.

## Scopo

Fornire a Claude un elenco deterministico e consumabile di controlli da eseguire sul dataset raccolto dallo scanner. Ogni regola è atomica, ha una detection logic eseguibile via MCP e un fix associato.

## Come si usa questa reference

1. Lo scanner (`model-scanner.md`) raccoglie tutto il metadata del modello.
2. Claude itera su questo catalogo e valuta ciascuna regola contro il metadata.
3. Le violazioni vengono aggregate nel report (`audit-report.md`) con severità e fix.
4. Le azioni correttive (`refactor-actions.md`) consumano l'elenco violazioni.

## Livelli di severità

- **🔴 Error** — viola principi fondamentali di modeling o può produrre risultati scorretti. Da correggere prima del rilascio.
- **🟡 Warning** — impatto su performance, manutenibilità o leggibilità. Da valutare caso per caso.
- **🔵 Info** — best practice di stile o organizzazione. Opzionale ma consigliato.

## Categorie

- **Performance** — regole che impattano velocità query, refresh, dimensione modello
- **DAX** — espressioni DAX in misure e colonne calcolate
- **Modeling** — struttura tabelle, relazioni, star schema
- **Maintenance** — pulizia, oggetti inutilizzati, organizzazione
- **Naming & Formatting** — convenzioni di nomenclatura e formattazione utente finale

## Schema di una regola

Ogni regola segue questo schema:

```
### BPA-{CAT}-{NNN} — {Titolo breve}

- **Categoria:** {Performance | DAX | Modeling | Maintenance | Naming & Formatting}
- **Severità:** {Error | Warning | Info}
- **Detection:** criterio deterministico sul metadata raccolto dallo scanner
- **Rationale:** perché è un problema
- **Fix:** azione correttiva consigliata
- **Auto-fix:** ✅ safe (applicabile senza approval esplicito) | ⚠️ richiede approval | ❌ manuale
```

---

## Performance

### BPA-P-001 — Evitare relazioni bidirezionali

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** relazioni con `crossFilteringBehavior == "bothDirections"`
- **Rationale:** le bidirezionali aumentano la complessità di filtro, possono causare ambiguità e degradano le performance. Spesso nascondono un problema di modellazione (mancanza di bridge o dimensione condivisa).
- **Fix:** convertire a `singleDirection` e, se serve il filtro inverso in contesti specifici, usare `CROSSFILTER()` in DAX nelle misure che lo richiedono.
- **Auto-fix:** ⚠️ richiede approval (impatto funzionale)

### BPA-P-002 — Evitare relazioni many-to-many

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** relazioni con cardinalità `manyToMany`
- **Rationale:** peggiori performance e semantica ambigua. Spesso sintomo di chiavi non adeguate o dimensione mancante.
- **Fix:** introdurre una bridge table con chiavi single, oppure creare una dimensione condivisa con cardinalità `oneToMany` su entrambi i lati.
- **Auto-fix:** ❌ manuale (richiede rivedere il modello)

### BPA-P-003 — Disabilitare Auto Date/Time

- **Categoria:** Performance
- **Severità:** 🔴 Error
- **Detection:** `model.properties.autoDateTimeEnabled == true` (o equivalente su livello dataset)
- **Rationale:** genera automaticamente tabelle date nascoste per ogni colonna data, aumentando la dimensione del modello e creando modelli "sporchi". Una Date table esplicita è sempre preferibile.
- **Fix:** disabilitare Auto Date/Time e usare una calendar table DAX o M esplicita.
- **Auto-fix:** ✅ safe (impostazione modello)

### BPA-P-004 — Ridurre il numero di colonne calcolate

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** colonne con `type == "calculated"`; soglia di allerta > 5 per tabella fact, > 3 per tabella dim
- **Rationale:** le colonne calcolate occupano memoria come importate ma non beneficiano della compressione VertiPaq ottimale; la stessa logica in Power Query è generalmente più efficiente per il refresh e rende il modello più portabile.
- **Fix:** spostare la logica in Power Query (nuova colonna M) dove possibile.
- **Auto-fix:** ❌ manuale (richiede refactor M)

### BPA-P-005 — Evitare tabelle calcolate quando sostituibili

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** tabelle con partizione `type == "calculated"` che non sono la calendar table dedicata
- **Rationale:** una calculated table ricalcola a ogni refresh e non è portabile verso Dataflow / Lakehouse. È giustificata solo per Calendar e poche eccezioni (bridge generate, statiche).
- **Fix:** valutare se la tabella può essere prodotta in Power Query o a monte.
- **Auto-fix:** ❌ manuale

### BPA-P-006 — Preferire tipi numerici interi a stringa per chiavi

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** colonne usate come `fromColumn`/`toColumn` in relazioni con `dataType == "string"`
- **Rationale:** la cardinalità alta su chiavi stringa è molto più costosa in VertiPaq rispetto a Int64. Le join con chiavi integer sono drasticamente più veloci.
- **Fix:** introdurre surrogate key intere a monte (PQ o sorgente).
- **Auto-fix:** ❌ manuale

### BPA-P-007 — Evitare colonne DateTime quando basta Date

- **Categoria:** Performance
- **Severità:** 🟡 Warning
- **Detection:** colonne con `dataType == "dateTime"` dove la componente oraria è sempre `00:00:00` (richiede query DAX `MIN/MAX` + controllo ora)
- **Rationale:** DateTime ha cardinalità al secondo e compressione peggiore. Date è sufficiente nella maggior parte dei casi di reportistica.
- **Fix:** convertire a `date` in Power Query.
- **Auto-fix:** ⚠️ richiede approval

### BPA-P-008 — Nascondere colonne chiave sorgente

- **Categoria:** Performance
- **Severità:** 🔵 Info
- **Detection:** colonne usate come chiave in relazioni con `isHidden == false`
- **Rationale:** le chiavi tecniche non servono all'utente finale e intasano il field list. Nasconderle rende il modello più pulito e previene aggregazioni scorrette.
- **Fix:** impostare `isHidden = true` sulle colonne chiave.
- **Auto-fix:** ✅ safe

### BPA-P-009 — Evitare alta cardinalità su colonne non necessarie

- **Categoria:** Performance
- **Severità:** 🔵 Info
- **Detection:** colonne stringa con cardinalità > 1M righe distinte (richiede query `DISTINCTCOUNT`)
- **Rationale:** colonne testuali ad altissima cardinalità (es. URL, note libere, GUID) dominano la dimensione del modello. Valutare se servono davvero per analisi o possono essere escluse.
- **Fix:** escludere la colonna dal modello, oppure splitare in componenti a cardinalità inferiore.
- **Auto-fix:** ❌ manuale

### BPA-P-010 — Evitare colonne Double quando basta Decimal Fixed

- **Categoria:** Performance
- **Severità:** 🔵 Info
- **Detection:** colonne numeriche con `dataType == "double"` che rappresentano valori monetari o misure con al massimo 4 decimali
- **Rationale:** Decimal Number Fixed (Currency) comprime meglio e riduce errori di arrotondamento.
- **Fix:** convertire a `decimal` (Fixed Decimal) in Power Query.
- **Auto-fix:** ⚠️ richiede approval

---

## DAX

### BPA-D-001 — Usare DIVIDE al posto di `/`

- **Categoria:** DAX
- **Severità:** 🟡 Warning
- **Detection:** espressioni misure/colonne calcolate che contengono `/` senza `DIVIDE(` nel contesto (regex su TMDL)
- **Rationale:** `DIVIDE` gestisce la divisione per zero in modo nativo (ritorna BLANK) evitando errori in runtime.
- **Fix:** sostituire `A / B` con `DIVIDE(A, B)`.
- **Auto-fix:** ⚠️ richiede approval (rewrite espressione)

### BPA-D-002 — Evitare IFERROR per nascondere errori logici

- **Categoria:** DAX
- **Severità:** 🟡 Warning
- **Detection:** espressioni contenenti `IFERROR(`
- **Rationale:** `IFERROR` maschera errori di logica che sarebbero meglio corretti all'origine. Spesso usato per nascondere divisioni per zero (caso in cui `DIVIDE` è migliore).
- **Fix:** risolvere la causa dell'errore oppure usare funzioni più specifiche (`DIVIDE`, `COALESCE`).
- **Auto-fix:** ❌ manuale

### BPA-D-003 — Misure non dovrebbero referenziare direttamente altre misure senza logica

- **Categoria:** DAX
- **Severità:** 🔵 Info
- **Detection:** misure la cui espressione è esattamente `[AltraMisura]` (alias banali)
- **Rationale:** duplicazione senza valore aggiunto che complica il lineage e genera confusione.
- **Fix:** eliminare l'alias o dargli una logica distintiva, oppure rinominare se l'unico scopo è branding.
- **Auto-fix:** ❌ manuale (l'utente può avere motivi validi)

### BPA-D-004 — Usare SUM per aggregazione singola colonna

- **Categoria:** DAX
- **Severità:** 🟡 Warning
- **Detection:** misure con pattern `SUMX(Tabella, Tabella[Colonna])` o `SUMX(Tabella, [Colonna])` su singola colonna
- **Rationale:** `SUMX` su singola colonna è più lento di `SUM`. `SUMX` è giustificato solo per espressioni tra più colonne (es. `Quantita * Prezzo`).
- **Fix:** sostituire con `SUM(Tabella[Colonna])`.
- **Auto-fix:** ⚠️ richiede approval

### BPA-D-005 — Evitare variabili senza nome descrittivo

- **Categoria:** DAX
- **Severità:** 🔵 Info
- **Detection:** variabili DAX con nomi generici (`VAR x`, `VAR t`, `VAR a`, `VAR temp`)
- **Rationale:** compromettono la leggibilità. Nomi descrittivi rendono le espressioni auto-documentanti.
- **Fix:** rinominare le variabili in modo significativo.
- **Auto-fix:** ❌ manuale

### BPA-D-006 — Filtrare per colonna, non per misura

- **Categoria:** DAX
- **Severità:** 🟡 Warning
- **Detection:** `CALCULATE(..., [Misura] > ...)` dove il predicato è su una misura invece che su una colonna
- **Rationale:** filtrare una misura richiede a CALCULATE di valutarla in ogni contesto di riga, degradando le performance. Filtrare una colonna è drasticamente più efficiente.
- **Fix:** riscrivere il filtro usando la colonna sottostante con `FILTER` se necessario.
- **Auto-fix:** ❌ manuale

### BPA-D-007 — Evitare USERELATIONSHIP su tabelle con RLS

- **Categoria:** DAX
- **Severità:** 🔴 Error
- **Detection:** misure che usano `USERELATIONSHIP` su relazioni che coinvolgono tabelle con ruoli di sicurezza
- **Rationale:** l'interazione tra `USERELATIONSHIP` e RLS può produrre risultati inattesi o violazioni di sicurezza.
- **Fix:** valutare architettura alternativa (relazioni attive, calcoli alternativi).
- **Auto-fix:** ❌ manuale

---

## Modeling

### BPA-M-001 — Modello deve avere una Date Table marcata

- **Categoria:** Modeling
- **Severità:** 🔴 Error
- **Detection:** nessuna tabella con `dataCategory == "Time"` e colonna con `isKey == true` di tipo date
- **Rationale:** senza una Date Table marcata, le funzioni Time Intelligence DAX non funzionano correttamente e l'auto date/time viene attivato come fallback.
- **Fix:** creare o marcare una calendar table (riusare la logica STEP 12 di `SKILL.md` per nuova creazione).
- **Auto-fix:** ⚠️ richiede approval (operazione strutturale)

### BPA-M-002 — Evitare snowflake schema

- **Categoria:** Modeling
- **Severità:** 🟡 Warning
- **Detection:** relazioni dove entrambe le tabelle coinvolte NON sono il fact centrale (cioè una relazione dim→dim)
- **Rationale:** lo snowflake aumenta il numero di join necessari, peggiora le performance e complica la DAX. Lo star schema è lo standard Power BI.
- **Fix:** denormalizzare le dimensioni secondarie nella dimensione principale tramite merge in Power Query.
- **Auto-fix:** ❌ manuale (richiede refactor M, proporre codice ma applicazione manuale in PQ Editor)

### BPA-M-003 — Relazioni inattive giustificate

- **Categoria:** Modeling
- **Severità:** 🔵 Info
- **Detection:** relazioni con `isActive == false`
- **Rationale:** le relazioni inattive sono legittime per scenari `USERELATIONSHIP` (es. role-playing dimensions come OrderDate/ShipDate), ma spesso sono residui di sperimentazione.
- **Fix:** verificare con l'utente se la relazione inattiva ha una misura che la usa; altrimenti eliminarla.
- **Auto-fix:** ⚠️ richiede approval (case-by-case)

### BPA-M-004 — Dimensioni dovrebbero avere chiave univoca

- **Categoria:** Modeling
- **Severità:** 🔴 Error
- **Detection:** tabelle lato "one" di una relazione in cui la colonna chiave ha cardinalità < `COUNTROWS` (duplicati)
- **Rationale:** chiavi duplicate lato dimensione producono blank row automatiche e potenziali join incorretti.
- **Fix:** deduplicare in Power Query o correggere a monte.
- **Auto-fix:** ❌ manuale

### BPA-M-005 — Fact table non dovrebbe avere colonne di tipo dimensionale non normalizzate

- **Categoria:** Modeling
- **Severità:** 🟡 Warning
- **Detection:** colonne stringa su fact table con cardinalità < 1000 distinct values (candidati a estrazione in dimensione)
- **Rationale:** attributi descrittivi sulla fact aumentano la dimensione del modello e impediscono slicer coerenti. Estrarre in dimensione migliora compressione e UX.
- **Fix:** proporre generazione dimensione (riusa logica STEP 13 di `SKILL.md`).
- **Auto-fix:** ⚠️ richiede approval

### BPA-M-006 — Evitare tabelle isolate

- **Categoria:** Modeling
- **Severità:** 🟡 Warning
- **Detection:** tabelle senza nessuna relazione attiva, ad eccezione di tabelle parametri/disconnected legittime (es. tabelle "What-If")
- **Rationale:** tabelle isolate sono spesso residui di test o import non completati.
- **Fix:** collegare tramite relazione, oppure eliminare se non servono.
- **Auto-fix:** ⚠️ richiede approval

---

## Maintenance

### BPA-X-001 — Rimuovere misure inutilizzate

- **Categoria:** Maintenance
- **Severità:** 🔵 Info
- **Detection:** misure il cui nome non compare in nessuna espressione di altre misure / colonne calcolate / tabelle calcolate (scan testuale su tutto il TMDL)
- **Limitation:** Claude NON può verificare l'uso nei report (visual, bookmark, parametri report). Questa detection identifica solo le misure non referenziate *a livello di modello*.
- **Rationale:** misure orfane appesantiscono la manutenzione e confondono gli utenti. Cleanup periodico è consigliato.
- **Fix (consigliato):** spostare in display folder `_ToBeDeleted` come marker per review finale prima di eliminazione.
- **Fix (alternativo):** eliminazione definitiva — sconsigliato senza verifica sui report.
- **Auto-fix:** ⚠️ richiede approval (scelta tra le due opzioni)

### BPA-X-002 — Nascondere colonne tecniche inutilizzate

- **Categoria:** Maintenance
- **Severità:** 🔵 Info
- **Detection:** colonne con `isHidden == false` non usate in: relazioni, sort-by, misure, gerarchie
- **Rationale:** colonne tecniche visibili confondono l'utente finale.
- **Fix:** impostare `isHidden = true`.
- **Auto-fix:** ✅ safe

### BPA-X-003 — Consolidare misure sparse in tabella `Calcs`

- **Categoria:** Maintenance
- **Severità:** 🔵 Info
- **Detection:** misure distribuite su più tabelle (non in una tabella `Calcs` dedicata) in numero > 3 per tabella
- **Rationale:** la convenzione del progetto prevede tutte le misure in una tabella `Calcs` dedicata con colonna placeholder nascosta, per UX più pulita e separazione logica dati/calcoli.
- **Fix:** spostare tutte le misure in `Calcs`. Se `Calcs` non esiste, crearla (calculated table `Calcs = ROW("_", BLANK())` con colonna nascosta).
- **Auto-fix:** ⚠️ richiede approval

### BPA-X-004 — Organizzare misure in display folder standard

- **Categoria:** Maintenance
- **Severità:** 🔵 Info
- **Detection:** misure senza `displayFolder` o con folder non standard (diversi da `Base Measures`, `To Date`, `Previous Period`, `_ToBeDeleted`)
- **Rationale:** convenzione del progetto: tre folder standard per le misure (`Base Measures`, `To Date`, `Previous Period`). Altri folder sono ammessi ma devono essere giustificati.
- **Fix:** proporre riassegnazione folder basata sul pattern della misura (`YTD`/`MTD`/`QTD` → `To Date`; `PY`/`LY` → `Previous Period`; altrimenti `Base Measures`).
- **Auto-fix:** ⚠️ richiede approval

---

## Naming & Formatting

### BPA-N-001 — Format string obbligatorio sulle misure

- **Categoria:** Naming & Formatting
- **Severità:** 🟡 Warning
- **Detection:** misure con `formatString == null` o vuoto
- **Rationale:** senza format string l'utente finale vede numeri grezzi senza separatori migliaia o simbolo valuta, UX scadente.
- **Fix:** applicare format string coerente (es. `"#,0"`, `"#,0.00"`, `"€ #,0.00"`, `"0.0%"`) in base al tipo semantico.
- **Auto-fix:** ✅ safe (applicare default `"#,0.00"` per numeriche, `"0.0%"` per misure con `%` nel nome)

### BPA-N-002 — Format string sulle colonne data

- **Categoria:** Naming & Formatting
- **Severità:** 🔵 Info
- **Detection:** colonne con `dataType == "dateTime"` o `"date"` senza `formatString`
- **Rationale:** senza formato esplicito le date vengono visualizzate secondo locale del client, creando inconsistenze.
- **Fix:** applicare `"dd/MM/yyyy"` o standard aziendale.
- **Auto-fix:** ✅ safe

### BPA-N-003 — Nomi oggetti senza spazi in testa/coda

- **Categoria:** Naming & Formatting
- **Severità:** 🔴 Error
- **Detection:** nomi di tabelle/colonne/misure con `name != name.strip()`
- **Rationale:** spazi invisibili causano errori difficili da diagnosticare in DAX e filtri.
- **Fix:** rinominare rimuovendo spazi in testa/coda.
- **Auto-fix:** ✅ safe

### BPA-N-004 — Misure non devono condividere nome con colonne

- **Categoria:** Naming & Formatting
- **Severità:** 🟡 Warning
- **Detection:** esiste misura con lo stesso nome di una colonna (anche su tabelle diverse)
- **Rationale:** ambiguità nei riferimenti DAX e nell'autocompletamento. Best practice: usare prefisso `[Nome]` per misure sempre, `Tabella[Colonna]` per colonne.
- **Fix:** rinominare la misura aggiungendo prefisso o suffisso distintivo.
- **Auto-fix:** ⚠️ richiede approval

### BPA-N-005 — Evitare caratteri ambigui nei nomi

- **Categoria:** Naming & Formatting
- **Severità:** 🔵 Info
- **Detection:** nomi contenenti `'`, `"`, caratteri Unicode invisibili, doppi spazi
- **Rationale:** possono causare problemi di escaping in DAX e M.
- **Fix:** rinominare con caratteri semplici (lettere, numeri, spazi singoli, underscore).
- **Auto-fix:** ⚠️ richiede approval

### BPA-N-006 — Separatore migliaia su colonne numeriche

- **Categoria:** Naming & Formatting
- **Severità:** 🔵 Info
- **Detection:** colonne numeriche (non chiavi) visibili senza separatore migliaia nel format
- **Rationale:** leggibilità sui visual tabellari.
- **Fix:** applicare format `"#,0"` o `"#,0.00"`.
- **Auto-fix:** ✅ safe

---

## Output atteso dallo scanner per la valutazione regole

Per valutare queste regole, lo scanner deve produrre una struttura dati con almeno questi campi (vedi `model-scanner.md` per lo schema completo):

```yaml
model:
  autoDateTimeEnabled: bool
  datasetName: str
tables:
  - name: str
    type: "import" | "calculated" | "directQuery"
    source: str       # connector descrittivo
    isHidden: bool
    dataCategory: str | null
    rowCount: int | null
    columns:
      - name: str
        dataType: str
        type: "data" | "calculated"
        isHidden: bool
        isKey: bool
        formatString: str | null
        cardinality: int | null
    measures:
      - name: str
        expression: str
        displayFolder: str | null
        isHidden: bool
        formatString: str | null
relationships:
  - fromTable: str
    fromColumn: str
    toTable: str
    toColumn: str
    cardinality: "oneToOne" | "oneToMany" | "manyToMany"
    crossFilteringBehavior: "singleDirection" | "bothDirections"
    isActive: bool
```

## Convenzioni di output violazioni

Ogni violazione rilevata deve essere strutturata così:

```yaml
ruleId: "BPA-P-001"
severity: "Warning"
object:
  type: "relationship" | "table" | "column" | "measure" | "model"
  path: "Sales → Date via OrderDate"
message: "Relazione bidirezionale rilevata"
fix: "Convertire a singleDirection e usare CROSSFILTER() in DAX dove necessario"
autoFix: "requires_approval"
```

Questa struttura viene consumata da `audit-report.md` per la sezione "Violazioni Best Practice" e da `refactor-actions.md` per le azioni correttive.
