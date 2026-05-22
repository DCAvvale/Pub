# Audit Report Template

> 🛑 **Se stai leggendo questo file mentre stai per generare un report di audit:**
> leggilo INTEGRALMENTE prima di scrivere qualsiasi cosa nel file di output. Le 9 sezioni
> sono obbligatorie nell'ordine indicato. I diagrammi mermaid (`flowchart` Data Lineage e
> `erDiagram` relazioni) sono parte del deliverable, non opzionali. Il flag Redaction PII
> va chiesto all'utente PRIMA di iniziare la scrittura. Saltare sezioni o improvvisare la
> struttura "perché si conosce il dominio" produce report sotto-standard che l'utente
> finale potrebbe accettare senza accorgersi delle mancanze — è un errore grave da evitare.

Template e convenzioni per la generazione del report AS-IS in Markdown. Usato da `audit-existing-model.md` nello STEP A4.

## Scopo

Definire struttura, sezioni e formattazione del documento di audit che Claude produce a partire dai dati raccolti da `model-scanner.md` e dalle violazioni rilevate da `best-practices.md`.

## File di output

Percorso: `{CartellaOutput}\audit_AS-IS_{DatasetName}_{YYYY-MM-DD}.md`

`{CartellaOutput}` è la cartella scelta dall'utente in STEP A4 di `audit-existing-model.md`.
`{DatasetName}` è ricavato da `scanMetadata.datasetName` (sanitizzato: spazi → underscore, rimuovere caratteri non filesystem-safe).

Al termine, chiamare `present_files` per renderlo scaricabile dall'utente.

## Struttura del report

Il report segue questo ordine fisso di 9 sezioni. Ogni sezione deve essere presente anche se vuota (in quel caso riportare nota esplicita, es. "Nessuna relazione bidirezionale rilevata").

---

### Sezione 1 — Executive Summary

**Scopo:** dare all'utente una visione d'insieme in < 30 secondi di lettura.

**Formato:**

```markdown
# Audit Modello Power BI — {DatasetName}

**Data scan:** {scanTimestamp}
**Istanza:** localhost:{port}
**Durata scan:** {scanDurationSeconds}s
**Modalità:** {Scan completo | Scan rapido}

## Executive Summary

| Metrica | Valore |
|---------|--------|
| Tabelle totali | {N} |
| └ Fact | {N} |
| └ Dimensioni | {N} |
| └ Calendar | {N} |
| └ Calculated | {N} |
| └ Disconnesse | {N} |
| Colonne totali | {N} |
| └ di cui calcolate | {N} |
| Misure totali | {N} |
| └ di cui inutilizzate (modello) | {N} |
| Relazioni | {N} |
| └ bidirezionali | {N} |
| └ inattive | {N} |
| Violazioni best practice | {N} |
| └ 🔴 Error | {N} |
| └ 🟡 Warning | {N} |
| └ 🔵 Info | {N} |

## Stato generale

{Frase sintetica automatica basata sui conteggi, es:}
- Se 0 Error e < 5 Warning: "Modello in buono stato, piccoli interventi di rifinitura consigliati."
- Se Error presenti: "⚠️ Rilevate {N} violazioni critiche che richiedono intervento prioritario."
- Se > 15 Warning: "Modello con margini significativi di ottimizzazione."
```

---

### Sezione 2 — Inventario tabelle

**Formato:** tabella markdown con tutte le tabelle, una riga per tabella.

```markdown
## 2. Inventario tabelle

| Tabella | Ruolo | Tipo | Sorgente | Righe | Colonne | Note |
|---------|-------|------|----------|-------|---------|------|
| Sales | Fact | Import | Dataflow: SalesDF | 1,250,430 | 18 | |
| Customer | Dim | Import | SQL Server: DWH | 42,100 | 12 | |
| Date | Calendar | Calculated | DAX CALENDAR | 3,653 | 14 | Date Table marcata ✅ |
| _Parameters | Disconnected | Import | Excel locale | 5 | 2 | ⚠️ Isolata, verificare uso |
```

**Regole di rendering:**
- Ordine righe: prima Fact, poi Calendar, poi Dim (ordine alfabetico), poi Bridge, poi Calculated, poi Disconnected.
- Colonna "Note" evidenzia tabelle problematiche con emoji (⚠️ per isolate, ❌ per scan error).
- Nascondi colonna "Note" se nessuna tabella ha note.
- Numeri con separatore migliaia.

**Dopo la tabella, aggiungere le sezioni di dettaglio:**

```markdown
### Tabelle con errori di scan

{Se presenti, elencarle con il messaggio di errore. Altrimenti omettere.}

### Data Lineage

> 💡 *Per visualizzare il diagramma aprire [mermaid.live](https://mermaid.live) e incollare
> il codice, oppure usare un editor Markdown con supporto Mermaid (es. VS Code + estensione).*

```mermaid
flowchart LR
    subgraph Sorgenti
        {un nodo per ogni sorgente distinta, es:}
        SQL1[(SQL Server\n{server}\n{database})]
        CALC[DAX Calculated]
        EXCEL[Excel locale]
    end
    subgraph Modello
        {un nodo per ogni tabella visibile}
    end
    {archi: SorgenteName -->|{nome view/tabella/query}| NomeTabella}
```

**Regole di costruzione del diagramma lineage:**
- Raggruppare le tabelle per sorgente distinta (stesso server+database = stesso nodo).
- Il label sull'arco è il nome della view/tabella SQL o del file Excel; ometterlo se è identico al nome della tabella nel modello.
- Le tabelle Calculated (DAX) puntano al nodo `DAX Calculated`.
- Le tabelle Disconnected e Parameter vengono incluse nel grafo con la loro sorgente reale.
- Se ci sono > 20 tabelle, mostrare solo Fact + Calendar nel grafo e aggiungere nota: *"Le dimensioni sono omesse per leggibilità — vedi inventario sopra per il dettaglio completo."*

### Dettaglio sorgenti tabelle Import

Per ogni tabella Import con `sourceExpression` disponibile, riportare:

#### `{NomeTabella}`

**Descrizione funzionale:** {sempre presente — generata analizzando la sourceExpression:
descrivere in linguaggio naturale cosa fa la query: da dove legge, eventuali filtri,
join, trasformazioni principali applicati in Power Query. Es: "Legge la view
`manufacturing_prod_views_stops` dal database SQL `manufacturing_prod` senza filtri.
Rinomina le colonne `machine_code` → `Cod Macchina` e converte `stop_time` in DateTime."}

**Query M:**
```m
{sourceExpression completa se ≤ 20 righe}
```
{Se > 20 righe:}
```m
{prime 20 righe}
...
```
> *Query completa visibile in Power Query Editor (Power BI Desktop → Transform Data → seleziona `{NomeTabella}`).*

{Omettere questa sottosezione per tabelle Calculated (DAX) — già documentate in Sezione 3.}
{Omettere per tabelle senza sourceExpression nel metadata di scan.}
```

---

### Sezione 3 — Power Query vs DAX

**Scopo:** evidenziare logica in DAX che potrebbe stare in PQ.

```markdown
## 3. Power Query vs DAX

### Tabelle calcolate ({N})

{Per ogni tabella calculated (esclusa Calendar se riconosciuta):}

#### `NomeTabella`

**Espressione:**
```dax
{prime 20 righe dell'espressione, con "..." se più lunga}
```

**Raccomandazione:** {automatica in base a pattern — es. "Valutare spostamento in Power Query o Dataflow per migliorare refresh performance e portabilità."}

### Colonne calcolate ({N})

| Tabella | Colonna | Espressione | Raccomandazione |
|---------|---------|-------------|-----------------|
| Sales | Margin | `Sales[Price] - Sales[Cost]` | 🟡 Candidata PQ (calcolo deterministico su colonne stessa riga) |
| Customer | FullName | `Customer[First] & " " & Customer[Last]` | 🟡 Candidata PQ |

{Se 0 colonne calcolate, mostrare "Nessuna colonna calcolata rilevata ✅"}
```

---

### Sezione 4 — Relazioni

```markdown
## 4. Relazioni

### Mappa relazioni ({N} attive, {N} inattive)

| From | Cardinalità | To | Direzione | Stato | Note |
|------|-------------|----|-----------| ----- |------|
| Sales[CustomerKey] | *:1 | Customer[CustomerKey] | → | ✅ Attiva | |
| Sales[OrderDateKey] | *:1 | Date[DateKey] | → | ✅ Attiva | |
| Sales[ShipDateKey] | *:1 | Date[DateKey] | → | ⏸️ Inattiva | Role-playing (USERELATIONSHIP?) |
| Customer[RegionKey] | *:1 | Region[RegionKey] | ↔ | ✅ Attiva | ⚠️ Bidirezionale |
| Customer[CountryKey] | *:1 | Country[CountryKey] | → | ✅ Attiva | ❄️ Snowflake (dim→dim) |

### ER Diagram

> 💡 *Per visualizzare il diagramma aprire [mermaid.live](https://mermaid.live) e incollare
> il codice, oppure usare un editor Markdown con supporto Mermaid (es. VS Code + estensione).*

```mermaid
erDiagram
    {per ogni relazione attiva, una riga con:}
    {notazione cardinalità:}
    {  one-to-many  →  FromTable }o--|| ToTable : "colonna"}
    {  many-to-one  →  FromTable ||--o{ ToTable : "colonna"}
    {  one-to-one   →  FromTable ||--|| ToTable : "colonna"}
    {  many-to-many →  FromTable }o--o{ ToTable : "colonna"}
    {  bidirezionale: aggiungere " ↔" al label della relazione}
    {  inattiva: aggiungere " (inattiva)" al label}

    Sales ||--o{ Customer : "CustomerKey"
    Sales ||--o{ Date : "OrderDateKey"
    Sales ||--o{ Date : "ShipDateKey (inattiva)"
    Customer }o--o{ Region : "RegionKey ↔"
```

**Regole di costruzione del diagramma ER:**
- Includere tutte le relazioni (attive + inattive).
- I nomi tabella nell'ER non possono contenere spazi o caratteri speciali: sostituire con underscore (`oee3/2` → `oee3_2`, `Fermi Produttivi` → `Fermi_Produttivi`). Il label sull'arco mostra il nome colonna originale.
- Se ci sono > 30 relazioni, includere solo le relazioni delle tabelle Fact e omettere quelle tra sole dimensioni. Aggiungere nota: *"Relazioni tra dimensioni omesse per leggibilità — vedi mappa sopra per il dettaglio completo."*

### Relazioni bidirezionali

{Se presenti, elencare con motivazione per ciascuna e raccomandazione BPA-P-001. Se nessuna: "Nessuna relazione bidirezionale ✅"}

### Relazioni inattive

{Per ognuna, verificare se una misura usa USERELATIONSHIP con quella coppia di colonne. In caso positivo marcarla come "Giustificata (usata in USERELATIONSHIP da misure: X, Y)". Altrimenti segnalare come candidata rimozione.}

### Snowflake rilevati

{Lista delle catene snowflake, es:}
- `Customer → Country → Continent` — raccomandazione: denormalizzare Country e Continent in Customer.
```

---

### Sezione 5 — Misure

```markdown
## 5. Misure

### Distribuzione per tabella

| Tabella | N misure | Note |
|---------|----------|------|
| Calcs | 42 | ✅ Tabella misure dedicata |
| Sales | 8 | ⚠️ Misure sparse — candidate a consolidamento in Calcs |

### Distribuzione per display folder

| Folder | N misure |
|--------|----------|
| Base Measures | 18 |
| To Date | 12 |
| Previous Period | 8 |
| (nessun folder) | 12 |
| Altri folder custom | {elenco} |

### Misure potenzialmente inutilizzate ({N})

> ⚠️ **Limitazione:** questa detection verifica solo che le misure non siano referenziate da altre misure o oggetti del modello. Non può verificare l'uso nei visual dei report. Prima di eliminare, verificare manualmente nei report.

| Misura | Tabella | Folder attuale | Azione consigliata |
|--------|---------|----------------|--------------------|
| Sales Amount Old | Calcs | Base Measures | Spostare in `_ToBeDeleted` |

### Anteprima misure (prime 20)

{Tabella con: Nome, Folder, Format, Descrizione (se presente). Se > 20 misure, nota "... e altre {N} misure"}
```

---

### Sezione 6 — Organizzazione dimensioni e misure

```markdown
## 6. Organizzazione

### Tabella `Calcs` dedicata

{Se esiste: descrivere quante misure contiene, struttura colonna nascosta, etc.}
{Se non esiste: "❌ Nessuna tabella `Calcs` dedicata rilevata. Le misure sono distribuite su {N} tabelle dati."}

### Misure sparse su tabelle dati

{Se presenti: elenco tabelle con misure non-dedicate e conteggi. Raccomandazione BPA-X-003.}

### Folder non standard

{Elenco folder custom. Raccomandazione BPA-X-004 per normalizzazione a `Base Measures` / `To Date` / `Previous Period`.}
```

---

### Sezione 7 — Analisi Star Schema

```markdown
## 7. Analisi Star Schema

### Stato
{Una delle seguenti:}
- ✅ **Star schema pulito** — tutte le dimensioni sono collegate direttamente alle fact, nessuno snowflake.
- ⚠️ **Star schema con eccezioni** — {N} snowflake rilevati (vedi dettaglio sotto).
- ❌ **Snowflake dominante** — {N} catene snowflake, refactor consigliato.

### Fact tables ({N})

{Elenco fact con N righe, N dimensioni collegate.}

### Snowflake chains

{Se presenti, per ogni catena:}

**Chain #1: `Sales → Customer → Country → Continent`**

- **Impatto:** query con slice su Continent devono attraversare 3 join.
- **Refactor proposto:** denormalizzare Country e Continent dentro Customer via merge in Power Query. Query M esemplificativa:
  ```m
  = Table.NestedJoin(Customer, {"CountryKey"}, Country, {"CountryKey"}, "_country", JoinKind.LeftOuter)
  ```

### Many-to-many

{Se presenti, elenco con raccomandazione BPA-P-002.}

### Tabelle disconnesse

{Elenco, con distinzione tra parameter tables legittime e tabelle orfane.}
```

---

### Sezione 8 — Violazioni Best Practice

```markdown
## 8. Violazioni Best Practice

Risultati dell'analisi secondo il catalogo `best-practices.md`.

### Per severità

**🔴 Error ({N})**

| Regola | Oggetto | Messaggio | Fix |
|--------|---------|-----------|-----|
| BPA-P-003 | Modello | Auto Date/Time attivo | Disabilitare nelle opzioni modello |

**🟡 Warning ({N})**

{Idem}

**🔵 Info ({N})**

{Idem}

### Per categoria

{Contatori aggregati:}

| Categoria | Error | Warning | Info | Totale |
|-----------|-------|---------|------|--------|
| Performance | 1 | 3 | 2 | 6 |
| DAX | 0 | 2 | 1 | 3 |
| Modeling | 2 | 1 | 0 | 3 |
| Maintenance | 0 | 0 | 4 | 4 |
| Naming & Formatting | 0 | 1 | 3 | 4 |
```

---

### Sezione 9 — Azioni consigliate (prioritized)

```markdown
## 9. Azioni consigliate

Lista ordinata delle azioni raggruppate per categoria di intervento, ordinate per priorità (Error prima, poi Warning, poi Info).

> Per applicare le azioni, richiamare il flusso refactor con il comando: **"procedi con le azioni correttive"**.

### Priorità 1 — Error

1. **Disabilitare Auto Date/Time** (BPA-P-003)
2. **Creare Date Table marcata** (BPA-M-001)

### Priorità 2 — Warning strutturali

3. **Denormalizzare snowflake `Customer → Country → Continent`** (BPA-M-002)
4. **Convertire relazione bidirezionale `Customer ↔ Region`** (BPA-P-001)

### Priorità 3 — Warning performance

5. **Sostituire SUMX con SUM in {N} misure** (BPA-D-004)
6. **Valutare spostamento di {N} colonne calcolate in PQ** (BPA-P-004)

### Priorità 4 — Maintenance

7. **Spostare {N} misure inutilizzate in folder `_ToBeDeleted`** (BPA-X-001)
8. **Consolidare {N} misure sparse nella tabella `Calcs`** (BPA-X-003)
9. **Normalizzare display folder a standard `Base Measures` / `To Date` / `Previous Period`** (BPA-X-004)

### Priorità 5 — Formatting & Naming

10. **Applicare format string a {N} misure senza format** (BPA-N-001)
11. **Nascondere {N} colonne chiave tecniche** (BPA-P-008)

---

*Report generato automaticamente dalla skill `pbi-crea-semantic-model` — audit mode.*
```

---

## Modalità Redaction PII (opzionale)

Quando l'utente attiva la modalità `{RedactPII} = true` (chiesta a STEP A4 di
`audit-existing-model.md`), il rendering del report applica la sostituzione
descritta sotto a **tutti i nomi di colonna e nomi di misura** in **tutte le
sezioni del report**.

### Cosa viene redacted

Solo gli **identificatori** (nomi di colonne / nomi di misure) il cui nome
matcha uno dei pattern PII elencati sotto. **Non** vengono redacted:
- Nomi di tabelle (rimangono visibili)
- Server names, database names, URL SharePoint (visibili — sono infrastruttura)
- Espressioni DAX e query M (rimangono visibili — la business logic è il
  punto del report; se il pattern PII appare nell'espressione, sostituire
  inline solo il riferimento alla colonna)

### Pattern di detection (case-insensitive, match parziale)

| Pattern (regex su nome) | Sostituzione |
|---|---|
| `codice.?fisc\|cod.?fisc\|c\.?f\.?\|fiscal.?code\|tax.?code\|tax.?id` | `[REDACTED-CF]` |
| `iban\|bic\|swift` | `[REDACTED-IBAN]` |
| `email\|e.?mail\|posta.?elettronica` | `[REDACTED-EMAIL]` |
| `phone\|tel\b\|telefono\|cellul\|mobile\|numero.?telefon` | `[REDACTED-PHONE]` |
| `password\|pwd\|secret\|token\|api.?key\|access.?key` | `[REDACTED-SECRET]` |
| `stipendio\|salary\|salario\|retribuzion\|compenso\|paga` | `[REDACTED-SALARY]` |
| `address\|indirizzo\|via\b\|civico\|cap\|zip\|postal.?code` | `[REDACTED-ADDRESS]` |
| `birth.?date\|date.?of.?birth\|data.?nascita\|dob\b` | `[REDACTED-DOB]` |
| `ssn\|social.?security\|nin\b` | `[REDACTED-SSN]` |
| `credit.?card\|cc.?number\|carta.?credito\|pan\b` | `[REDACTED-CC]` |
| `partita.?iva\|p\.?iva\|vat.?number\|vat.?id` | `[REDACTED-VAT]` |

### Formato di redaction

Sostituire l'identificatore mantenendo la qualifica della tabella:

| Originale | Redacted |
|---|---|
| `Customer[Email]` | `Customer[REDACTED-EMAIL]` |
| `Sales[CustomerEmail]` | `Sales[REDACTED-EMAIL]` |
| `Employee[Stipendio_Lordo]` | `Employee[REDACTED-SALARY]` |
| `Misura: SUM(Sales[Importo])` (no match) | invariato |

### Header del report quando RedactPII = true

In testa al report (subito sotto il titolo), aggiungere:

```markdown
> 🔒 **Redaction PII attiva** — i nomi di colonne/misure che matchano pattern
> PII sono stati sostituiti con `[REDACTED-{tipo}]`. La detection è euristica
> basata sui nomi e NON sostituisce una review da parte del data steward.
> Potrebbero esserci falsi negativi (colonne PII con nomi non standard) o
> falsi positivi (es. una colonna `email_template` non è PII).
```

### Quando RedactPII = false (default)

Comportamento attuale: nessuna sostituzione, tutti i nomi visibili.

---

## Convenzioni di rendering

### Emoji semaforo

- 🔴 Error
- 🟡 Warning
- 🔵 Info
- ✅ OK / positivo
- ⚠️ Attenzione
- ❌ Negativo / assente
- ❄️ Snowflake
- ⏸️ Inattivo
- ↔️ Bidirezionale
- → Mono-direzionale

### Formattazione numerica

- Numeri interi > 999: separatore migliaia con virgola o spazio (coerente in tutto il report)
- Percentuali: `12.3%` con 1 decimale

### Troncamento

- Espressioni DAX > 20 righe: troncare con `...` e nota "espressione completa visibile in Power Query Editor (Transform Data → seleziona la tabella)"
- Query M > 20 righe: troncare con `...`, aggiungere sempre la **descrizione funzionale** in linguaggio naturale, poi la nota su Power Query Editor
- Elenchi > 20 elementi: mostrare top 20 + "... e altri N elementi"

### Sezioni vuote

Se una sezione non ha contenuto (es. nessuna relazione bidirezionale), includerla comunque con una nota breve:

> *Nessuna relazione bidirezionale rilevata ✅*

### Link alle regole BPA

Ogni citazione di regola BPA (es. `BPA-P-001`) idealmente include un riferimento ancorato alla sezione di `best-practices.md`. In pratica, nel report MD standalone, basta il codice — l'utente che vuole dettaglio apre la reference.

## Dopo la generazione

1. Salvare il file in `{CartellaOutput}\audit_AS-IS_{DatasetName}_{YYYY-MM-DD}.md`.
2. Chiamare `present_files` per renderlo scaricabile.
3. Mostrare all'utente un riepilogo testuale con i principali contatori (da Sezione 1) e proporre di procedere con le azioni correttive.
