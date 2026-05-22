# Reference — Storage Mode: Direct Lake

Questo reference copre il flusso Direct Lake end-to-end: creazione guidata del
modello in Fabric con un breve passaggio UI da parte dell'utente (~30 secondi),
seguito da tutte le operazioni di modeling automatizzate via MCP — classificazione
Fact/Dim, referential integrity check, creazione relazioni, validazione, alert
Star Schema, calendario DAX, tabella Calcs con misure, memorizzazione dell'ID
del semantic model.

Al termine di questi step il modello esiste nel workspace Fabric, la connessione
MCP è attiva, le tabelle sono validate, le relazioni sono create (o esplicitamente
scartate per motivi di integrità referenziale), calendario e misure sono
applicate e l'ID del semantic model è memorizzato come variabile per step o
tool successivi.

**Principio guida**: minimizza le domande all'utente. Quando un'informazione può
essere dedotta dai metadata del modello o da pattern di naming, NON chiederla —
deducila e mostra il risultato come "ecco cosa ho fatto, confermi?".

---

## STEP D1 — Raccolta informazioni essenziali

Chiedi in un solo turno le tre informazioni minime:

```
Per creare il modello in Direct Lake mi servono:

1. Nome del workspace Fabric di destinazione:
2. Nome esatto del Lakehouse (o Warehouse):
3. Nome che vuoi dare al semantic model:
```

Salva come {WorkspaceName}, {LakehouseName}, {NomeProgetto}.

Niente checklist di prerequisiti: se mancano permessi, tenant setting o capacita,
l'errore arrivera al primo tentativo di connessione MCP e lo gestiremo allora.

---

## STEP D2 — Guida alla creazione del modello "seme" (~30 secondi utente)

Dopo il sunset dei default semantic model (settembre/novembre 2025), il modo piu
affidabile per creare un modello Direct Lake e farlo generare a Fabric dalla UI.
Fabric gestisce automaticamente lo schema delle colonne delle tabelle Delta,
evitando errori di tipizzazione.

### Flavor: Direct Lake on OneLake (default)

Il modello viene creato in **Direct Lake on OneLake**, che è il flavor raccomandato
da Microsoft: performance migliori, supporto nativo per composite model (essenziale
per gli step successivi che aggiungono Calendar e la tabella Calcs in import storage),
e possibilità di estendere il modello con tabelle da più Lakehouse/Warehouse.

La shared expression sara `AzureStorage.DataLake` (non `DatabaseQuery`/SQL).

### Istruzioni per l'utente

Spiega all'utente esattamente cosa fare:

```
Ho bisogno di un modello-seme creato da Fabric per gestire automaticamente
lo schema delle tabelle Delta. Seguimi:

1. Apri il workspace "{WorkspaceName}" in Fabric (app.fabric.microsoft.com)
2. Clicca sul Lakehouse "{LakehouseName}" per aprirlo (vista "Lakehouse", NON SQL endpoint)
3. Nel ribbon in alto clicca "New semantic model"
4. Nella dialog:
   - Name: {NomeProgetto}
   - Workspace: {WorkspaceName}
   - Seleziona TUTTE le tabelle che ti servono nel modello
   - Clicca "Confirm"

Fabric creera il modello in Direct Lake on OneLake con le tabelle selezionate.
Fammi sapere quando e pronto (ci vogliono pochi secondi).
```

Aspetta un messaggio di conferma dell'utente ("fatto", "ok", "pronto", ecc.).

### Caso edge: Direct Lake on SQL

Se l'utente chiede esplicitamente Direct Lake on SQL (tipicamente per usare RLS
definito a livello di SQL analytics endpoint con delegated identity, o per avere
fallback automatico a DirectQuery), cambia le istruzioni cosi:

```
2. Apri il Lakehouse e in alto a destra passa alla vista "SQL analytics endpoint"
3. Nel ribbon clicca "Reporting" → "New semantic model"
4. (resto identico)
5. Nella dialog Direct Lake flavor, scegli "Direct Lake on SQL endpoints"
```

In questo caso il modello sarà limitato a tabelle di un singolo Fabric item e la
shared expression sarà `DatabaseQuery`. Il resto del reference (STEP D3-D9) funziona
identico in entrambi i flavor.

### Verifica post-creazione (facoltativa)

Se vuoi confermare il flavor dopo la creazione, dopo lo STEP D3 puoi ispezionare
la shared expression nel TMDL esportato:
- `AzureStorage.DataLake` → Direct Lake on OneLake ✓
- `DatabaseQuery` / `Sql.Database` → Direct Lake on SQL

---

## STEP D3 — Connessione MCP ed export TMDL

*Senza chiedere nulla all'utente*, esegui:

1. `connection_operations ConnectFabric`:
   ```
   operation: ConnectFabric
   workspaceName: {WorkspaceName}
   semanticModelName: {NomeProgetto}
   ```
   Al primo utilizzo compare un prompt di autenticazione Entra ID — l'utente lo
   completa con le stesse credenziali usate in Fabric.

2. `database_operations ExportTMDL`:
   ```
   operation: ExportTMDL
   tmdlExportOptions:
     maxReturnCharacters: -1
   ```

3. Conserva l'output TMDL come riferimento per gli step successivi.

Se la connessione fallisce, diagnostica in base al messaggio:
- `Model not found` → l'utente ha digitato male il nome, o non ha ancora completato
  lo STEP D2. Chiedi di verificare il nome esatto nel workspace.
- `Unauthorized` → manca il tenant setting, oppure l'utente non ha permessi sul
  workspace. Spiega cosa deve chiedere al suo admin Fabric.
- `Workspace not found` → nome workspace errato.

---

## STEP D4 — Classificazione automatica Fact/Dimension

Analizza il TMDL esportato e applica questa euristica su ogni tabella — **senza
chiedere nulla all'utente**:

### Regole di classificazione (in ordine di priorita)

1. **Pattern di naming espliciti** (case-insensitive):
   - `Fact*`, `F_*`, `fct_*`, `FT_*`, `*_Fact`, `*_F` → **Fact**
   - `Dim*`, `D_*`, `dim_*`, `DT_*`, `*_Dim`, `*_D` → **Dimension**
   - Nome contiene `Calendar`, `Calendario`, `Date`, `Time` → **Dimension (candidata Date Table)**

2. **Se nessun pattern di naming corrisponde**, analizza la struttura:
   - Tabella con ≥2 colonne chiave (suffissi `ID`, `Key`, `Cod`, `Code`, `FK`) e
     almeno una colonna numerica aggregabile → **Fact**
   - Tabella con 1 colonna chiave + molte colonne descrittive string → **Dimension**
   - Conteggio righe elevato rispetto alla media → probabile **Fact**
   - Conteggio righe basso + bassa cardinalita chiavi → probabile **Dimension**

3. **Fallback**: se ambiguo, classifica in base a dove la chiave appare in altre
   tabelle. Se `{X}ID` appare in molte tabelle, `{X}ID` e una FK → la tabella che
   la contiene come PK e una **Dimension**.

### Presentazione della classificazione

Mostra una sola tabella con tutte le classificazioni:

```
Ho classificato le tabelle cosi:

Fact:
  - Sales         (2.3M righe, 8 FK, 3 metriche numeriche)
  - OrderLines    (5.1M righe, 5 FK, 4 metriche numeriche)

Dimension:
  - DimCustomer   (142k righe)
  - DimProduct    (8.4k righe)
  - DimStore      (127 righe)
  - DimDate       (3.6k righe — candidata Date Table)

Confermi? Se devi cambiare qualcosa, dimmi solo cosa (es. "Sales e una dimensione").
```

### Gestione conferma

- Se l'utente risponde "sì/ok/confermo/procedi" → prosegui allo STEP D5
- Se l'utente specifica cambiamenti → applicali e mostra la nuova classificazione
  una seconda volta per conferma finale
- Se ci sono tabelle in eccesso che l'utente vuole escludere dal modello, NON
  rimuoverle dal semantic model Fabric (le avrebbe rimosse nello STEP D2 se non
  le voleva); marcale semplicemente come "escluse dalle relazioni e misure"

---

## STEP D5 — Referential Integrity Check (critico per Direct Lake)

Questo step e specifico di Direct Lake e va eseguito **prima** di creare qualsiasi
relazione. In import mode si puo "pulire" il dato a monte via Power Query; in Direct
Lake no — quindi ogni orfano produce blank nei visual.

### Fase 1 — Rileva relazioni candidate

Analizza le colonne di ogni Fact e identifica FK candidate:
- Colonne con nome identico a una colonna PK di una Dimension
- Colonne con suffisso `ID`, `Key`, `Cod`, `Code`, `FK` che matchano pattern nome
  Dimension (es. `CustomerID` in Fact → `DimCustomer.CustomerID`)
- Colonne con stesso data type della PK di una Dimension

Costruisci la lista di coppie candidate `(Fact.FK, Dim.PK)`.

### Fase 2 — Esegui check di integrita referenziale via DAX

*Senza interazione utente*, per ogni coppia candidata esegui via
`dax_query_operations Execute`:

```dax
EVALUATE
VAR FactKeys   = DISTINCT('{Fact}'[{FK}])
VAR DimKeys    = DISTINCT('{Dim}'[{PK}])
VAR Orfani     = EXCEPT(FactKeys, DimKeys)
VAR NumOrfani  = COUNTROWS(Orfani)
VAR RigheImpattate =
    CALCULATE(COUNTROWS('{Fact}'), '{Fact}'[{FK}] IN Orfani)
VAR TotRighe = COUNTROWS('{Fact}')
RETURN
    ROW(
        "Relazione",      "{Fact}.{FK} -> {Dim}.{PK}",
        "ValoriOrfani",   NumOrfani,
        "RigheImpattate", RigheImpattate,
        "PercImpatto",    DIVIDE(RigheImpattate, TotRighe)
    )
```

Aggrega i risultati in una tabella unica.

### Fase 3 — Classifica risultati

Per ogni relazione:
- **Pulita**: `NumOrfani = 0` → crea relazione automaticamente, nessuna domanda
- **Accettabile**: `0 < PercImpatto <= 0.01` (impatto ≤1%) → crea relazione e
  segnala l'impatto minore
- **Problematica**: `PercImpatto > 0.01` → richiede decisione utente

### Fase 4 — Presentazione e decisione utente

Se esistono SOLO relazioni pulite o accettabili: applicale tutte, mostra il
riepilogo e prosegui direttamente allo STEP D6. **Nessuna domanda.**

Se esistono relazioni problematiche, mostra il report consolidato e chiedi UNA
volta sola per TUTTE:

```
Integrita referenziale:

Relazioni pulite (creerò automaticamente, flag RI: ON):
  ✓ Sales.CustomerID    -> DimCustomer.CustomerID     (0 orfani)
  ✓ Sales.ProductID     -> DimProduct.ProductID       (0 orfani)
  ✓ OrderLines.OrderID  -> Sales.OrderID              (0 orfani)

Relazioni con impatto minore (creerò automaticamente, flag RI: OFF):
  ⚠ Sales.StoreID       -> DimStore.StoreID           (3 orfani, 847 righe, 0.04%)

Relazioni problematiche (richiedono la tua decisione):
  ✗ Sales.VendorID      -> DimVendor.VendorID         (52 orfani, 12.340 righe, 31%)
  ✗ OrderLines.PromoID  -> DimPromo.PromoID           (8 orfani, 2.105 righe, 4.1%)

Per le relazioni problematiche, come procedo?
  A) Crea comunque (accetti blank nei visual, flag RI: OFF)
  B) Aggiungi "Unknown" nel Lakehouse (ti dico quali valori inserire; flag RI: ON dopo fix)
  C) Non creare la relazione (Fact e Dim restano scollegate)

Puoi rispondere in modo globale ("tutte A") o granulare ("B per VendorID, A per PromoID").
```

### Fase 5 — Applicazione delle decisioni

- **Opzione A** (o relazioni pulite/accettabili) → crea relazione via
  `relationship_operations Create` con parametri standard (many-to-one, single
  direction)

- **Opzione B** → NON creare ancora la relazione. Genera uno script SQL/PySpark
  che l'utente puo eseguire nel Lakehouse per aggiungere righe "Unknown" nella
  Dim che coprano gli orfani:

  ```sql
  -- Da eseguire nel SQL endpoint del Lakehouse o in un notebook Spark
  INSERT INTO {LakehouseName}.{Dim} ({PK}, {altri_campi})
  SELECT DISTINCT
      f.{FK} AS {PK},
      '(Unknown)' AS {NomeCampo},
      ...
  FROM {LakehouseName}.{Fact} f
  LEFT JOIN {LakehouseName}.{Dim} d ON f.{FK} = d.{PK}
  WHERE d.{PK} IS NULL
  ```

  Spiega all'utente: "Esegui questo script nel Lakehouse, fai un refresh del
  modello, poi dimmi 'fatto' e creo la relazione". Aspetta conferma.

- **Opzione C** → salta, non creare relazione. Registra nel riepilogo finale che
  questa relazione e stata deliberatamente omessa.

### Fase 6 — Imposta il flag "Assume Referential Integrity" sulle relazioni RI-clean

Questo step e deterministico, **senza domande all'utente**. In Direct Lake il flag
`relyOnReferentialIntegrity` attiva ottimizzazioni VertiPaq importanti (inner join
invece di left outer join nel piano di esecuzione), ma produce risultati sbagliati
silenziosamente se impostato su relazioni che hanno orfani.

Regola applicata automaticamente sulle relazioni appena create:

| Origine della relazione                      | relyOnReferentialIntegrity |
|----------------------------------------------|----------------------------|
| Pulita (0 orfani nel check)                  | **true**                   |
| Accettabile (≤1% impatto, opzione automatica)| false                      |
| Opzione A (crea comunque con orfani)         | false                      |
| Opzione B (fix applicato nel Lakehouse)      | **true** (dopo conferma utente) |

Per ogni relazione idonea, esegui `relationship_operations Update` impostando
`relyOnReferentialIntegrity: true`.

### Fase 7 — Refresh del modello

Dopo aver creato le relazioni e impostato i flag RI, esegui `model_operations Refresh`
per fare il framing dei metadata. In Direct Lake questo e rapido (pochi secondi)
perche non ricopia dati.

**→ Checkpoint `/compact`** (esegui subito dopo il refresh):
Usa `/compact` e nel messaggio successivo includi questo blocco di stato:
```
Semantic model Direct Lake "{NomeProgetto}" in corso — workspace "{WorkspaceName}".
Completato: STEP D5 (RI check + {N} relazioni create, flag RI impostati).
Tabelle: Fact=[{lista}], Dim=[{lista}].
Relazioni pulite RI ON: {N} | RI OFF: {N} | omesse: {N}.
Prossimo: STEP D6 — validazione finale + Star Schema check.
```

---

## STEP D6 — Validazione finale + verifica Star Schema

### Fase 1 — Validazione modello e relazioni

1. Valida la connessione a livello modello:
   ```
   EVALUATE ROW("Test", 1)
   ```

2. Per ogni tabella Fact/Dim valida con:
   ```
   EVALUATE TOPN(1, '{NomeTabella}')
   ```

3. Per ogni relazione creata, testa che funzioni correttamente:
   ```dax
   EVALUATE
   SUMMARIZECOLUMNS(
       '{Dim}'[{PK}],
       "Righe Fact", CALCULATE(COUNTROWS('{Fact}'))
   )
   ORDER BY [Righe Fact] DESC
   ```
   Mostra le prime 3 righe per ogni relazione — serve a confermare che il filtro
   si propaga. Se tutte le righe mostrano `BLANK` nel conteggio, la relazione non
   funziona (diagnostica errore).

4. Mostra il riepilogo di validazione:

   ```
   Modello "{NomeProgetto}" pronto in "{WorkspaceName}":

   Tabelle:    {N_Fact} Fact + {N_Dim} Dimension
   Relazioni:  {N_Create} create ({N_Pulite} pulite con RI ON, {N_Accettabili} con impatto
               minore e RI OFF, {N_Manuali} risolte nel Lakehouse, {N_Omesse} omesse)
   Validazione: tutte le tabelle rispondono, tutti i filtri si propagano correttamente
   ```

### Fase 2 — Star Schema check (solo alert)

Usa `ExportTMDL` per rileggere il modello. Regola: le Dimension non devono
avere relazioni verso altre Dimension.

- **Se NON trovi snowflake** → conferma:
  ```
  Struttura Star Schema validata.
  ```
  e prosegui a D7.

- **Se trovi uno o più snowflake** (`DimA → DimB`) → mostra un **alert
  informativo** con la best practice, **senza proporre azioni né aspettare
  decisioni**:

  ```
  ⚠ Rilevato snowflake nel modello:
    - DimProdotto → DimCategoria
    - DimCliente  → DimAreaGeografica

  Best practice: per performance ottimali in Direct Lake e per
  semplicità del modello, è consigliato denormalizzare le dimensioni
  snowflake in un'unica tabella piatta a monte nel Lakehouse
  (join delle Delta table e refresh schema del modello).

  Proseguo comunque con gli step successivi.
  ```

  Nessuna domanda all'utente, nessuna modifica al modello. Prosegui a D7.

---

## STEP D7 — Calendario DAX via MCP

Leggi `calendar.md` per le istruzioni complete su verifica preventiva, template
DAX della Calendar, marcatura come Date Table, colonne standard e gestione
delle relazioni via MCP.

---

## STEP D8 — Tabella Calcs + Misure via MCP

Leggi `measures.md` per le istruzioni complete su struttura della tabella Calcs,
template DAX delle misure e modalità di applicazione via MCP.

---

## STEP D9 — Memorizzazione ID semantic model

Recupera il GUID del semantic model creato in Fabric con una cascata di tentativi
MCP — **zero interazione utente**:

**Tentativo 1** — `database_operations List`:
```
operation: List
connectionName: {connessione attiva dello STEP D3}
```
Scorri il risultato cercando `name = {NomeProgetto}` ed estrai l'ID (GUID).

**Tentativo 2** (fallback) — `database_operations ExportTMSL`:
```
operation: ExportTMSL
tmslExportOptions:
  maxReturnCharacters: -1
  formatJson: true
```
Il JSON esportato contiene il campo `id` al livello database. Estrailo.

**Tentativo 3** (ultimo fallback) — `dax_query_operations Execute`:
```dax
EVALUATE INFO.DATABASES()
```
La colonna `[ID]` del risultato contiene il GUID.

Salva il valore come variabile **`{SemanticModelID}`** — formato
`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. Tienila disponibile per step successivi
o tool che dovessero richiederla (es. creazione PBIP thin report, pubblicazione
report collegati, script di deploy).

Mostra all'utente una riga di conferma:

```
ID semantic model salvato: {SemanticModelID}
```

Se tutti e tre i tentativi falliscono (evento raro), chiedi all'utente:
*"Non sono riuscito a recuperare l'ID automaticamente. Apri il modello in Fabric
e incolla qui l'URL del browser: estrarrò io il GUID dalla parte `/datasets/...`."*

---

## STEP D10 — Crea thin report locale (Live Connection pura)

Il modello remoto è completo. Per permettere all'utente di costruire report in
Power BI Desktop serve un `.pbip` locale come punto d'ingresso. Lo creiamo in
**Live Connection pura**: nessun semantic model locale, solo la parte `.Report`
che si collega al modello remoto.

### Perché Live Connection pura e non composite (DirectQuery)

Per i modelli Direct Lake è il pattern raccomandato:

- **Single source of truth** — relazioni, misure e calendar vivono nel modello
  Fabric; nessun duplicato locale da tenere allineato.
- **Nessun fallback imprevisto** — Direct Lake on OneLake non fa fallback a
  DirectQuery. Passare a composite aggiungerebbe tabelle import con refresh
  schedulati e vanificherebbe il sync automatico del Lakehouse, che è uno dei
  benefici principali di Direct Lake (Microsoft Learn, *Direct Lake overview*).
- **RLS pass-through** — la live connection passa l'identità dell'utente al
  modello remoto; le regole di security definite in Fabric vengono applicate
  senza duplicazioni (Microsoft Learn, *DirectQuery in Power BI*).
- **Thick once, thin everywhere** — più report possono connettersi allo stesso
  modello con definizioni KPI coerenti.

Il composite locale ha senso solo se l'utente deve aggiungere tabelle o misure
che non possono vivere nel modello Fabric. Caso raro in questo workflow: misure,
relazioni e calendar sono già nel modello remoto (STEP D5–D8).

### Fase 1 — Cartella di destinazione (unica domanda)

Chiedi:

```
Il modello "{NomeProgetto}" è pronto in Fabric. Posso creare un .pbip locale
da aprire in Power BI Desktop — thin report con live connection al modello
remoto, zero dati locali.

Dove vuoi salvare il file? Incolla il path completo della cartella.
```

Salva come `{CartellaProgetto}`. Nessun default.

### Fase 2 — Aggancio a connectors.md §6 (Live Connection pura)

I parametri richiesti da §6 sono già tutti noti dagli step precedenti:

| Parametro §6            | Valore                                |
|-------------------------|---------------------------------------|
| Nome workspace          | `{WorkspaceName}`      (da D1)        |
| Nome semantic model     | `{NomeProgetto}`       (da D1)        |
| Modalità                | Live Connection pura (fissata)        |
| GUID del modello        | `{SemanticModelID}`    (da D9)        |

Applica il "Caso Live Connection pura" di §6: nessun file `.tmdl` per tabelle,
relazioni, calendar o misure — tutto vive nel modello remoto.

### Fase 3 — Generazione thin PBIP da template

**Copia verbatim** la cartella `templates/Live Mode/` dentro `{CartellaProgetto}/`.

**Rinomina**:
- `livetemplate.pbip` → `{NomeProgetto}.pbip`
- `livetemplate.Report/` → `{NomeProgetto}.Report/`

**Sostituzioni**:

1. In `{NomeProgetto}.pbip`:
   - `"path": "livetemplate.Report"` → `"path": "{NomeProgetto}.Report"`

2. In `{NomeProgetto}.Report/.platform`:
   - `"displayName": "livetemplate"` → `"displayName": "{NomeProgetto}"`
   - `"logicalId"`: sostituisci con un **nuovo UUID v4** generato al momento

3. In `{NomeProgetto}.Report/definition.pbir` — sostituisci INTERAMENTE la
   `connectionString` con:

   ```
   Data Source=powerbi://api.powerbi.com/v1.0/myorg/{WorkspaceName};initial catalog={NomeProgetto};access mode=readonly;integrated security=ClaimsToken;semanticmodelid={SemanticModelID}
   ```

4. **Elimina** il file `{NomeProgetto}.Report/.pbi/localSettings.json` (NON
   copiarlo dal template). Il file è user-specific e contiene una
   `securityBindingsSignature` legata all'identità di chi ha generato il
   template originale. Desktop lo rigenera automaticamente al primo open con
   l'identità dell'utente corrente.

   Nota: il pattern "file `.pbi/localSettings.json` con contenuto `{}` vuoto"
   usato in `SKILL.md` (ramo Import) vale per il file dentro `.SemanticModel/`,
   che ha schema diverso e accetta oggetto vuoto. Il file dentro `.Report/`
   segue lo schema `item/report/localSettings/1.0.0` che richiede `$schema` e
   `version` obbligatori — scriverlo come `{}` provoca l'errore
   `MissingVersion: ArtifactName: ReportLocalSettings` all'apertura.

**Tutti gli altri file** (`report.json`, `version.json`, `pages.json`,
`page.json`, `StaticResources/...`) si copiano **identici al template**,
page ID incluso.

### Fase 4 — Riepilogo finale

```
Direct Lake end-to-end completato.

  Modello:   "{NomeProgetto}" in workspace "{WorkspaceName}" (Fabric)
  GUID:      {SemanticModelID}
  Storage:   Direct Lake on OneLake
  Thin PBIP: {CartellaProgetto}/{NomeProgetto}.pbip

Apri il .pbip con doppio clic per costruire report in Desktop.
Le modifiche al modello (misure, relazioni, calendar) si fanno in Fabric —
il thin report le vede automaticamente alla prossima apertura.

Importante: Power BI Desktop deve essere connesso con lo stesso account
Microsoft usato per il workspace Fabric. Se apri il .pbip e vedi un
errore di connessione al modello: chiudi il messaggio, clicca "Sign in"
in alto a destra di Desktop, accedi con l'account corretto, poi
riapri il .pbip.
```

---

## Caveat e comportamenti attesi

Tieni a mente (e segnala all'utente se rilevante):

- **Calculated table in composite**: Calendar (STEP D7) è creata come calculated
  table DAX. In un modello Direct Lake diventa automaticamente una tabella in
  **import storage mode** dentro un modello composite. È comportamento
  documentato e supportato.

- **Tabella Calcs**: la tabella placeholder per le misure è sempre import storage
  (è una calc table con `{BLANK()}`). Zero impatto.

- **Relazioni Calendar**: le relazioni create nello STEP D7 attraversano
  Direct Lake ↔ import. Power BI le gestisce via composite model — funzionano
  ma possono richiedere più tempo su dataset molto grandi. Valuta di aggiungere
  le colonne di Calendar direttamente nella Delta table a monte se le
  performance diventano un problema.

- **Nessun refresh tradizionale**: per le tabelle Direct Lake non si fa "Refresh"
  — si fa "framing" (aggiornamento dei metadata che puntano ai Delta files).
  `model_operations Refresh` triggera il framing. Le calc table invece si
  rigenerano quando il modello viene processato.

- **Modifica schema Delta**: se le Delta table sottostanti cambiano (nuove colonne,
  tipi modificati), il modello Direct Lake NON si aggiorna automaticamente. Serve
  un refresh schema manuale dalla UI Fabric o un nuovo ciclo dello skill.

- **Referential integrity nel tempo**: gli orfani rilevati oggi potrebbero cambiare
  domani se vengono aggiunte nuove righe al Lakehouse. Se il modello è critico,
  valuta di schedulare un check periodico del RI (stessa query DAX dello STEP D5).
