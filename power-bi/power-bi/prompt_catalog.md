# Prompt Catalog — pbi-semantic-model-advanced

> **Versione:** 2.0 · **Aggiornato:** 2026-04-29
>
> Esempi di prompt per attivare e guidare la skill. Ogni prompt scatena un flusso specifico.
> Le frasi marcate ▸ sono **trigger ufficiali** della skill (matching `description` nel SKILL.md).

---

## 1. Flusso CREAZIONE (modello da zero)

### 1.1 Prompt minimo — flusso guidato step-by-step

▸ `genera semantic model`
▸ `crea modello`
▸ `crea pbip`
▸ `nuovo pbip`
▸ `nuovo modello`

> Avvia il flusso completo con le 18 domande. Claude raccoglie nome, modalità storage, connettore, tabelle Fact/Dim, cartella, git, e procede. **Nessun parametro fornito a priori.** Adatto se non hai ancora deciso tutto.

### 1.2 Prompt dettagliato — end-to-end con parametri

```
crea semantic model "Vendite2026", modalità Import, sorgente SQL Server
on-prem (SQLPRD01, database "DWH_Sales"), tabelle fact: FactSales, FactReturns
(da unificare), dim: DimCustomer, DimProduct, DimDate. Salva in
C:\PowerBI\Vendite2026. Usa GitHub, repo privata.
```

> Claude estrae i parametri dal prompt e procede chiedendo solo conferme tra uno step e l'altro. Riduce le domande a metà. **Specifica almeno: nome, modalità, connettore, tabelle, cartella, git.**

### 1.3 Prompt Direct Lake (Fabric)

```
crea semantic model "Operations_DL" in modalità Direct Lake, connesso al
Lakehouse "OpsLH" del workspace "Production_Fabric". Tabelle: factEvents,
dimMachine, dimShift.
```

> Salta gli STEP 2-15 standard e segue `references/directlake.md`. Richiede tenant Fabric e workspace già configurato.

### 1.4 Prompt SharePoint multi-file

```
crea pbip "BudgetFY26" da SharePoint https://contoso.sharepoint.com/sites/finance,
file Excel: Budget_FY26.xlsx (foglio Budget) e Actuals_FY26.xlsx (foglio Q1-Q4).
Le due tabelle vanno unificate.
```

### 1.5 Solo locale, no git

```
nuovo semantic model "Sandbox_Test", Import, Excel locale
C:\Data\test.xlsx, due tabelle: Sales, Customers. Niente git, lavoro in locale.
```

---

## 2. Flusso AUDIT (modello esistente)

### 2.1 Audit completo

▸ `audit modello`
▸ `analizza modello esistente`
▸ `revisione modello`
▸ `controlla il mio modello`
▸ `auditare modello`
▸ `best practice check`

> Claude esegue lo scan via MCP, applica il catalogo BPA, genera il report Markdown AS-IS in 9 sezioni con diagrammi mermaid, propone azioni correttive prioritizzate.

### 2.2 Audit con redaction PII attiva

```
audit modello — il modello contiene dati personali, attiva la redaction PII
nel report
```

> Claude applica la sostituzione automatica di nomi colonne/misure che matchano pattern PII (CF, IBAN, Email, Phone, Stipendio, Indirizzo, ecc.). Il report committato è safe per condivisione esterna.

### 2.3 Audit + refactor immediato

```
audit modello "Sales_Production" e procedi subito con il refactor di tutte
le violazioni Error e Warning di categoria Performance e DAX
```

> Salta la pausa post-report e parte direttamente con A5-A6, filtrando solo le categorie indicate.

### 2.4 Audit focalizzato su una categoria

```
revisione modello, focus solo su misure DAX (DIVIDE, format string, naming)
```

> Claude applica solo le regole BPA della categoria DAX, salta le altre. Report più snello.

### 2.5 Documentare modello esistente senza refactor

```
documenta pbip — voglio solo il report AS-IS, niente modifiche
```

> Genera il report e termina dopo STEP A4. Equivalente a scegliere `[2] Salvo e basta` al checkpoint.

---

## 3. Quality check & validazione (richiede modello già aperto in PBI Desktop)

### 3.1 Blank in dimensioni

```
controlla valori blank nelle dimensioni del modello aperto
```

> MCP esegue query DAX per ogni dimensione: `EVALUATE FILTER('{Dim}', ISBLANK('{Dim}'[{Key}]))`. Restituisce solo conteggi (privacy-safe).

### 3.2 Cardinalità relazioni sospette

```
verifica le relazioni del modello: trova quelle con cardinalità non corretta
o con valori orfani
```

> Per ogni relazione runs `COUNTROWS(EXCEPT(...))` per stimare orfani. Solo metriche.

### 3.3 Misure inutilizzate

```
trova le misure non referenziate da altre misure o oggetti del modello
```

> Equivalente a STEP A3 BPA-X-001 in modalità isolata.

### 3.4 Performance check rapido

```
fai un performance check rapido: Auto Date/Time, colonne calcolate pesanti,
SUMX dove basterebbe SUM
```

> Esegue solo le regole BPA-P-* (Performance) e produce un riepilogo testuale, non il report completo.

---

## 4. Esplorazione e analisi (modello già esistente)

### 4.1 Spiega una misura

```
spiegami in linguaggio naturale la misura "[Calcs].[Sales YTD]" e le sue dipendenze
```

> Legge l'espressione DAX via `ExportTMDL`, traccia le dipendenze (misure referenziate, colonne usate), produce spiegazione step-by-step.

### 4.2 Lineage source-to-measure

```
mostrami il lineage dalla colonna SQL "dbo.Sales.Amount" fino alle misure
del modello che la usano
```

> Combina query M (per origine) + dipendenze DAX. Produce un albero di derivazione.

### 4.3 Confronto pre/post refactor

```
confronta il modello attuale con la baseline AS-IS dell'audit di ieri:
quali violazioni sono state risolte?
```

> Richiede che il report AS-IS sia committato in `audit_AS-IS_*.md`. Confronta scan corrente con quel report.

---

## 5. Documentazione

### 5.1 Documentazione tecnico-funzionale standalone

```
genera la documentazione tecnico-funzionale del modello attualmente aperto
in PBI Desktop, salvala in C:\Docs\
```

> Chiama direttamente `references/documentation.md` (STEP D1-D4) senza il flusso di creazione completo.

### 5.2 KPI catalog per stakeholder business

```
estrai un KPI catalog del modello in formato tabellare:
nome misura, descrizione business, formula DAX, owner, tag dominio
```

> Subset della documentazione, solo Sezione "KPI catalog" del template doc.

---

## 6. Git e collaborazione

### 6.1 Setup git su modello esistente non versionato

```
il modello è in C:\Models\Existing.pbip ma non è ancora su git.
Inizializza una repo GitHub privata e fai il primo commit della baseline
```

> Salta direttamente a STEP G1 di `git-integration.md`, branch `main`, primo commit con tutti i file.

### 6.2 Push baseline audit

```
ho appena finito un audit, fammi push del report AS-IS e crea una PR
"audit baseline {nome}"
```

> Skip degli step di refactor, push diretto del solo report.

---

## 7. Direct Lake & Fabric

### 7.1 Convertire un modello Import in Direct Lake

```
ho un .pbip in modalità Import che pesca da SQL. Voglio migrarlo a
Direct Lake leggendo dal Lakehouse "ProdLH". Cosa devo cambiare?
```

> Claude analizza il modello via `ExportTMDL`, identifica le tabelle migrabili, propone la conversione (richiede manualità — non è completamente automatica).

### 7.2 Validazione Direct Lake

```
controlla che tutte le tabelle del modello Direct Lake siano correttamente
mappate alle delta table del Lakehouse e che non ci siano fallback warnings
```

> Esegue query DAX di sondaggio + interroga lo stato del Lakehouse via MCP Fabric.

---

## 8. Tips per prompting efficace

### 8.1 Cosa includere in un prompt dettagliato

Per ridurre le domande della skill, fornisci almeno:

| Parametro | Esempio |
|---|---|
| Nome progetto | `"Vendite2026"` |
| Modalità storage | `Import` o `Direct Lake` |
| Connettore | `SQL Server`, `SharePoint`, `Fabric LH`, ecc. |
| Parametri sorgente | server/URL/workspace + database/sito/lakehouse |
| Tabelle Fact (+ unifica?) | `factSales, factReturns (unificate)` |
| Tabelle Dim | `dimCustomer, dimProduct, dimDate` |
| Cartella | path completo `C:\PowerBI\...` |
| Git | `GitHub privata` / `Azure DevOps` / `solo locale` |

### 8.2 Cosa evitare

- ❌ Non incollare PAT / credenziali / connection string in chat — finiscono nel contesto AI
- ❌ Non chiedere l'esecuzione di DAX che restituisce dati di riga (`EVALUATE TopN`, `EVALUATE {table}`) su tabelle con PII — usa `COUNTROWS` o `INFO.*`
- ❌ Non lanciare il flusso AUDIT su modelli con dati classificati senza prima attivare la redaction PII
- ❌ Non saltare la conferma a G1.3 quando l'opzione è "crea repo GitHub" — verifica la classificazione del dato

### 8.3 Quando usare quale approccio

| Scenario | Approccio consigliato |
|---|---|
| Prima volta, struttura non chiara | Prompt minimo (1.1), risposte interattive |
| Modello standard, parametri noti | Prompt dettagliato (1.2) |
| Modello complesso multi-sorgente | Prompt minimo, sfrutta loop STEP 5b |
| Audit periodico ripetibile | Prompt 2.1 + script che lo richiama |
| Demo / training | Prompt 2.5 (solo doc, no modifiche) |

---

## 9. Esempi di sessione completa

### 9.1 Creazione end-to-end (10 minuti)

```
> crea semantic model "Demo_Q1", Import, SharePoint
  https://contoso.sharepoint.com/sites/demo, file Sales_Q1.xlsx (foglio
  Detail). Una sola tabella fact, niente dim. Cartella C:\PBI\Demo_Q1.
  Solo locale, niente git.

[Skill: preflight → STEP 1-7 con conferme rapide → STEP 8 apertura manuale →
STEP 9-15 validazione e arricchimento → STEP 15 riepilogo]

> grazie, salta documentazione

[Skill: termina senza STEP 16-17]
```

### 9.2 Audit completo con remediation (~20 minuti)

```
> audit modello

[Skill: A1 selezione → A2 scan → A3 BPA → A4 report → checkpoint]

> /compact

> procedi con tutte le azioni di Priorità 1 ed Error

[Skill: A5 filtro → A6 refactor in 5 milestone → commit per milestone]

> push e PR

[Skill: A6b push branch + PR su GitHub]
```
