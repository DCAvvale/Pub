# Reference — Calendario DAX

Questo reference e invocato dallo STEP 12 del SKILL.md. Contiene la logica
completa per gestire il calendario del semantic model via MCP: rilevamento
di una tabella calendario preesistente, creazione di una nuova Calendar DAX
con range dinamico, marcatura come Date Table, colonne standard e relazioni
con le Fact.

---

## Fase 1 — Verifica preventiva

Usa `ExportTMDL` e controlla se esiste gia una tabella il cui nome contiene
(case-insensitive): "calendar", "calendario", "date", "dim_date", "dimdate", "data".

- Se trovi una tabella candidata → vai al **Caso B**
- Altrimenti → vai al **Caso A**

---

## Caso A — Calendario NON presente

1. Individua tutte le colonne di tipo dateTime nelle tabelle Fact
2. Mostra le colonne trovate e chiedi quale usare come riferimento per il range
3. Crea la tabella Calendar DAX con range dinamico per anno intero:

   ```dax
   Calendar =
   VAR MinYear = YEAR(MIN({FactTable}[{DateColumn}]))
   VAR MaxYear = YEAR(MAX({FactTable}[{DateColumn}]))
   RETURN
   ADDCOLUMNS(
       CALENDAR(DATE(MinYear, 1, 1), DATE(MaxYear, 12, 31)),
       "Anno",            YEAR([Date]),
       "Mese",            MONTH([Date]),
       "NomeMese",        FORMAT([Date], "MMMM"),
       "Trimestre",       "Q" & QUARTER([Date]),
       "AnnoMese",        FORMAT([Date], "YYYY-MM"),
       "GiornoSettimana", WEEKDAY([Date], 2),
       "NomeGiorno",      FORMAT([Date], "dddd"),
       "IsWeekend",       IF(WEEKDAY([Date], 2) >= 6, TRUE, FALSE)
   )
   ```

   Nota: `MinYear` e `MaxYear` vengono ricalcolati a ogni refresh, quindi se nel
   2027 arrivano nuovi dati il calendario si estende automaticamente a
   `DATE(2027,12,31)`.

4. Aggiunge la tabella Calendar al modello via MCP
5. Marca la tabella come Date Table (`isDateTable: true`) via MCP
6. Propone le relazioni tra `Calendar[Date]` e le colonne dateTime nelle Fact
7. Ordina `NomeMese` in base a `Mese` via MCP
8. Aspetta approvazione e applica via MCP

---

## Caso B — Calendario GIA presente

1. Mostra il nome della tabella trovata:
   "Ho trovato una tabella calendario esistente: [{NomeTabella}]. Vuoi usarla come Date Table?"
2. Aspetta conferma esplicita
3. Se confermato:
   - Marca la tabella come Date Table (`isDateTable: true`) via MCP
   - Analizza le colonne esistenti e confrontale con il set standard:
     `Anno, Mese, NomeMese, Trimestre, AnnoMese, GiornoSettimana, NomeGiorno, IsWeekend`
   - Per ogni colonna standard mancante propone di aggiungerla come colonna calcolata DAX
   - Aspetta approvazione per le colonne aggiuntive, applica via MCP
   - Verifica le relazioni con le Fact table e propone eventuali relazioni mancanti
   - Aspetta approvazione e applica via MCP
