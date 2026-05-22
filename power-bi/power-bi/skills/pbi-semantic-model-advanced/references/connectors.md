# Connettori — Parametri e Template M Query

> **Regola di lettura (context window):** Leggi SOLO la sezione del connettore
> richiesto + `## Template relazioni`. Salta le sezioni degli altri connettori.
> Corrispondenza STEP 2 → sezione:
> opzione 1 (SharePoint) → `## 1. SharePoint`
> opzione 2 (Dataflow) → `## 3. Dataflow Fabric / Power BI`
> opzione 3 (Azure SQL / SQL Server) → `## 2. SQL Server`
> opzione 4 (Excel locale) → `## 4. File Excel locale`
> opzione 5 (Altro) → cerca nell'indice qui sotto, poi `## 6` o `## 7` se pertinente

## Opzioni disponibili (STEP 2)

```
Quale connettore vuoi usare?
1. SharePoint (file Excel o CSV)
2. Fabric Warehouse / Lakehouse (endpoint)
3. SQL Server (on-premise)
4. Dataflow Fabric / Power BI
5. Altro (descrivi)
```

---

## 1. SharePoint (file Excel o CSV)

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| URL sito | "URL del sito SharePoint?" | https://azienda.sharepoint.com/sites/dati |
| Tipo file | "I file sono Excel (.xlsx) o CSV (.csv)?" | xlsx |
| Nome file | Per ogni tabella: "Come si chiama il file?" | Vendite.xlsx |
| Nome foglio | Solo Excel: "Come si chiama il foglio?" | Sheet1 |

### Raccomandazione importante
Inserire SOLO il nome del file con estensione, non il percorso completo.
Il connettore SharePoint.Files trova il file automaticamente per nome.

### Template tabella Excel
```
table {NomeTabella}

	partition {NomeTabella}-SP = m
		mode: import
		source =
			let
				Source = SharePoint.Files("{URLSharePoint}", [ApiVersion = 15]),
				NomeFile = Source{[Name="{NomeFile}.xlsx"]}[Content],
				Workbook = Excel.Workbook(NomeFile, null, true),
				Foglio = Workbook{[Item="{NomeFoglio}",Kind="Sheet"]}[Data],
				Intestazioni = Table.PromoteHeaders(Foglio, [PromoteAllScalars=true])
			in
				Intestazioni

```

### Template tabella CSV
```
table {NomeTabella}

	partition {NomeTabella}-SP = m
		mode: import
		source =
			let
				Source = SharePoint.Files("{URLSharePoint}", [ApiVersion = 15]),
				NomeFile = Source{[Name="{NomeFile}.csv"]}[Content],
				Tabella = Csv.Document(NomeFile, [Delimiter=",", Encoding=65001]),
				Intestazioni = Table.PromoteHeaders(Tabella, [PromoteAllScalars=true])
			in
				Intestazioni

```

### Autenticazione
Power BI chiederà le credenziali Microsoft 365 al primo refresh.
Usare l'account aziendale con accesso al sito SharePoint.

---

## 2. SQL Server (on-premise)

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| Server | "Nome o IP del server SQL?" | SQLSERVER01 oppure 192.168.1.10 |
| Database | "Nome del database?" | Vendite_DB |
| Autenticazione | "Windows o SQL Server?" | Windows |
| Schema | "Quale schema? (default: dbo)" | dbo |
| Tabelle | "Quali tabelle vuoi importare?" | dbo.Vendite, dbo.Clienti |

### Raccomandazione importante
- Per autenticazione Windows non servono username/password nel file
- Per SQL Server auth le credenziali si inseriscono al primo avvio, MAI nel file TMDL
- Verifica che il server sia raggiungibile dalla macchina che esegue Power BI Desktop

### Template tabella SQL Server (Windows Auth)
```
table {NomeTabella}

	partition {NomeTabella}-SQL = m
		mode: import
		source =
			let
				Source = Sql.Database("{NomeServer}", "{NomeDatabase}"),
				Schema = Source{[Schema="{NomeSchema}",Item="{NomeTabellaSQL}"]}[Data]
			in
				Schema

```

### Template tabella SQL Server (con query personalizzata)
```
table {NomeTabella}

	partition {NomeTabella}-SQL = m
		mode: import
		source =
			let
				Source = Sql.Database("{NomeServer}", "{NomeDatabase}"),
				Query = Value.NativeQuery(Source,
					"SELECT * FROM {NomeSchema}.{NomeTabellaSQL}",
					null,
					[EnableFolding=true])
			in
				Query

```

---

## 3. Dataflow Fabric / Power BI

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| Workspace ID | "Qual è il Workspace ID?" | a1b2c3d4-1234-5678-abcd-ef0123456789 |
| Dataflow ID | "Qual è il Dataflow ID?" | f9e8d7c6-4321-8765-dcba-210987654321 |
| Nome entità | Per ogni tabella: "Come si chiama l'entità (tabella) nel dataflow?" | Vendite |

### Come trovare Workspace ID e Dataflow ID

**Metodo 1 — dall'URL del browser (il più rapido):**
1. Apri Power BI Service o Microsoft Fabric (app.powerbi.com o app.fabric.microsoft.com)
2. Naviga nel workspace che contiene il dataflow
3. Clicca sul dataflow per aprirlo
4. Leggi l'URL nella barra del browser:

```
https://app.powerbi.com/groups/{WorkspaceID}/dataflows/{DataflowID}

Esempio reale:
https://app.powerbi.com/groups/a1b2c3d4-1234-5678-abcd-ef0123456789/dataflows/f9e8d7c6-4321-8765-dcba-210987654321
                                 ^^^^^^^^ Workspace ID ^^^^^^^^^^^^^^^^^        ^^^^^^^^ Dataflow ID ^^^^^^^^^^^^^^^^^^
```

**Metodo 2 — dalle impostazioni del dataflow:**
1. Nel workspace, clicca sui tre puntini "..." accanto al dataflow
2. Seleziona "Impostazioni"
3. In basso nella pagina trovi il Dataflow ID sotto "Dettagli del dataflow"
4. Il Workspace ID lo trovi nelle impostazioni del workspace (ingranaggio → Impostazioni workspace → sezione "Dettagli")

**Metodo 3 — tramite API REST (per chi usa PowerShell o Postman):**
```
GET https://api.powerbi.com/v1.0/myorg/groups        → lista workspace con relativi ID
GET https://api.powerbi.com/v1.0/myorg/groups/{workspaceId}/dataflows   → lista dataflow con ID
```

### Raccomandazioni importanti
- I due GUID sono visibili direttamente nell'URL: è sempre il metodo più veloce
- Workspace ID = il GUID dopo `/groups/` nell'URL
- Dataflow ID = il GUID dopo `/dataflows/` nell'URL
- Credenziali: Power BI chiederà l'autenticazione Microsoft 365 al primo refresh
- Compatibilità: funziona sia con Dataflow Gen1 (Power BI) sia con Dataflow Gen2 (Fabric)
- Il nome entità deve corrispondere ESATTAMENTE al nome della tabella definita nel dataflow

### Template tabella Dataflow (singola entità)
```
table {NomeTabella}

	partition {NomeTabella}-DF = m
		mode: import
		source =
			let
				Source = PowerPlatform.Dataflows(null),
				Workspaces = Source{[Id="Workspaces"]}[Data],
				Workspace = Workspaces{[workspaceId="{WorkspaceID}"]}[Data],
				Dataflow = Workspace{[dataflowId="{DataflowID}"]}[Data],
				Entita = Dataflow{[entity="{NomeEntita}",version=""]}[Data]
			in
				Entita

```

### Template per più entità dallo stesso dataflow (query condivisa)
Se si importano più tabelle dallo stesso dataflow, usa una query condivisa per
evitare connessioni duplicate:

```
expression _Dataflow_{NomeProgetto} =
	let
		Source = PowerPlatform.Dataflows(null),
		Workspaces = Source{[Id="Workspaces"]}[Data],
		Workspace = Workspaces{[workspaceId="{WorkspaceID}"]}[Data],
		Dataflow = Workspace{[dataflowId="{DataflowID}"]}[Data]
	in
		Dataflow

table {NomeTabella1}

	partition {NomeTabella1}-DF = m
		mode: import
		source =
			let
				Dataflow = _Dataflow_{NomeProgetto},
				Entita = Dataflow{[entity="{NomeEntita1}",version=""]}[Data]
			in
				Entita

table {NomeTabella2}

	partition {NomeTabella2}-DF = m
		mode: import
		source =
			let
				Dataflow = _Dataflow_{NomeProgetto},
				Entita = Dataflow{[entity="{NomeEntita2}",version=""]}[Data]
			in
				Entita

```

---

## 4. File Excel locale

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| Percorso | "Percorso completo del file Excel?" | C:\Dati\Vendite.xlsx |
| Foglio | "Nome del foglio?" | Sheet1 |

### Raccomandazioni
- Il percorso deve essere raggiungibile dalla macchina PBI Desktop
- Per file su rete usare percorso UNC: \\server\cartella\file.xlsx
- Percorso hardcodato non è portabile — considerare parametro Power Query

### Template tabella Excel locale (SOLO partition)
```
table {NomeTabella}

	partition {NomeTabella}-Excel = m
		mode: import
		source =
			let
				Source = Excel.Workbook(File.Contents("{PercorsoFile}"), null, true),
				Foglio = Source{[Item="{NomeFoglio}",Kind="Sheet"]}[Data],
				Intestazioni = Table.PromoteHeaders(Foglio, [PromoteAllScalars=true])
			in
				Intestazioni

```

---

## Template relazioni (relationships.tmdl)

```
relationship r_{TabellaDa}_{TabellaA}
	fromColumn: {TabellaDa}.{ColonnaDa}
	toColumn: {TabellaA}.{ColonnaA}

```

Per relazione bidirezionale aggiungere sotto:
	crossFilteringBehavior: bothDirections


---

## 6. Live Connection (Semantic Model Power BI / Fabric)

A differenza degli altri connettori, la Live Connection NON importa dati nel
semantic model locale: le tabelle, le relazioni e le misure rimangono nel
modello remoto pubblicato su Power BI Service o Microsoft Fabric.

### Due modalità distinte

| Modalità | Cosa crea | Quando usarla |
|---|---|---|
| **Live Connection pura** | Solo un file `.Report` che punta al modello remoto. NESSUN semantic model locale viene creato. | Quando vuoi SOLO fare report su un modello esistente senza estenderlo. |
| **DirectQuery to Semantic Model** (Composite Model) | Un semantic model locale che contiene tabelle in DirectQuery verso il modello remoto + eventuali tabelle locali aggiuntive. | Quando vuoi estendere un modello esistente con tabelle o misure locali. |

⚠️ Nota importante per questo skill: la **Live Connection pura** esula dal
flusso classico di `pbi-crea-semantic-model` perché non produce un `.SemanticModel`.
Se l'utente la richiede, informalo che il file `.pbip` risultante avrà solo
la parte Report e non seguirà gli step 10-14 (relazioni, calendario, misure).

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| Nome workspace | "Nome esatto del workspace su Power BI / Fabric?" | AdventureWork - DATA |
| Nome semantic model | "Nome esatto del semantic model?" | DirectLakeTest |
| Semantic Model ID (opzionale) | "GUID del semantic model (opzionale, consigliato per robustezza)?" | b3230182-2389-4dd1-a3f7-88de66f255e2 |
| Modalità | "Live Connection pura o DirectQuery (composite)?" | Live Connection pura |
| Tabelle (solo DirectQuery) | "Quali tabelle del modello remoto vuoi esporre localmente?" | Vendite, Clienti, Prodotti |

⚠️ **Attenzione — nomi sensibili al maiuscolo/minuscolo e agli spazi:**
Sia il nome del workspace sia il nome del semantic model devono essere scritti
ESATTAMENTE come appaiono in Power BI Service (case-sensitive, spazi e caratteri
speciali inclusi). Esempio: `AdventureWork - DATA` con gli spazi attorno al trattino.

### Come trovare i parametri

**Metodo 1 — dal breadcrumb di Power BI Service / Fabric (il più rapido):**
1. Apri Power BI Service o Microsoft Fabric
2. Naviga nel workspace che contiene il semantic model
3. Il nome del workspace è visibile nel breadcrumb in alto e nella sidebar
4. Clicca sul semantic model per aprirlo: il nome compare in testa alla pagina

**Metodo 2 — dalle impostazioni del semantic model (per ottenere il GUID opzionale):**
1. Nel workspace, clicca sui tre puntini "..." accanto al semantic model
2. Seleziona "Impostazioni"
3. In "Dettagli del semantic model" trovi il Dataset ID (GUID)
4. Questo GUID va usato come parametro `semanticmodelid` nella connection string
   per disambiguare in caso di rinomine future del semantic model

**Metodo 3 — dall'URL del browser (per riferimento):**
```
https://app.powerbi.com/groups/{WorkspaceGUID}/datasets/{DatasetGUID}/details
```
Nota: l'URL mostra i GUID di workspace e dataset, ma per la connection
string serve il **NOME** del workspace e il **NOME** del semantic model.
Il GUID del workspace NON è utilizzabile nell'URL `powerbi://`.
Il GUID del dataset serve solo come parametro opzionale `semanticmodelid`.

**Metodo 4 — da Power BI Desktop (il più affidabile):**
1. In Power BI Desktop → Get Data → Power Platform → Power BI semantic models
2. Seleziona il semantic model desiderato → Connect
3. Una volta connesso, File → Opzioni e impostazioni → Origini dati: vedrai la
   connection string completa con nome workspace e nome dataset

### Raccomandazioni importanti
- Il nome del workspace nella connection string deve essere il **nome leggibile**,
  NON il GUID. Il GUID del workspace non è utilizzabile nell'URL `powerbi://`.
- Il nome del semantic model deve corrispondere ESATTAMENTE a quello in Power BI
  Service (case-sensitive, spazi inclusi).
- Il parametro `semanticmodelid` (GUID del dataset) è **opzionale** ma consigliato:
  permette alla connessione di sopravvivere a rinomine del semantic model.
- Le credenziali Microsoft 365 saranno richieste al primo refresh/apertura.
- In DirectQuery le misure del modello remoto sono utilizzabili ma non modificabili
  localmente. Le nuove misure locali sono additive.
- Le tabelle in DirectQuery NON hanno partizione di storage locale: ogni query
  viene eseguita runtime sul modello remoto.

### Template Live Connection PURA — file `.Report/definition.pbir`

Per la Live Connection pura il file `.pbir` contiene il riferimento al
semantic model remoto via `byConnection.connectionString`, senza alcun file
TMDL nel `.SemanticModel`.

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json",
  "version": "4.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "Data Source=powerbi://api.powerbi.com/v1.0/myorg/{NomeWorkspace};initial catalog={NomeSemanticModel};access mode=readonly;integrated security=ClaimsToken;semanticmodelid={SemanticModelID}"
    }
  }
}
```

**Esempio compilato:**
```
"connectionString": "Data Source=powerbi://api.powerbi.com/v1.0/myorg/AdventureWork - DATA;initial catalog=DirectLakeTest;access mode=readonly;integrated security=ClaimsToken;semanticmodelid=b3230182-2389-4dd1-a3f7-88de66f255e2"
```

**Parametri della connection string:**
- `Data Source` → URL `powerbi://api.powerbi.com/v1.0/myorg/` + **nome workspace**
- `initial catalog` → **nome del semantic model**
- `access mode=readonly` → sola lettura (standard per Live Connection)
- `integrated security=ClaimsToken` → autenticazione Microsoft 365
- `semanticmodelid` → **GUID del semantic model** (opzionale, consigliato)

### Template tabella DirectQuery to Semantic Model (M query)

Se invece scegli DirectQuery (composite model), le tabelle sono definite in M
query e importate nel semantic model locale. Anche qui `{NomeWorkspace}` è il
**nome** del workspace, non il GUID.

```
table {NomeTabella}

	partition {NomeTabella}-LC = m
		mode: directQuery
		source =
			let
				Source = AnalysisServices.Database(
					"powerbi://api.powerbi.com/v1.0/myorg/{NomeWorkspace}",
					"{NomeSemanticModel}",
					[TypedMeasureColumns=true, Implementation="2.0"]
				),
				Cube = Source{[Name="Model"]}[Data],
				Tabella = Cube{[Name="{NomeTabella}",Kind="Table"]}[Data]
			in
				Tabella

```

### Template per più tabelle dallo stesso semantic model (query condivisa)
Se si espongono più tabelle dallo stesso semantic model remoto, usa una query
condivisa per evitare connessioni duplicate:

```
expression _SemanticModel_{NomeProgetto} =
	let
		Source = AnalysisServices.Database(
			"powerbi://api.powerbi.com/v1.0/myorg/{NomeWorkspace}",
			"{NomeSemanticModel}",
			[TypedMeasureColumns=true, Implementation="2.0"]
		),
		Cube = Source{[Name="Model"]}[Data]
	in
		Cube

table {NomeTabella1}

	partition {NomeTabella1}-LC = m
		mode: directQuery
		source =
			let
				Cube = _SemanticModel_{NomeProgetto},
				Tabella = Cube{[Name="{NomeTabella1}",Kind="Table"]}[Data]
			in
				Tabella

table {NomeTabella2}

	partition {NomeTabella2}-LC = m
		mode: directQuery
		source =
			let
				Cube = _SemanticModel_{NomeProgetto},
				Tabella = Cube{[Name="{NomeTabella2}",Kind="Table"]}[Data]
			in
				Tabella

```

### Caso Live Connection pura — cosa fare nel flusso
Se l'utente sceglie **Live Connection pura**, il flusso del skill cambia:
- NON vengono creati file `.tmdl` per tabelle, relazioni, calendario o misure
- La cartella `.SemanticModel` non viene creata (o resta vuota)
- Viene creato SOLO il file `.Report/definition.pbir` con il `byConnection.connectionString`
- Si salta direttamente agli step 7 (UUID/creazione file) e 8 (import in PBI Desktop)
- Nessun step 10-14 è applicabile (relazioni, calendario, dimensioni, misure sono
  già nel modello remoto e non sono estendibili)

In questo caso, informa l'utente che il workflow standard non si applica e chiedi
conferma se vuole procedere comunque oppure passare a DirectQuery per mantenere
la possibilità di estendere localmente.

---

## 7. Microsoft Fabric SQL Endpoint (Warehouse / Lakehouse)

Il connettore `Sql.Database` funziona con gli endpoint SQL di Microsoft Fabric:
sia Warehouse sia il SQL Analytics Endpoint di un Lakehouse. I dati vengono
IMPORTATI nel semantic model locale.

Per Direct Lake puro (lettura diretta da OneLake senza importazione) vedi
invece `directlake.md`.

### Parametri da raccogliere
| Parametro | Domanda | Esempio |
|---|---|---|
| SQL Connection String | "Qual è la SQL connection string dell'endpoint Fabric?" | xio7tuocv4zunleqg6rdkk2nye-34mxy57z4pkene4anqyyztg4oa.datawarehouse.fabric.microsoft.com |
| Nome Warehouse/Lakehouse | "Come si chiama il Warehouse o il Lakehouse?" (nome esatto, case-sensitive) | adw_analytics |
| Schema | "Quale schema? (default: dbo)" | dbo |
| Tabelle | "Quali tabelle vuoi importare?" | fact_sales, dim_customer, dim_product |

### Come trovare la SQL connection string

**Metodo A — dal workspace (più rapido):**
1. Apri [app.fabric.microsoft.com](https://app.fabric.microsoft.com) e naviga nel workspace
2. Individua il Warehouse (o il Lakehouse) nell'elenco degli item
3. Passa il mouse sopra l'item → appaiono le icone rapide a destra
4. Clicca sui **tre puntini "..."** (More options) → seleziona **"Copy SQL connection string"**
5. La stringa copiata ha la forma `{hash}.datawarehouse.fabric.microsoft.com`

**Metodo B — dall'interno del Warehouse:**
1. Apri il Warehouse cliccandoci sopra
2. Nella barra in alto cerca il pulsante **"Copy SQL connection string"** (icona copia accanto al nome)
   — oppure: menu **"..."** nella toolbar → "Copy SQL connection string"

**Per un Lakehouse (SQL Analytics Endpoint):**
1. Apri il Lakehouse
2. In alto a destra cambia la vista da **"Lakehouse"** a **"SQL analytics endpoint"**
3. Usa Metodo B come sopra

Il valore finale è nella forma `{hash}.datawarehouse.fabric.microsoft.com`
(non include `https://` né il database name — solo l'hostname).

Il **nome del Warehouse/Lakehouse** è il nome dell'item come appare nel
workspace (es. `adw_analytics`).

### Raccomandazioni importanti
- Autenticazione: **Microsoft 365 / Account organizzativo** (OAuth2). Le
  credenziali sono richieste al primo refresh. SQL Auth e Windows Auth
  NON sono supportate dagli endpoint Fabric.
- Schema di default: `dbo` (sia Warehouse sia Lakehouse SQL Endpoint)
- Il Lakehouse SQL Endpoint espone **solo tabelle Delta registrate**: file
  non registrati come tabelle non sono visibili via TDS
- Per refresh programmati da Power BI Service, l'account deve avere almeno
  il permesso **ReadData** sull'item Fabric

### Template tabella
```
table {NomeTabella}

	partition {NomeTabella}-FabricSQL = m
		mode: import
		source =
			let
				Source = Sql.Database("{SQLConnectionString}", "{NomeWarehouse}"),
				Tabella = Source{[Schema="{NomeSchema}",Item="{NomeTabellaSQL}"]}[Data]
			in
				Tabella

```

### Template per più tabelle dallo stesso endpoint (query condivisa)
```
expression _FabricSQL_{NomeProgetto} =
	let
		Source = Sql.Database("{SQLConnectionString}", "{NomeWarehouse}")
	in
		Source

table {NomeTabella1}

	partition {NomeTabella1}-FabricSQL = m
		mode: import
		source =
			let
				Source = _FabricSQL_{NomeProgetto},
				Tabella = Source{[Schema="{NomeSchema}",Item="{NomeTabellaSQL1}"]}[Data]
			in
				Tabella

table {NomeTabella2}

	partition {NomeTabella2}-FabricSQL = m
		mode: import
		source =
			let
				Source = _FabricSQL_{NomeProgetto},
				Tabella = Source{[Schema="{NomeSchema}",Item="{NomeTabellaSQL2}"]}[Data]
			in
				Tabella

```

### Template con query SQL personalizzata
Per filtrare o aggregare direttamente sul Warehouse sfruttando il query folding:

```
table {NomeTabella}

	partition {NomeTabella}-FabricSQL = m
		mode: import
		source =
			let
				Source = Sql.Database("{SQLConnectionString}", "{NomeWarehouse}"),
				Query = Value.NativeQuery(Source,
					"SELECT * FROM {NomeSchema}.{NomeTabellaSQL} WHERE ...",
					null,
					[EnableFolding=true])
			in
				Query

```
