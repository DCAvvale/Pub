#Requires -Version 7.0
<#
.SYNOPSIS
  Power BI load test — STANDALONE single-file version.
  Paste this whole file into pwsh on the VDI and follow the prompts.
  No Claude, no skill, no other scripts required.

.DESCRIPTION
  What it does:
    1) Checks / installs Az.Accounts.
    2) Prompts you for tenant / workspace / dataset GUIDs.
    3) Opens the browser for interactive login (Connect-AzAccount).
    4) Discovers measures + a filter column from the model via INFO.MEASURES / INFO.COLUMNS.
    5) Builds a small DAX battery (5 unfiltered + 5 filtered queries).
    6) Runs the battery at concurrency levels 1 / 10 / 25 / 50 / 100,
       each in two scenarios:
         BCS = Best-Case  → same filter literal every call (caches warm up)
         WCS = Worst-Case → filter literal randomized per call (cache miss)
    7) Writes raw CSV + a Markdown summary to .\pbi-loadtest-output\.

  Limits vs full skill (be aware):
    - No automatic bottleneck classification (model vs source vs onelake vs capacity).
    - No context profile / customer-specific framing.
    - Smaller, hand-picked battery (no automatic query-pattern coverage).
    - Single Service Principal / user → expect HTTP 429 at level >= 50
      (REST API limit is 120 req/min/user). That's still useful data:
      shows the SPN-pool ceiling, not the engine ceiling.

  Total runtime with defaults (5 levels × 2 scenarios × 10 queries × 2 iter):
    - "stress" think-time: ~25-40 min
    - "realistic" think-time: ~90-120 min (matches Microsoft RLTT methodology)

.PARAMETER ThinkTimeMode
  'stress' (3-8s BCS, 0s WCS) — fast, oversamples engine. Good for regression.
  'realistic' (25-40s BCS, 0s WCS) — Microsoft RLTT-style. Good for sign-off.

.PARAMETER ConcurrencyLevels
  Default: 1, 10, 25, 50, 100.

.EXAMPLE
  # After pasting in pwsh:
  .\Standalone-LoadTest.ps1
  # Or with overrides:
  .\Standalone-LoadTest.ps1 -ThinkTimeMode realistic -ConcurrencyLevels 1,10,25
#>

[CmdletBinding()]
param(
    [ValidateSet('stress','realistic')]
    [string]$ThinkTimeMode = 'stress',
    [int[]]$ConcurrencyLevels = @(1,10,25,50,100),
    [int]$IterationsPerUser = 2,
    [int]$TimeoutSec = 120,
    [int]$BatterySize = 5,         # number of base measures (× 2 → 1 unfiltered + 1 filtered each)
    [string]$OutputDir = ".\pbi-loadtest-output"
)

$ErrorActionPreference = 'Stop'
$global:ProgressPreference = 'SilentlyContinue'   # speeds up Invoke-WebRequest

# ─────────────────────────────────────────────────────────────────────────────
# 0. Banner
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " Power BI Standalone Load Test" -ForegroundColor White
Write-Host " Concurrency: $($ConcurrencyLevels -join ', ') | Think-time: $ThinkTimeMode" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# ─────────────────────────────────────────────────────────────────────────────
# 1. Prereqs (Az.Accounts)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "      Az.Accounts not found. Installing for current user (no admin needed)..." -ForegroundColor Yellow
    try {
        Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "      Install-Module failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "      Try manually: Install-Module Az.Accounts -Scope CurrentUser -Force" -ForegroundColor Red
        throw
    }
}
Import-Module Az.Accounts -ErrorAction Stop | Out-Null
Write-Host "      Az.Accounts ready." -ForegroundColor DarkGreen

# ─────────────────────────────────────────────────────────────────────────────
# 2. Interactive config
# ─────────────────────────────────────────────────────────────────────────────
function Read-Guid {
    param([string]$Label, [string]$Help)
    while ($true) {
        Write-Host ""
        Write-Host "  $Label" -ForegroundColor White
        if ($Help) { Write-Host "  ($Help)" -ForegroundColor DarkGray }
        $v = Read-Host "  >"
        $v = $v.Trim()
        # accept either a bare GUID or a Power BI URL containing one
        if ($v -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            return $Matches[1].ToLower()
        }
        Write-Host "  Invalid GUID. Paste either the GUID directly or the Power BI URL containing it." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "[2/7] Configuration" -ForegroundColor Cyan
$tenantId    = Read-Guid -Label "Tenant ID (ctid)" -Help "Look at app.powerbi.com URL: ?ctid=<TENANT_ID>"
$workspaceId = Read-Guid -Label "Workspace ID"     -Help "app.powerbi.com/groups/<WORKSPACE_ID>/..."
$datasetId   = Read-Guid -Label "Dataset ID"       -Help "app.powerbi.com/groups/.../datasets/<DATASET_ID>/..."

Write-Host ""
Write-Host "  Confirmed:" -ForegroundColor White
Write-Host "    tenantId    = $tenantId" -ForegroundColor DarkGray
Write-Host "    workspaceId = $workspaceId" -ForegroundColor DarkGray
Write-Host "    datasetId   = $datasetId" -ForegroundColor DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 3. Auth (interactive browser)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/7] Authenticating (browser will open)..." -ForegroundColor Cyan
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx -or $ctx.Tenant.Id -ne $tenantId) {
    try {
        Connect-AzAccount -TenantId $tenantId -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "      Browser login failed — falling back to device code..." -ForegroundColor Yellow
        Connect-AzAccount -TenantId $tenantId -UseDeviceAuthentication -ErrorAction Stop | Out-Null
    }
}

function Get-PbiToken {
    # Always returns a fresh bearer token for the Power BI service.
    # NB: AccessToken can come back as either [string] or [securestring] depending on Az version.
    $t = Get-AzAccessToken -ResourceUrl "https://analysis.windows.net/powerbi/api" -ErrorAction Stop
    if ($t.Token -is [System.Security.SecureString]) {
        return [System.Net.NetworkCredential]::new('', $t.Token).Password
    }
    return [string]$t.Token
}

$token = Get-PbiToken
Write-Host "      Token acquired (length=$($token.Length))." -ForegroundColor DarkGreen

# ─────────────────────────────────────────────────────────────────────────────
# 4. Output setup
# ─────────────────────────────────────────────────────────────────────────────
$OutputDir = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $OutputDir -Force).FullName).Path
$csvPath   = Join-Path $OutputDir "raw-results.csv"
$reportPath= Join-Path $OutputDir "perf-report.md"
$logPath   = Join-Path $OutputDir "run.log"

if (Test-Path $csvPath) { Remove-Item $csvPath -Force }
"timestamp_iso,level,scenario,virtual_user_id,iteration,query_id,phase,http_status,duration_ms,error_short,filter_value" | Out-File $csvPath -Encoding utf8

# ─────────────────────────────────────────────────────────────────────────────
# 5. Helper: invoke DAX (sync, single call)
# ─────────────────────────────────────────────────────────────────────────────
$endpoint = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/executeQueries"

function Invoke-Dax {
    param([string]$Dax, [string]$Tk, [int]$Timeout = 60)
    $body = @{
        queries = @(@{ query = $Dax })
        serializerSettings = @{ includeNulls = $true }
    } | ConvertTo-Json -Depth 5 -Compress
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $endpoint `
            -Headers @{ Authorization = "Bearer $Tk"; 'Content-Type' = 'application/json' } `
            -Body $body -TimeoutSec $Timeout -SkipHttpErrorCheck -ErrorAction Stop
        $sw.Stop()
        return @{
            ok       = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
            status   = [int]$resp.StatusCode
            ms       = [int]$sw.ElapsedMilliseconds
            body     = $resp.Content
            err      = if ($resp.StatusCode -ge 400) { ($resp.Content | Out-String).Substring(0, [Math]::Min(300, $resp.Content.Length)) } else { $null }
        }
    } catch {
        $sw.Stop()
        return @{ ok = $false; status = -1; ms = [int]$sw.ElapsedMilliseconds; body = $null; err = $_.Exception.Message }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Discovery: measures + filter column
# Three-tier strategy: INFO.* DAX functions → REST tables API → manual input.
# INFO.* requires compat-level >= 1500 (PBI Dec-2023+). Older models (SSAS
# live-connect, legacy migrations) need fallbacks.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/7] Discovering model (measures + filter column)..." -ForegroundColor Cyan

$pickedMeasures = $null
$filterColumn   = $null
$filterValues   = @()
$discoveryMode  = 'unknown'

# ── Tier 1: INFO.MEASURES / INFO.TABLES / INFO.COLUMNS ──────────────────────
Write-Host "      Tier 1: trying INFO.* DAX functions..." -ForegroundColor DarkGray
$measDax = "EVALUATE SELECTCOLUMNS(FILTER(INFO.MEASURES(), [IsHidden] = FALSE()), ""Name"", [Name], ""TableID"", [TableID])"
$mres = Invoke-Dax -Dax $measDax -Tk $token

if ($mres.ok) {
    $mjson = $mres.body | ConvertFrom-Json
    $measureRows = $mjson.results[0].tables[0].rows
    if ($measureRows -and $measureRows.Count -gt 0) {
        # Tables
        $tblDax = "EVALUATE SELECTCOLUMNS(INFO.TABLES(), ""ID"", [ID], ""Name"", [Name])"
        $tres = Invoke-Dax -Dax $tblDax -Tk $token
        if ($tres.ok) {
            $tjson = $tres.body | ConvertFrom-Json
            $tableById = @{}
            foreach ($r in $tjson.results[0].tables[0].rows) {
                $tableById[[string]$r.'[ID]'] = [string]$r.'[Name]'
            }
            $pickedMeasures = $measureRows | Select-Object -First $BatterySize | ForEach-Object {
                [PSCustomObject]@{
                    name  = [string]$_.'[Name]'
                    table = $tableById[[string]$_.'[TableID]']
                }
            }
            $discoveryMode = 'info-dax'
            Write-Host "      Tier 1 OK: INFO.* available." -ForegroundColor DarkGreen
        }
    }
} else {
    Write-Host "      Tier 1 FAILED (HTTP $($mres.status)). Model likely on old compat level. Trying Tier 2..." -ForegroundColor Yellow
}

# ── Tier 2: REST API /datasets/{id}/tables ──────────────────────────────────
if (-not $pickedMeasures) {
    Write-Host "      Tier 2: trying Power BI REST API /tables endpoint..." -ForegroundColor DarkGray
    $tablesUrl = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$datasetId/tables"
    try {
        $tablesResp = Invoke-RestMethod -Method Get -Uri $tablesUrl `
            -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
        $allMeasures = New-Object System.Collections.Generic.List[object]
        foreach ($t in $tablesResp.value) {
            if ($t.measures) {
                foreach ($m in $t.measures) {
                    if (-not $m.isHidden) {
                        $allMeasures.Add([PSCustomObject]@{
                            name  = [string]$m.name
                            table = [string]$t.name
                        }) | Out-Null
                    }
                }
            }
        }
        if ($allMeasures.Count -gt 0) {
            $pickedMeasures = $allMeasures | Select-Object -First $BatterySize
            $discoveryMode = 'rest-tables'
            Write-Host "      Tier 2 OK: REST tables API works." -ForegroundColor DarkGreen
        } else {
            Write-Host "      Tier 2: API responded but no measures found. Trying Tier 3..." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      Tier 2 FAILED: $($_.Exception.Message). Trying Tier 3..." -ForegroundColor Yellow
    }
}

# ── Tier 3: Manual input ────────────────────────────────────────────────────
if (-not $pickedMeasures -or $pickedMeasures.Count -eq 0) {
    Write-Host ""
    Write-Host "      Tier 3: MANUAL INPUT required." -ForegroundColor Yellow
    Write-Host "      Open your report in Power BI Desktop or Service and copy" -ForegroundColor White
    Write-Host "      the names of 3-5 measures you want to test." -ForegroundColor White
    Write-Host ""
    Write-Host "      Format: TableName|MeasureName  (one per line, empty line to finish)" -ForegroundColor White
    Write-Host "      Example:" -ForegroundColor DarkGray
    Write-Host "        Sales|Total Sales" -ForegroundColor DarkGray
    Write-Host "        Sales|YoY %" -ForegroundColor DarkGray
    Write-Host "        Inventory|Stock Value" -ForegroundColor DarkGray
    Write-Host ""

    $manualMeasures = New-Object System.Collections.Generic.List[object]
    while ($true) {
        $line = Read-Host "      measure $($manualMeasures.Count + 1)"
        $line = $line.Trim()
        if (-not $line) {
            if ($manualMeasures.Count -ge 1) { break }
            Write-Host "      Need at least 1 measure." -ForegroundColor Red
            continue
        }
        if ($line -notmatch '^(.+?)\|(.+)$') {
            Write-Host "      Invalid format. Use: TableName|MeasureName" -ForegroundColor Red
            continue
        }
        $manualMeasures.Add([PSCustomObject]@{
            table = $Matches[1].Trim()
            name  = $Matches[2].Trim()
        }) | Out-Null
        if ($manualMeasures.Count -ge $BatterySize) { break }
    }
    $pickedMeasures = $manualMeasures.ToArray()
    $discoveryMode = 'manual'
}

Write-Host "      Picked $($pickedMeasures.Count) measure(s) [mode=$discoveryMode]:" -ForegroundColor DarkGreen
$pickedMeasures | ForEach-Object { Write-Host "        - [$($_.table)] $($_.name)" -ForegroundColor DarkGray }

# ── Filter column discovery ──────────────────────────────────────────────────
Write-Host ""
Write-Host "      Looking for a filter column (for WCS scenario)..." -ForegroundColor DarkGray

# Tier A: probe known table columns via INFO.COLUMNS (only if INFO.* works)
if ($discoveryMode -eq 'info-dax') {
    $colDax = @"
EVALUATE
SELECTCOLUMNS(
    FILTER(
        INFO.COLUMNS(),
        [IsHidden] = FALSE() && [ExplicitDataType] = 2
    ),
    "TableID", [TableID],
    "ExplicitName", [ExplicitName]
)
"@
    $cres = Invoke-Dax -Dax $colDax -Tk $token
    if ($cres.ok) {
        $cjson = $cres.body | ConvertFrom-Json
        $stringCols = $cjson.results[0].tables[0].rows | ForEach-Object {
            [PSCustomObject]@{
                table  = $tableById[[string]$_.'[TableID]']
                column = [string]$_.'[ExplicitName]'
            }
        } | Where-Object { $_.table -and $_.column }

        foreach ($c in ($stringCols | Select-Object -First 30)) {
            $probeDax = "EVALUATE TOPN(50, VALUES('$($c.table)'[$($c.column)]))"
            $pr = Invoke-Dax -Dax $probeDax -Tk $token -Timeout 20
            if (-not $pr.ok) { continue }
            $rows = ($pr.body | ConvertFrom-Json).results[0].tables[0].rows
            if (-not $rows -or $rows.Count -lt 20) { continue }
            $vals = $rows | ForEach-Object { [string]($_.PSObject.Properties | Select-Object -First 1).Value } | Where-Object { $_ -and $_ -ne 'null' }
            if ($vals.Count -ge 20) {
                $filterColumn = $c
                $filterValues = @($vals | Select-Object -Unique)
                break
            }
        }
    }
}

# Tier B: manual filter column input
if (-not $filterColumn) {
    Write-Host ""
    Write-Host "      MANUAL FILTER COLUMN required for WCS scenario." -ForegroundColor Yellow
    Write-Host "      Pick a string/category column with at least 20 distinct values" -ForegroundColor White
    Write-Host "      (e.g. Product[Category], Customer[Country], Date[Month])." -ForegroundColor White
    Write-Host "      Leave EMPTY to skip WCS and test only BCS." -ForegroundColor White
    Write-Host ""
    $line = Read-Host "      filter column (TableName|ColumnName, or empty to skip)"
    $line = $line.Trim()
    if ($line -match '^(.+?)\|(.+)$') {
        $filterColumn = [PSCustomObject]@{
            table  = $Matches[1].Trim()
            column = $Matches[2].Trim()
        }
        # Probe the column to get sample values
        Write-Host "      Probing values from [$($filterColumn.table)].[$($filterColumn.column)]..." -ForegroundColor DarkGray
        $probeDax = "EVALUATE TOPN(50, VALUES('$($filterColumn.table)'[$($filterColumn.column)]))"
        $pr = Invoke-Dax -Dax $probeDax -Tk $token -Timeout 30
        if ($pr.ok) {
            $rows = ($pr.body | ConvertFrom-Json).results[0].tables[0].rows
            if ($rows) {
                $vals = $rows | ForEach-Object { [string]($_.PSObject.Properties | Select-Object -First 1).Value } | Where-Object { $_ -and $_ -ne 'null' }
                $filterValues = @($vals | Select-Object -Unique)
            }
        } else {
            Write-Host "      Probe failed: $($pr.err)" -ForegroundColor Red
            $filterColumn = $null
        }
    }
}

if (-not $filterColumn -or $filterValues.Count -lt 5) {
    Write-Host "      No filter column → only BCS scenario will run." -ForegroundColor Yellow
    $scenarios = @('BCS')
    $filterColumn = $null
    $filterValues = @()
} else {
    Write-Host "      Filter column: [$($filterColumn.table)].[$($filterColumn.column)]  ($($filterValues.Count) sample values)" -ForegroundColor DarkGreen
    $scenarios = @('BCS','WCS')
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Build battery
# ─────────────────────────────────────────────────────────────────────────────
$battery = New-Object System.Collections.Generic.List[object]
$qid = 0
foreach ($m in $pickedMeasures) {
    $qid++
    # Unfiltered query — BCS-only signal, will benefit hugely from cache
    $battery.Add([PSCustomObject]@{
        id        = "Q$($qid)_unfilt"
        wcsCapable= $false
        dax       = "EVALUATE ROW(""v"", CALCULATE([$($m.name)]))"
    })
    if ($filterColumn) {
        $qid++
        # Filtered query — placeholder {{F}} swapped per call
        $dax = "EVALUATE ROW(""v"", CALCULATE([$($m.name)], '$($filterColumn.table)'[$($filterColumn.column)] = {{F}}))"
        $battery.Add([PSCustomObject]@{
            id           = "Q$($qid)_filt"
            wcsCapable   = $true
            dax          = $dax
            filterTable  = $filterColumn.table
            filterColumn = $filterColumn.column
        })
    }
}

# Smoke test: run each query once to validate
Write-Host ""
Write-Host "[5/7] Smoke-testing the battery (1 call per query)..." -ForegroundColor Cyan
$batteryFinal = New-Object System.Collections.Generic.List[object]
foreach ($q in $battery) {
    $daxTry = $q.dax
    if ($q.wcsCapable) {
        $sample = $filterValues[0]
        $lit = "`"$($sample -replace '"','""')`""
        $daxTry = $daxTry -replace '\{\{F\}\}', $lit
    }
    $r = Invoke-Dax -Dax $daxTry -Tk $token -Timeout 30
    if ($r.ok) {
        Write-Host "      OK  $($q.id) → $($r.ms) ms" -ForegroundColor DarkGreen
        $batteryFinal.Add($q)
    } else {
        Write-Host "      SKIP $($q.id) → HTTP $($r.status): $($r.err)" -ForegroundColor Yellow
    }
}
if ($batteryFinal.Count -eq 0) { throw "All battery queries failed smoke. Aborting." }
$battery = $batteryFinal.ToArray()
Write-Host "      Final battery: $($battery.Count) queries." -ForegroundColor DarkGreen

# ─────────────────────────────────────────────────────────────────────────────
# 8. Load test
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[6/7] Load test ($($ConcurrencyLevels -join ', ') × $($scenarios -join '/'))" -ForegroundColor Cyan

# think-time
$thinkBcs = if ($ThinkTimeMode -eq 'realistic') { @(25,40) } else { @(3,8) }
$thinkWcs = @(0,0)

$totalStart = Get-Date
$csvLock = New-Object System.Threading.Mutex($false, "PbiCsvLock_$([guid]::NewGuid().ToString('N'))")

foreach ($level in $ConcurrencyLevels) {
    foreach ($scenario in $scenarios) {

        # Refresh token before every (level, scenario) — long runs can hit
        # the 1h token TTL, and runspaces can't refresh it themselves.
        $token = Get-PbiToken

        $rampSec = [Math]::Max(5, [Math]::Ceiling($level / 10.0))  # 10 users/sec ramp
        $startedAt = Get-Date
        $steadyAt  = $startedAt.AddSeconds($rampSec).ToUniversalTime()

        $thinkRange = if ($scenario -eq 'BCS') { $thinkBcs } else { $thinkWcs }
        $thinkMin = [int]$thinkRange[0]
        $thinkMax = [int]$thinkRange[1]

        Write-Host ""
        Write-Host "  ► Level=$level | Scenario=$scenario | Ramp=$($rampSec)s | Iter/user=$IterationsPerUser" -ForegroundColor White

        $delayPerUser = if ($level -gt 1) { $rampSec / $level } else { 0 }

        $allResults = 1..$level | ForEach-Object -Parallel {
            $u = $_
            $delay = $using:delayPerUser * ($u - 1)
            if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]($delay * 1000)) }

            $local:battery     = $using:battery
            $local:filterVals  = $using:filterValues
            $local:scen        = $using:scenario
            $local:iter        = $using:IterationsPerUser
            $local:ep          = $using:endpoint
            $local:tk          = $using:token
            $local:to          = $using:TimeoutSec
            $local:tmin        = $using:thinkMin
            $local:tmax        = $using:thinkMax
            $local:lvl         = $using:level
            $local:steady      = $using:steadyAt

            $rng = [System.Random]::new($u * 31 + [int]((Get-Date).Ticks % 9973))
            $headers = @{ Authorization = "Bearer $tk"; 'Content-Type' = 'application/json' }
            $out = New-Object System.Collections.Generic.List[object]

            for ($i = 1; $i -le $iter; $i++) {
                foreach ($q in $battery) {

                    # In WCS, skip non-WCS-capable queries (unfiltered ones would
                    # just cache-hit and contaminate the WCS signal).
                    if ($scen -eq 'WCS' -and -not $q.wcsCapable) { continue }

                    $daxToRun = $q.dax
                    $filterUsed = $null
                    if ($q.wcsCapable) {
                        if ($scen -eq 'WCS') {
                            $sample = $filterVals[$rng.Next(0, $filterVals.Count)]
                        } else {
                            $sample = $filterVals[0]  # BCS: stable so caches hit
                        }
                        $lit = '"' + ($sample -replace '"','""') + '"'
                        $daxToRun = $daxToRun -replace '\{\{F\}\}', $lit
                        $filterUsed = $sample
                    }

                    # Think time (BCS only)
                    if ($tmax -gt 0) {
                        $thinkMs = $rng.Next($tmin * 1000, ($tmax + 1) * 1000)
                        Start-Sleep -Milliseconds $thinkMs
                    }

                    $body = @{
                        queries = @(@{ query = $daxToRun })
                        serializerSettings = @{ includeNulls = $true }
                    } | ConvertTo-Json -Depth 5 -Compress

                    $startUtc = (Get-Date).ToUniversalTime()
                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $status = 0
                    $err = $null
                    $attempt = 0
                    $maxAttempts = 4

                    while ($attempt -lt $maxAttempts) {
                        $attempt++
                        try {
                            $resp = Invoke-WebRequest -Method Post -Uri $ep -Headers $headers `
                                -Body $body -TimeoutSec $to -SkipHttpErrorCheck -ErrorAction Stop
                            $status = [int]$resp.StatusCode

                            if (($status -eq 429 -or $status -eq 503) -and $attempt -lt $maxAttempts) {
                                $ra = $null
                                try { $ra = [string]$resp.Headers['Retry-After'] } catch {}
                                $waitMs = if ($ra -and $ra -match '^\d+$') { [int]$ra * 1000 } else {
                                    [int]([Math]::Pow(2, $attempt - 1) * 1000 + $rng.Next(0, 500))
                                }
                                if ($waitMs -gt 30000) { $waitMs = 30000 }
                                Start-Sleep -Milliseconds $waitMs
                                continue
                            }
                            if ($status -ge 400) {
                                $err = "HTTP $status :: " + ($resp.Content | Out-String).Trim()
                                if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
                            }
                            break
                        } catch {
                            if ($attempt -lt $maxAttempts) {
                                Start-Sleep -Milliseconds ([int]([Math]::Pow(2, $attempt-1)*500 + $rng.Next(0,250)))
                                continue
                            }
                            $status = -1
                            $err = $_.Exception.Message
                            if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
                            break
                        }
                    }
                    $sw.Stop()
                    $phase = if ($startUtc -lt $steady) { 'rampup' } else { 'steady' }

                    $out.Add([PSCustomObject]@{
                        timestamp_iso   = $startUtc.ToString('o')
                        level           = $lvl
                        scenario        = $scen
                        virtual_user_id = $u
                        iteration       = $i
                        query_id        = $q.id
                        phase           = $phase
                        http_status     = $status
                        duration_ms     = [int]$sw.ElapsedMilliseconds
                        error_short     = $err
                        filter_value    = $filterUsed
                    }) | Out-Null
                }
            }
            return $out.ToArray()
        } -ThrottleLimit $level

        # write CSV
        if ($allResults) {
            $sb = [System.Text.StringBuilder]::new()
            foreach ($r in $allResults) {
                $e = if ($null -eq $r.error_short) { '' } else { '"' + ($r.error_short -replace '"','""') + '"' }
                $f = if ($null -eq $r.filter_value) { '' } else { '"' + ($r.filter_value -replace '"','""') + '"' }
                [void]$sb.AppendLine("$($r.timestamp_iso),$($r.level),$($r.scenario),$($r.virtual_user_id),$($r.iteration),$($r.query_id),$($r.phase),$($r.http_status),$($r.duration_ms),$e,$f")
            }
            Add-Content -Path $csvPath -Value $sb.ToString().TrimEnd() -Encoding utf8

            $count   = $allResults.Count
            $errCnt  = ($allResults | Where-Object { $_.http_status -ge 400 -or $_.http_status -lt 0 }).Count
            $steadyDurs = $allResults | Where-Object { $_.phase -eq 'steady' -and $_.http_status -ge 200 -and $_.http_status -lt 300 } | ForEach-Object { $_.duration_ms }
            $avg = if ($steadyDurs) { [int]($steadyDurs | Measure-Object -Average).Average } else { 0 }
            Write-Host "    done: $count calls | errors=$errCnt | steady avg=$($avg) ms" -ForegroundColor Green
        } else {
            Write-Host "    done: no results" -ForegroundColor DarkYellow
        }
    }
}

$totalElapsed = (Get-Date) - $totalStart

# ─────────────────────────────────────────────────────────────────────────────
# 9. Aggregate + Markdown report
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[7/7] Aggregating results + writing report..." -ForegroundColor Cyan

# percentile helper
function Get-Percentile {
    param([double[]]$Values, [double]$P)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $rank = ($P / 100.0) * ($sorted.Count - 1)
    $lo = [Math]::Floor($rank); $hi = [Math]::Ceiling($rank)
    if ($lo -eq $hi) { return [int]$sorted[$lo] }
    $w = $rank - $lo
    return [int]($sorted[$lo] * (1 - $w) + $sorted[$hi] * $w)
}

$raw = Import-Csv $csvPath
$summary = New-Object System.Collections.Generic.List[object]
$groups = $raw | Where-Object { $_.phase -eq 'steady' } | Group-Object level, scenario
foreach ($g in $groups) {
    $lvl, $scn = $g.Name -split ', '
    $okDurs = @($g.Group | Where-Object { [int]$_.http_status -ge 200 -and [int]$_.http_status -lt 300 } | ForEach-Object { [double]$_.duration_ms })
    $totalCalls = $g.Group.Count
    $errCount   = ($g.Group | Where-Object { [int]$_.http_status -ge 400 -or [int]$_.http_status -lt 0 }).Count
    $rate429    = ($g.Group | Where-Object { [int]$_.http_status -eq 429 }).Count
    $summary.Add([PSCustomObject]@{
        level    = [int]$lvl
        scenario = $scn
        calls    = $totalCalls
        ok       = $okDurs.Count
        errors   = $errCount
        http429  = $rate429
        p50_ms   = Get-Percentile -Values $okDurs -P 50
        p95_ms   = Get-Percentile -Values $okDurs -P 95
        p99_ms   = Get-Percentile -Values $okDurs -P 99
        max_ms   = if ($okDurs.Count -gt 0) { [int]($okDurs | Measure-Object -Maximum).Maximum } else { $null }
        err_rate = if ($totalCalls -gt 0) { [Math]::Round($errCount * 100.0 / $totalCalls, 2) } else { 0 }
    }) | Out-Null
}

$summary = $summary | Sort-Object level, scenario

# Write MD report
$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# Power BI Load Test Report")
$mdLines.Add("")
$mdLines.Add("**Run timestamp (UTC):** $((Get-Date).ToUniversalTime().ToString('o'))")
$mdLines.Add("**Duration:** $([int]$totalElapsed.TotalMinutes)m $($totalElapsed.Seconds)s")
$mdLines.Add("**Concurrency levels:** $($ConcurrencyLevels -join ', ')")
$mdLines.Add("**Scenarios:** $($scenarios -join ', ')")
$mdLines.Add("**Think-time mode:** $ThinkTimeMode")
$mdLines.Add("")
$mdLines.Add("## Target")
$mdLines.Add("- Tenant: ``$tenantId``")
$mdLines.Add("- Workspace: ``$workspaceId``")
$mdLines.Add("- Dataset: ``$datasetId``")
$mdLines.Add("")
$mdLines.Add("## Battery")
foreach ($q in $battery) {
    $mark = if ($q.wcsCapable) { 'WCS-capable' } else { 'BCS-only' }
    $mdLines.Add("- ``$($q.id)`` ($mark)")
}
$mdLines.Add("")
$mdLines.Add("## Results (steady-state only)")
$mdLines.Add("")
$mdLines.Add("| Level | Scenario | Calls | OK | Errors | 429 | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Err % |")
$mdLines.Add("|------:|:---------|------:|---:|-------:|----:|--------:|--------:|--------:|--------:|------:|")
foreach ($r in $summary) {
    $mdLines.Add("| $($r.level) | $($r.scenario) | $($r.calls) | $($r.ok) | $($r.errors) | $($r.http429) | $($r.p50_ms) | $($r.p95_ms) | $($r.p99_ms) | $($r.max_ms) | $($r.err_rate) |")
}
$mdLines.Add("")
$mdLines.Add("## Notes")
$mdLines.Add("- BCS = Best-Case Scenario (stable filter, caches warm).")
$mdLines.Add("- WCS = Worst-Case Scenario (random filter per call, bypasses query cache).")
$mdLines.Add("- HTTP 429 at high concurrency (>= 50) is expected on a single principal:")
$mdLines.Add("  the executeQueries REST limit is 120 req/min/user. Levels with >=2% 429 should")
$mdLines.Add("  be treated as 'capacity-of-the-test-harness', not 'capacity-of-the-engine'.")
$mdLines.Add("- For methodology details and bottleneck classification, run the full")
$mdLines.Add("  usage-simulator skill with a context profile.")
$mdLines | Out-File $reportPath -Encoding utf8

# Console summary
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " DONE in $([int]$totalElapsed.TotalMinutes)m $($totalElapsed.Seconds)s" -ForegroundColor Green
Write-Host "   Report: $reportPath" -ForegroundColor Green
Write-Host "   Raw:    $csvPath" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
$summary | Format-Table level, scenario, calls, ok, errors, http429, p50_ms, p95_ms, p99_ms, err_rate -AutoSize
