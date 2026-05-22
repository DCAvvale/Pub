# Preflight — Verifica prerequisiti di sistema

Questo file descrive i controlli da eseguire **all'avvio della skill**, prima della
welcome / routing / STEP 1. Obiettivo: fallire subito (in <5 secondi) se l'ambiente
non è pronto, invece di scoprirlo al STEP 8 (MCP) o al STEP 6b (Git/CLI provider).

## Principi

1. **Silenzioso quando tutto funziona** — solo un riepilogo a una riga in caso di successo.
2. **Esplicito in caso di errore** — messaggio chiaro + remediation specifica + interruzione del flusso (per i check bloccanti).
3. **Check stratificati per criticità:**
   - **Bloccanti** — fermano il flusso se falliscono (MCP).
   - **Warning** — avvisano ma l'utente può proseguire (PBI Desktop, git).
   - **Informativi** — segnalano disponibilità per scelte successive (gh, az + estensione devops).
4. **Idempotente** — eseguibile a ogni avvio senza side-effect.
5. **Nessun controllo auth** — `gh auth status` / `az account show` richiedono interazione e dipendono dal provider scelto: si rimandano a STEP G1.2 quando il provider è noto.

---

## Sequenza controlli

Esegui i check **in parallelo** dove possibile (sono indipendenti). Aggrega i risultati e mostra un riepilogo unico.

### Check 1 — MCP `powerbi-mcp-server` raggiungibile [BLOCCANTE]

**Cosa fare:**
Chiama `mcp__powerbi-mcp-server__connection_operations` con `action: "ListLocalInstances"`.

**Successo:** la chiamata ritorna senza eccezione.

**Fallimento:** la chiamata produce errore (tool non disponibile, MCP server down, timeout).

**Remediation se fallisce:**
```
❌ MCP powerbi-mcp-server non raggiungibile.

Possibili cause:
  • Il server MCP non è installato o configurato in Claude Code
  • Il server è installato ma non avviato

Come verificare:
  1. Esegui in terminale:  claude mcp list
  2. Cerca "powerbi-mcp-server" nell'elenco
  3. Se non c'è, installalo seguendo la documentazione del server
  4. Se c'è ma è "failed", riavvia Claude Code

Senza MCP la skill non può importare il modello in Power BI Desktop
né leggere modelli esistenti per l'audit. Stop preflight.
```

Dopo aver mostrato il messaggio, **interrompi la skill**.

---

### Check 2 — Power BI Desktop installato [WARNING]

**Cosa fare:**
Verifica l'esistenza dell'eseguibile in uno dei path standard via PowerShell.

```powershell
$paths = @(
  "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
  "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
)
$found = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($found) { Write-Output "OK: $found" } else {
  $store = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "Microsoft.MicrosoftPowerBIDesktop_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($store) { Write-Output "OK (Store): $($store.FullName)" } else { Write-Output "MISSING" }
}
```

**Successo:** output inizia con `OK`.
**Fallimento:** output `MISSING` → warning, non blocca.

**Remediation:**
```
⚠️  Power BI Desktop non trovato. Scaricalo da:
   https://www.microsoft.com/it-it/download/details.aspx?id=58494
   oppure dal Microsoft Store.
```

---

### Check 3 — `git` CLI disponibile [WARNING]

**Cosa fare:**
```powershell
git --version
```

**Successo:** output tipo `git version 2.x.x`.
**Fallimento:** comando non trovato.

**Remediation:**
```
⚠️  git CLI non trovato. Senza git non potrai usare la git integration
   (STEP 6b — opzionale). Installa da: https://git-scm.com/download/win
```

Non blocca: l'utente può scegliere `GitEnabled = No` a STEP 6b e proseguire senza git.

---

### Check 4 — GitHub CLI (`gh`) disponibile [INFORMATIVO]

**Cosa fare:**
```powershell
$ghPath = "C:\Program Files\GitHub CLI\gh.exe"
if (Test-Path $ghPath) {
  & $ghPath --version | Select-Object -First 1
} else {
  $cmd = Get-Command gh -ErrorAction SilentlyContinue
  if ($cmd) { & $cmd.Source --version | Select-Object -First 1 } else { Write-Output "MISSING" }
}
```

**Successo:** output tipo `gh version 2.x.x ...`.
**Fallimento:** `MISSING` → informativo.

**Remediation:**
```
ℹ️  GitHub CLI non trovato. Sarà richiesta solo se sceglierai GitHub
   come provider a STEP G1.2. Installa da: https://cli.github.com/
```

Non blocca. Memorizza `{ghAvailable} = false` per STEP G1.2.

---

### Check 5 — Azure CLI (`az`) + estensione `azure-devops` [INFORMATIVO]

**Cosa fare:**
```powershell
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCmd) {
  Write-Output "AZ_MISSING"
} else {
  $ver = (& $azCmd.Source --version 2>&1 | Select-String -Pattern '^azure-cli\s+' | Select-Object -First 1).Line
  $ext = & $azCmd.Source extension list --output tsv 2>&1 | Select-String -Pattern 'azure-devops'
  if ($ext) { Write-Output "OK: $ver | devops extension: installed" }
  else      { Write-Output "OK: $ver | devops extension: MISSING" }
}
```

**Successo completo:** `az` presente E estensione `azure-devops` installata.
**Successo parziale:** `az` presente ma estensione mancante → segnala.
**Fallimento:** `AZ_MISSING`.

**Remediation:**
```
ℹ️  Azure CLI non trovato (o estensione azure-devops mancante).
   Sarà richiesta solo se sceglierai Azure DevOps come provider a STEP G1.2.
   Install: winget install --id Microsoft.AzureCLI
   Estensione: az extension add --name azure-devops
```

Non blocca. Memorizza `{azAvailable}` e `{azDevOpsExtension}` per STEP G1.2.

---

## Output formattato — riepilogo finale

Dopo tutti i check, mostra un **box unico** con lo stato di ciascun componente:

### Tutto OK
```
┌─ Preflight ──────────────────────────────────────────────┐
│ ✓ MCP powerbi-mcp-server     connesso                    │
│ ✓ Power BI Desktop           v2.153.910.0 (Store)        │
│ ✓ git                        v2.45.0                     │
│ ✓ GitHub CLI (gh)            v2.55.0                     │
│ ✓ Azure CLI (az)             v2.62.0 + devops extension  │
│                                                          │
│ Pronto. Procedo con la skill.                            │
└──────────────────────────────────────────────────────────┘
```

### Disclaimer privacy (sempre, dopo il box di esito)

Subito dopo il box di preflight (in caso di successo, anche con warning), mostra
all'utente questo disclaimer una sola volta:

```
🔒 Nota privacy
   I metadati del modello (TMDL: nomi tabelle, colonne, formule DAX, query M)
   e i conteggi delle query di validazione passano attraverso il provider AI
   per essere elaborati.

   • La skill NON esegue query che restituiscono righe di dati reali.
   • Server names, URL SharePoint e schemi DB sono comunque visibili.
   • Se il modello contiene dati classificati (PII, finanziari, sanitari),
     verifica con il tuo data steward / responsabile compliance prima di
     procedere.

   Vuoi continuare?  [S] Sì  [N] No, esco
```

Aspetta conferma esplicita prima di proseguire con welcome / routing.

Se l'utente risponde [N]: termina silenziosamente la skill.

### Successo con warning
```
┌─ Preflight ──────────────────────────────────────────────┐
│ ✓ MCP powerbi-mcp-server     connesso                    │
│ ✓ Power BI Desktop           v2.153.910.0 (Store)        │
│ ⚠ git                        non installato              │
│ ℹ GitHub CLI (gh)            non installato              │
│ ✓ Azure CLI (az)             v2.62.0 + devops extension  │
│                                                          │
│ Procedo. Senza git la git integration sarà disabilitata. │
└──────────────────────────────────────────────────────────┘
```

### Fallimento bloccante (Check 1)
Mostra solo il blocco di remediation Check 1 e **stop**, non il box riepilogativo.

---

## Variabili di sessione popolate

Dopo il preflight, salva queste variabili (sopravvivono al `/compact`):

| Variabile | Valori | Uso futuro |
|---|---|---|
| `{PreflightDone}` | `true` | Skip preflight a re-invocazione |
| `{PBIDesktopPath}` | path o `null` | STEP 8 ImportFromTmdlFolder |
| `{LocalPBIInstances}` | array da Check 1 | STEP 8 evita di richiamare ListLocalInstances |
| `{gitAvailable}` | `true`/`false` | STEP 6b decide se mostrare opzione git |
| `{ghAvailable}` | `true`/`false` | STEP G1.2 — disabilita opzione GitHub se false |
| `{azAvailable}` | `true`/`false` | STEP G1.2 — disabilita opzione Azure DevOps se false |
| `{azDevOpsExtension}` | `true`/`false` | STEP G1.2 — se az ok ma extension no, propone install |

---

## Quando NON eseguire il preflight

- Se nel contesto è già presente la riga `✓ Preflight: ...` o il box riepilogativo recente (stessa conversazione) → salta.
- Se l'utente esplicitamente scrive `--skip-preflight` o equivalente nel suo trigger.

In tutti gli altri casi, **esegui sempre il preflight come prima azione della skill**.
