### Fase 1 — Crea tabella placeholder Calcs
Crea via MCP una tabella calcolata DAX chiamata "Calcs":

   Calcs = {BLANK()}

- La prima (e unica) colonna viene marcata come nascosta (isHidden: true)
- Questa tabella e il contenitore di tutte le misure del modello
- NON creare misure direttamente nelle tabelle Fact

### Fase 2 — Definizione KPI

Chiedi all'utente:

> "Quali sono i KPI principali del tuo modello? Ad esempio: **Vendite**, **Costi**,
> **Margine**, **Quantità**, **Ore lavorate**...
> Se non sei sicuro posso **esplorare il modello** e proporti io i KPI che trovo."

---

#### Percorso A — L'utente definisce i KPI

Per ogni KPI dichiarato (es. "Vendite"):

1. Usa ExportTMDL e cerca nelle colonne numeriche delle Fact:
   - Colonne il cui nome contiene il KPI o sinonimi comuni
     (es. "sales", "vendite", "revenue", "ricavo", "importo", "amount")
   - Coppie di colonne moltiplicabili (es. Quantity × UnitPrice)

2. Proponi la logica migliore seguendo questa priorità:

   | Caso | Formula proposta |
   |---|---|
   | Esiste colonna diretta (es. SalesAmount) | `SUM(Fact[SalesAmount])` |
   | Esiste coppia moltiplicabile (es. Qty × Price) | `SUMX(Fact, Fact[Qty] * Fact[Price])` |
   | Nessuna colonna chiara trovata | Segnala e chiedi indicazione manuale |

3. Mostra la proposta e aspetta conferma prima di procedere al KPI successivo.

---

#### Percorso B — Discovery automatica

Usa ExportTMDL e analizza tutte le colonne numeriche nelle Fact cercando:

- **Ricavo/Vendite:** colonne con sales, revenue, amount, importo, ricavo, vendita
  — oppure coppie quantity/price, qty/unitprice, quantità/prezzo → `SUMX`
- **Costo:** colonne con cost, costo, spesa, expense
  — oppure coppie qty × cost → `SUMX`
- **Margine:** se esistono sia revenue che cost propone
  `[Margine] = [Totale Vendite] - [Totale Costo]`
- **Quantità/Volumi:** colonne con quantity, qty, quantità, pezzi, units → `SUM`
- **Altri KPI:** colonne numeriche residue con cardinalità alta → `SUM`

Mostra il riepilogo dei KPI proposti con la formula per ciascuno.
Aspetta approvazione esplicita prima di procedere.

---

#### Regola formula per le Base Measures

- **`SUM(Fact[Colonna])`** → colonna singola da aggregare
- **`SUMX(Fact, Fact[A] * Fact[B])`** → prodotto o espressione tra due colonne
- **MAI usare SUMX su colonna singola** — usare sempre SUM in quel caso

---

### Fase 3 — Proponi set misure completo

Dopo approvazione dei KPI, mostra l'elenco completo di tutte le misure che verranno
create nelle tre cartelle. L'utente puo escludere singole misure o intere cartelle.
Aspetta approvazione finale prima di applicare.

Le misure sono organizzate in tre cartelle (displayFolder):

#### Cartella "Base Measures"
Per ogni KPI approvato:
   [Totale {KPI}]          = SUM({FactTable}[{Colonna}])           ← colonna diretta
   [Totale {KPI}]          = SUMX({FactTable}, Fact[A] * Fact[B])  ← coppia calcolata
   [Media {KPI}]           = DIVIDE([Totale {KPI}], [Conteggio Righe])
   [Conteggio Righe]       = COUNTROWS({FactTable})
   [Distinti {ChiaveFact}] = DISTINCTCOUNT({FactTable}[{ChiaveFact}])

#### Cartella "To Date"
Per ogni misura base approvata, collegate al Calendario:
   [YTD {Metrica}] = TOTALYTD([Totale {Metrica}], Calendar[Date])
   [MTD {Metrica}] = TOTALMTD([Totale {Metrica}], Calendar[Date])
   [QTD {Metrica}] = TOTALQTD([Totale {Metrica}], Calendar[Date])

#### Cartella "Previous Period"
Per ogni misura base approvata, collegate al Calendario:
   [PY {Metrica}] = CALCULATE([Totale {Metrica}], SAMEPERIODLASTYEAR(Calendar[Date]))
   [PM {Metrica}] = CALCULATE([Totale {Metrica}], PREVIOUSMONTH(Calendar[Date]))
   [PQ {Metrica}] = CALCULATE([Totale {Metrica}], PREVIOUSQUARTER(Calendar[Date]))

### Fase 4 — Applica via MCP
Dopo approvazione: crea tutte le misure nella tabella Calcs via MCP,
ognuna con il displayFolder corrispondente ("Base Measures", "To Date", "Previous Period").

---