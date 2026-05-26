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
  # Pipeline validation, ~30s (auth + discovery, 1 user, BCS only):
  .\Standalone-LoadTest.ps1 -Mode smoke

  # Pre-flight check before full run, ~3-5min (5 users, BCS+WCS):
  .\Standalone-LoadTest.ps1 -Mode test

  # Full baseline run, ~25-40min (1,10,25,50,100 users, BCS+WCS):
  .\Standalone-LoadTest.ps1 -Mode baseline

  # Custom — uses explicit params instead of presets:
  .\Standalone-LoadTest.ps1 -Mode custom -ConcurrencyLevels 1,10,25 -ThinkTimeMode realistic

  # Bring-your-own queries (from Performance Analyzer) — skips discovery entirely:
  .\Standalone-LoadTest.ps1 -Mode test -QueriesPath .\queries
#>

[CmdletBinding()]
param(
    # ─── Mode preset — most users only set this. Overrides Concurrency*/Iterations* below. ──
    # smoke    : 1 user, 1 iter, BCS only (~30 sec) — pipeline validation
    # test     : 5 users, 2/5 iter, BCS+WCS (~5-8 min) — pre-flight check
    # base10   : 1,10 users, 2/5 iter, BCS+WCS (~15-25 min)
    # base25   : 1,10,25 users, 2/5 iter, BCS+WCS (~30-50 min)
    # basefull : 1,10,25,50,100 users, 2/5 iter, BCS+WCS (~1.5-3 h) — production sign-off
    # custom   : use explicit -ConcurrencyLevels / -IterationsPerUser / -WcsIterationsPerUser
    [ValidateSet('smoke','test','base10','base25','basefull','custom')]
    [string]$Mode = 'test',

    # ─── BYOQ folders. One .dax file per query in each folder.
    # -BcsQueriesPath : queries that run in the BCS scenario (stable filters,
    #                   caches warm — measures the "happy path" experience).
    # -WcsQueriesPath : queries that run in the WCS scenario (worst-case stress).
    #                   These get MORE iterations per user (-WcsIterationsPerUser)
    #                   to keep the engine under sustained load on the heaviest
    #                   measures of the report.
    # You can fill only one of the two paths: then only that scenario runs.
    # If neither is set, the script falls back to the legacy discovery-driven
    # path (Tier 1/2/3 of model discovery).
    [string]$BcsQueriesPath = $null,
    [string]$WcsQueriesPath = $null,
    # Backward-compat alias: -QueriesPath behaves as -BcsQueriesPath.
    [string]$QueriesPath = $null,

    # ─── Custom overrides — only effective when -Mode custom (else ignored with a warning). ──
    [ValidateSet('stress','realistic')]
    [string]$ThinkTimeMode = 'stress',
    [int[]]$ConcurrencyLevels = @(1,10,25,50,100),
    [int]$IterationsPerUser = 2,
    [int]$WcsIterationsPerUser = 5,  # WCS iter > BCS iter: sustained pressure on heavy measures
    [int]$TimeoutSec = 180,        # per-call HTTP timeout (sec). 180 covers heavy Performance Analyzer queries.
    [int]$BatterySize = 5,         # number of base measures (× 2 → 1 unfiltered + 1 filtered each)
    [string]$OutputDir = ".\pbi-loadtest-output"
)

# Resolve backward-compat alias: -QueriesPath → -BcsQueriesPath when only the
# legacy parameter is given.
if ($QueriesPath -and -not $BcsQueriesPath) {
    $BcsQueriesPath = $QueriesPath
}

$ErrorActionPreference = 'Stop'
$global:ProgressPreference = 'SilentlyContinue'   # speeds up Invoke-WebRequest

# ─────────────────────────────────────────────────────────────────────────────
# 0a. Interactive Mode prompt if not passed on CLI
# (saves the user from remembering -Mode flag when launching with no args)
# ─────────────────────────────────────────────────────────────────────────────
if (-not $PSBoundParameters.ContainsKey('Mode')) {
    Write-Host ""
    Write-Host "Select run mode:" -ForegroundColor White
    Write-Host "  [1] smoke    — pipeline check, 1 user, ~30 sec" -ForegroundColor DarkGray
    Write-Host "  [2] test     — functional check, 5 users, ~5-8 min" -ForegroundColor DarkGray
    Write-Host "  [3] base10   — baseline up to 10 users, ~15-25 min" -ForegroundColor DarkGray
    Write-Host "  [4] base25   — baseline up to 25 users, ~30-50 min" -ForegroundColor DarkGray
    Write-Host "  [5] basefull — full baseline 1/10/25/50/100 users, ~1.5-3 h" -ForegroundColor DarkGray
    Write-Host "  [6] custom   — use explicit params" -ForegroundColor DarkGray
    while ($true) {
        $sel = Read-Host "  Choice (1/2/3/4/5/6) [default 2]"
        $sel = $sel.Trim()
        if (-not $sel) { $sel = '2' }
        switch ($sel) {
            '1' { $Mode = 'smoke';    break }
            '2' { $Mode = 'test';     break }
            '3' { $Mode = 'base10';   break }
            '4' { $Mode = 'base25';   break }
            '5' { $Mode = 'basefull'; break }
            '6' { $Mode = 'custom';   break }
        }
        if ($Mode) { break }
        Write-Host "  Invalid choice. Type 1-6." -ForegroundColor Red
    }
    Write-Host "  → Mode: $Mode" -ForegroundColor DarkGreen
}

# ─────────────────────────────────────────────────────────────────────────────
# 0b. Apply mode preset (overrides params unless Mode=custom)
# IterationsPerUser     → applies to BCS scenario
# WcsIterationsPerUser  → applies to WCS scenario (typically higher for sustained pressure)
# ─────────────────────────────────────────────────────────────────────────────
$skipWcsByMode = $false   # smoke can force-skip WCS

switch ($Mode) {
    'smoke' {
        # Pipeline validation only. ~30s on any model.
        $ConcurrencyLevels    = @(1)
        $IterationsPerUser    = 1
        $WcsIterationsPerUser = 1
        $ThinkTimeMode        = 'stress'   # ignored — think-time forced 0 below
        $BatterySize          = 2
        $skipWcsByMode        = $true       # smoke is BCS-only by design
        $estDuration          = "~30 seconds"
    }
    'test' {
        # Pre-flight functional check.
        $ConcurrencyLevels    = @(5)
        $IterationsPerUser    = 2
        $WcsIterationsPerUser = 5
        $ThinkTimeMode        = 'stress'
        $BatterySize          = 5
        $estDuration          = "~5-8 minutes"
    }
    'base10' {
        # Baseline progressive up to 10 users.
        $ConcurrencyLevels    = @(1, 10)
        $IterationsPerUser    = 2
        $WcsIterationsPerUser = 5
        $ThinkTimeMode        = 'stress'
        $BatterySize          = 5
        $estDuration          = "~15-25 minutes"
    }
    'base25' {
        # Baseline progressive up to 25 users.
        $ConcurrencyLevels    = @(1, 10, 25)
        $IterationsPerUser    = 2
        $WcsIterationsPerUser = 5
        $ThinkTimeMode        = 'stress'
        $BatterySize          = 5
        $estDuration          = "~30-50 minutes"
    }
    'basefull' {
        # Full baseline — the numbers you ship to stakeholders.
        $ConcurrencyLevels    = @(1, 10, 25, 50, 100)
        $IterationsPerUser    = 2
        $WcsIterationsPerUser = 5
        $ThinkTimeMode        = 'stress'
        $BatterySize          = 5
        $estDuration          = "~1.5-3 hours"
    }
    'custom' {
        # Honor whatever the user passed. No override.
        $estDuration          = "depends on params"
    }
}

# Warn if user passed custom-looking params but didn't set -Mode custom
if ($Mode -ne 'custom') {
    $cliBound = $PSBoundParameters.Keys
    $explicit = $cliBound | Where-Object { $_ -in @('ThinkTimeMode','ConcurrencyLevels','IterationsPerUser','WcsIterationsPerUser','BatterySize') }
    if ($explicit) {
        Write-Host ""
        Write-Host "  WARNING: -Mode $Mode ignores these explicit params: $($explicit -join ', ')" -ForegroundColor Yellow
        Write-Host "           If you want your values to apply, use: -Mode custom" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 0b. Banner
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host " Power BI Standalone Load Test" -ForegroundColor White
Write-Host " Mode: $Mode (est. $estDuration)" -ForegroundColor White
Write-Host " Concurrency: $($ConcurrencyLevels -join ', ')" -ForegroundColor White
Write-Host " Iter/user: BCS=$IterationsPerUser, WCS=$WcsIterationsPerUser | Think-time: $ThinkTimeMode | Battery size: $BatterySize" -ForegroundColor White
if ($BcsQueriesPath) {
    Write-Host " BCS queries: $BcsQueriesPath" -ForegroundColor Magenta
}
if ($WcsQueriesPath) {
    Write-Host " WCS queries: $WcsQueriesPath" -ForegroundColor Magenta
}
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
# 6. Discovery (or BYOQ — bring your own queries)
# BYOQ supports TWO query pools mapped to scenarios:
#   -BcsQueriesPath → folder of .dax files for the BCS scenario
#   -WcsQueriesPath → folder of .dax files for the WCS scenario (heavier load,
#                     more iterations per user — see -WcsIterationsPerUser)
# You can fill one or both. If neither: fall back to model discovery.
# ─────────────────────────────────────────────────────────────────────────────

$pickedMeasures = $null
$filterColumn   = $null
$filterValues   = @()
$discoveryMode  = 'unknown'
$useByoQueries  = $false
$byoBattery     = $null   # populated below if any *QueriesPath is set

# Helper: load .dax files from a folder, tag them with the given scenario bucket.
function Load-DaxFolder {
    param(
        [string]$Path,
        [string]$Bucket,   # 'BCS' or 'WCS'
        [int]$StartId
    )
    if (-not (Test-Path $Path)) { throw "Queries path '$Path' does not exist." }
    $files = Get-ChildItem -Path $Path -Filter "*.dax" -File | Sort-Object Name
    if (-not $files -or $files.Count -eq 0) {
        throw "No .dax files found in '$Path'. Drop one .dax file per query."
    }
    Write-Host "      [$Bucket] Found $($files.Count) .dax file(s) in $Path" -ForegroundColor DarkGreen

    $list = New-Object System.Collections.Generic.List[object]
    $i = $StartId
    foreach ($f in $files) {
        $content = Get-Content -LiteralPath $f.FullName -Raw
        if (-not $content -or $content.Trim().Length -eq 0) {
            Write-Host "      [$Bucket] [skip] $($f.Name) — empty file" -ForegroundColor Yellow
            continue
        }
        $cleanDax = $content -replace '^\s*//[^\r\n]*[\r\n]+',''
        # In the existing loop logic, $wcsCapable=true means "run in WCS scenario".
        # We piggy-back on it: BCS-bucket queries are wcsCapable=false (BCS-only),
        # WCS-bucket queries are wcsCapable=true (WCS-only). The runner already
        # filters per scenario by this flag.
        $list.Add([PSCustomObject]@{
            id           = "Q$($i)_$($Bucket)_$([IO.Path]::GetFileNameWithoutExtension($f.Name))"
            measureName  = $f.BaseName
            measureTable = "(custom-$Bucket)"
            wcsCapable   = ($Bucket -eq 'WCS')
            bucket       = $Bucket
            dax          = $cleanDax
            litStyle     = $null
            sourceFile   = $f.Name
        }) | Out-Null
        $i++
        $preview = $cleanDax.Substring(0, [Math]::Min(80, $cleanDax.Length)) -replace '[\r\n]+', ' '
        Write-Host "        - $($f.Name)  →  $preview..." -ForegroundColor DarkGray
    }
    return $list
}

if ($BcsQueriesPath -or $WcsQueriesPath) {
    Write-Host ""
    Write-Host "[4/7] Loading custom queries (BYOQ mode)..." -ForegroundColor Cyan

    $byoBattery = New-Object System.Collections.Generic.List[object]
    $nextId = 1

    if ($BcsQueriesPath) {
        $bcsItems = Load-DaxFolder -Path $BcsQueriesPath -Bucket 'BCS' -StartId $nextId
        foreach ($q in $bcsItems) { $byoBattery.Add($q) | Out-Null }
        $nextId = $byoBattery.Count + 1
    }
    if ($WcsQueriesPath) {
        $wcsItems = Load-DaxFolder -Path $WcsQueriesPath -Bucket 'WCS' -StartId $nextId
        foreach ($q in $wcsItems) { $byoBattery.Add($q) | Out-Null }
    }

    if ($byoBattery.Count -eq 0) { throw "All .dax files were empty. Aborting." }

    # Decide scenarios based on which folders were populated.
    $bcsCount = ($byoBattery | Where-Object { $_.bucket -eq 'BCS' }).Count
    $wcsCount = ($byoBattery | Where-Object { $_.bucket -eq 'WCS' }).Count
    $scenarios = @()
    if ($bcsCount -gt 0) { $scenarios += 'BCS' }
    if ($wcsCount -gt 0) { $scenarios += 'WCS' }

    $useByoQueries = $true
    $discoveryMode = 'byo-queries'
    Write-Host "      Mode: BYO queries — discovery & filter pool SKIPPED." -ForegroundColor DarkCyan
    Write-Host "      Scenarios to run: $($scenarios -join ', ') (BCS=$bcsCount queries, WCS=$wcsCount queries)" -ForegroundColor DarkCyan
} else {
    Write-Host ""
    Write-Host "[4/7] Discovering model (measures + filter column)..." -ForegroundColor Cyan

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

}  # end of else-branch for $QueriesPath (full discovery path)

# Mode=smoke forces BCS-only — smoke is for pipeline validation, not for
# capturing the WCS signal. Keeps the run under ~30s regardless of model size.
if ($skipWcsByMode -and $scenarios -contains 'WCS') {
    Write-Host "      Mode=smoke → forcing BCS-only (WCS skipped)." -ForegroundColor DarkCyan
    $scenarios = @('BCS')
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Build battery + smoke test with intelligent retries
# ─────────────────────────────────────────────────────────────────────────────

# Detect literal style: try quoted (string), then bare (numeric), then DATE() (date).
# We probe the SAMPLE value, not just guess, so we lock in the right style per column.
function Get-LiteralCandidates($value) {
    $cands = New-Object System.Collections.Generic.List[string]
    $s = [string]$value
    # 1. Quoted string (default)
    $cands.Add('"' + ($s -replace '"','""') + '"') | Out-Null
    # 2. Bare numeric (if parses as number)
    $num = 0.0
    if ([double]::TryParse($s, [ref]$num)) {
        $cands.Add($s) | Out-Null
    }
    # 3. Date literal — DATE(yyyy, M, d)
    $dt = Get-Date
    if ([datetime]::TryParse($s, [ref]$dt)) {
        $cands.Add("DATE($($dt.Year), $($dt.Month), $($dt.Day))") | Out-Null
    }
    return $cands.ToArray()
}

$battery = New-Object System.Collections.Generic.List[object]

if ($useByoQueries) {
    # BYOQ path: queries already constructed from .dax files. No synthesis,
    # no placeholders, no WCS shaping.
    foreach ($q in $byoBattery) { $battery.Add($q) | Out-Null }
} else {
    # Discovery-driven synthesis: build unfilt + filt pairs for each measure.
    $qid = 0
    foreach ($m in $pickedMeasures) {
        $qid++
        # Unfiltered (BCS-only signal — will benefit from query cache)
        $battery.Add([PSCustomObject]@{
            id           = "Q$($qid)_unfilt_$($m.name -replace '[^a-zA-Z0-9]','_')"
            measureName  = $m.name
            measureTable = $m.table
            wcsCapable   = $false
            dax          = "EVALUATE ROW(""v"", CALCULATE([$($m.name)]))"
            litStyle     = $null
        }) | Out-Null
        if ($filterColumn) {
            $qid++
            # Filtered with {{F}} placeholder — literal style TBD by smoke test
            $dax = "EVALUATE ROW(""v"", CALCULATE([$($m.name)], '$($filterColumn.table)'[$($filterColumn.column)] = {{F}}))"
            $battery.Add([PSCustomObject]@{
                id           = "Q$($qid)_filt_$($m.name -replace '[^a-zA-Z0-9]','_')"
                measureName  = $m.name
                measureTable = $m.table
                wcsCapable   = $true
                dax          = $dax
                filterTable  = $filterColumn.table
                filterColumn = $filterColumn.column
                litStyle     = $null   # filled in by smoke test below
            }) | Out-Null
        }
    }
}

# Smoke test: try each query, and for filtered queries try multiple literal styles
# until one works. Persist the working style so the load-test runner uses it.
Write-Host ""
Write-Host "[5/7] Smoke-testing the battery (with auto-retry on filter literal)..." -ForegroundColor Cyan

$smokeLog = New-Object System.Collections.Generic.List[object]
$batteryFinal = New-Object System.Collections.Generic.List[object]

foreach ($q in $battery) {
    # BYOQ queries (either bucket) and discovery-driven unfiltered queries take
    # the same path: single concrete query, no placeholder retry. The 9-combo
    # retry below is reserved for discovery-driven queries that have a {{F}}
    # placeholder needing a literal style + DAX shape probe.
    if (-not $q.wcsCapable -or $q.bucket) {
        $r = Invoke-Dax -Dax $q.dax -Tk $token -Timeout $TimeoutSec
        if ($r.ok) {
            Write-Host "      OK   $($q.id) → $($r.ms) ms" -ForegroundColor DarkGreen
            $batteryFinal.Add($q) | Out-Null
            $smokeLog.Add([PSCustomObject]@{ id=$q.id; result='OK'; ms=$r.ms; status=$r.status; err=$null; litStyle=$null }) | Out-Null
        } else {
            # Full error stored in smokeLog (no truncation), shown in console up to 800 chars.
            $fullErr  = if ($r.err) { [string]$r.err } else { "no detail" }
            $shownErr = if ($fullErr.Length -gt 800) { $fullErr.Substring(0, 800) + " ...[+$($fullErr.Length - 800)ch]" } else { $fullErr }
            Write-Host "      SKIP $($q.id) → HTTP $($r.status):" -ForegroundColor Yellow
            Write-Host "             $shownErr" -ForegroundColor DarkYellow
            # Also print the FIRST 600 chars of the actual DAX that was sent, for inspection.
            $daxPreview = if ($q.dax.Length -gt 600) { $q.dax.Substring(0, 600) + "...[truncated]" } else { $q.dax }
            Write-Host "           DAX sent (first 600 char):" -ForegroundColor DarkYellow
            Write-Host "             $daxPreview" -ForegroundColor DarkGray
            $smokeLog.Add([PSCustomObject]@{ id=$q.id; result='SKIP'; ms=$r.ms; status=$r.status; err=$fullErr; dax=$q.dax; litStyle=$null }) | Out-Null
        }
        continue
    }

    # Filtered — try multiple DAX shapes × multiple literal styles. Each
    # combination addresses a different failure mode we've seen in the wild:
    #   - 'inline'    : CALCULATE([m], 't'[c] = lit)             ← default, most models
    #   - 'filter-fn' : CALCULATE([m], FILTER('t', 't'[c] = lit)) ← when CALCULATE
    #                                                              rejects direct equality
    #                                                              (e.g. table is on
    #                                                              the "many" side of a
    #                                                              broken relationship)
    #   - 'treatas'   : CALCULATE([m], TREATAS({lit}, 't'[c]))    ← when no relationship
    #                                                              exists between filter
    #                                                              table and fact (common
    #                                                              with disconnected dims)
    $sample = $filterValues[0]
    $candidates = Get-LiteralCandidates $sample
    $passed = $false
    $lastErr = $null
    $lastStatus = $null
    $lastMs = $null
    $lastDax = $null
    $winningStyle = $null
    $winningShape = $null
    $allAttempts = New-Object System.Collections.Generic.List[object]

    $tableQ = $q.filterTable
    $colQ   = $q.filterColumn

    foreach ($shape in @('inline', 'filter-fn', 'treatas')) {
        if ($passed) { break }
        for ($ci = 0; $ci -lt $candidates.Count; $ci++) {
            $lit = $candidates[$ci]
            $styleName = if ($ci -eq 0) { 'string' } elseif ($ci -eq 1) { 'numeric' } else { 'date' }

            # Build the actual DAX based on shape (independent of the {{F}} template)
            $daxTry = switch ($shape) {
                'inline'    { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], '$tableQ'[$colQ] = $lit))" }
                'filter-fn' { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], FILTER('$tableQ', '$tableQ'[$colQ] = $lit)))" }
                'treatas'   { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], TREATAS({$lit}, '$tableQ'[$colQ])))" }
            }

            $r = Invoke-Dax -Dax $daxTry -Tk $token -Timeout $TimeoutSec
            $errSnip = if ($r.err) { $r.err.Substring(0, [Math]::Min(400, $r.err.Length)) } else { $null }
            $allAttempts.Add([PSCustomObject]@{
                shape    = $shape
                literal  = $styleName
                status   = $r.status
                ms       = $r.ms
                dax      = $daxTry
                error    = $errSnip
            }) | Out-Null

            if ($r.ok) {
                $passed = $true
                $winningStyle = $styleName
                $winningShape = $shape
                $lastMs = $r.ms
                $lastStatus = $r.status
                # store the working template back on $q so the load-test runner reuses it
                $q.dax = switch ($shape) {
                    'inline'    { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], '$tableQ'[$colQ] = {{F}}))" }
                    'filter-fn' { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], FILTER('$tableQ', '$tableQ'[$colQ] = {{F}})))" }
                    'treatas'   { "EVALUATE ROW(""v"", CALCULATE([$($q.measureName)], TREATAS({{{F}}}, '$tableQ'[$colQ])))" }
                }
                break
            }
            $lastErr = $errSnip
            $lastStatus = $r.status
            $lastMs = $r.ms
            $lastDax = $daxTry
        }
    }

    if ($passed) {
        $q.litStyle = $winningStyle
        Write-Host "      OK   $($q.id) → $lastMs ms (shape: $winningShape, literal: $winningStyle, sample=$sample)" -ForegroundColor DarkGreen
        $batteryFinal.Add($q) | Out-Null
        $smokeLog.Add([PSCustomObject]@{ id=$q.id; result='OK'; ms=$lastMs; status=$lastStatus; err=$null; litStyle=$winningStyle; shape=$winningShape; sample=$sample; attempts=$allAttempts.ToArray() }) | Out-Null
    } else {
        Write-Host "      SKIP $($q.id) → HTTP $lastStatus after $($allAttempts.Count) DAX shapes × literal styles tried." -ForegroundColor Yellow
        Write-Host "           last DAX tried:" -ForegroundColor DarkYellow
        Write-Host "             $lastDax" -ForegroundColor DarkGray
        Write-Host "           last error (400 char max):" -ForegroundColor DarkYellow
        Write-Host "             $lastErr" -ForegroundColor DarkGray
        Write-Host "           sample used: '$sample' (filter column: [$tableQ].[$colQ])" -ForegroundColor DarkYellow
        $smokeLog.Add([PSCustomObject]@{ id=$q.id; result='SKIP'; ms=$lastMs; status=$lastStatus; err=$lastErr; litStyle=$null; shape=$null; sample=$sample; attempts=$allAttempts.ToArray() }) | Out-Null
    }
}

# Smoke is informational only — never aborts the run. If queries fail smoke, the
# load test runs them anyway and you see the errors in raw-results.csv. You
# decide whether to act on smoke failures, not the script.
$smokeFailCount = ($smokeLog | Where-Object { $_.result -eq 'SKIP' }).Count
$smokeOkCount   = ($smokeLog | Where-Object { $_.result -eq 'OK' }).Count

if ($smokeFailCount -gt 0) {
    Write-Host ""
    Write-Host "      WARNING: $smokeFailCount of $($smokeLog.Count) queries failed smoke." -ForegroundColor Yellow
    Write-Host "      Load test will still run them — failures will show up in raw-results.csv." -ForegroundColor Yellow
    if ($smokeOkCount -eq 0) {
        Write-Host "      NOTE: zero queries passed smoke. Expect the load test to produce only errors." -ForegroundColor DarkYellow
        Write-Host "      Inspect discovery.json for full per-query error detail." -ForegroundColor DarkYellow
    }
}

# Use the FULL battery for the load test (not just queries that passed smoke).
# Rationale: smoke failures may be false negatives — REST executeQueries sometimes
# rejects valid queries in cold-start that pass under load, and some queries
# behave differently when an actual analyst-style filter is in effect.
# $batteryFinal still holds the litStyle for filtered queries that DID pass smoke;
# we copy those litStyle hints back onto the full battery here.
foreach ($qOk in $batteryFinal) {
    $match = $battery | Where-Object { $_.id -eq $qOk.id } | Select-Object -First 1
    if ($match) {
        $match.litStyle = $qOk.litStyle
        if ($qOk.dax) { $match.dax = $qOk.dax }   # only filtered queries get DAX shape rewritten by smoke
    }
}
# (battery stays as-is — already a [Object[]] from earlier .ToArray() conversion isn't needed
# since we never called .ToArray() on the original $battery here.)
$battery = $battery.ToArray()

# ─── EXPLICIT BATTERY COMPOSITION SUMMARY ───────────────────────────────────
# Two different framings:
#   - BYOQ mode: queries are split by bucket (BCS folder vs WCS folder).
#   - Discovery mode: queries are split by wcsCapable flag (unfilt vs filt).
$bcsCount = ($battery | Where-Object { $_.bucket -eq 'BCS' -or (-not $_.bucket -and -not $_.wcsCapable) }).Count
$wcsCount = ($battery | Where-Object { $_.bucket -eq 'WCS' -or (-not $_.bucket -and $_.wcsCapable) }).Count

Write-Host ""
Write-Host "      ┌─ Final battery composition ─────────────────────────────┐" -ForegroundColor Cyan
Write-Host "      │  BCS queries (run in BCS scenario): $bcsCount" -ForegroundColor Cyan
Write-Host "      │  WCS queries (run in WCS scenario): $wcsCount" -ForegroundColor Cyan
Write-Host "      │  Iter/user: BCS=$IterationsPerUser, WCS=$WcsIterationsPerUser" -ForegroundColor Cyan
Write-Host "      │  → per user: BCS=$($bcsCount * $IterationsPerUser) calls, WCS=$($wcsCount * $WcsIterationsPerUser) calls" -ForegroundColor Cyan
Write-Host "      └─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

# Drop scenarios that have no queries.
if ($scenarios -contains 'BCS' -and $bcsCount -eq 0) {
    Write-Host ""
    Write-Host "      WARNING: BCS scenario has 0 queries → dropping BCS." -ForegroundColor Yellow
    $scenarios = @($scenarios | Where-Object { $_ -ne 'BCS' })
}
if ($scenarios -contains 'WCS' -and $wcsCount -eq 0) {
    Write-Host ""
    Write-Host "      WARNING: WCS scenario has 0 queries → dropping WCS." -ForegroundColor Yellow
    $scenarios = @($scenarios | Where-Object { $_ -ne 'WCS' })
}

# Persist diagnostic dump for offline analysis
$diagPath = Join-Path $OutputDir "discovery.json"
@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    target = @{ tenant=$tenantId; workspace=$workspaceId; dataset=$datasetId }
    discoveryMode = $discoveryMode
    pickedMeasures = $pickedMeasures
    filterColumn = $filterColumn
    filterValuesCount = $filterValues.Count
    filterValuesSample = ($filterValues | Select-Object -First 10)
    smokeLog = $smokeLog
    finalBattery = $battery | Select-Object id, measureName, measureTable, wcsCapable, litStyle
    scenariosToRun = $scenarios
} | ConvertTo-Json -Depth 6 | Out-File $diagPath -Encoding utf8
Write-Host "      Diagnostic dump saved: $diagPath" -ForegroundColor DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 8. Load test
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[6/7] Load test ($($ConcurrencyLevels -join ', ') × $($scenarios -join '/'))" -ForegroundColor Cyan

# think-time
$thinkBcs = if ($ThinkTimeMode -eq 'realistic') { @(25,40) } else { @(3,8) }
$thinkWcs = @(0,0)

# Mode=smoke forces zero think-time so the validation run finishes fast.
if ($Mode -eq 'smoke') {
    $thinkBcs = @(0,0)
    $thinkWcs = @(0,0)
}

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

        # Pick iterations-per-user based on scenario: BCS uses the standard count,
        # WCS uses the elevated count (sustained pressure on heavier queries).
        $iterForScenario = if ($scenario -eq 'WCS') { $WcsIterationsPerUser } else { $IterationsPerUser }

        Write-Host ""
        Write-Host "  ► Level=$level | Scenario=$scenario | Ramp=$($rampSec)s | Iter/user=$iterForScenario" -ForegroundColor White

        $delayPerUser = if ($level -gt 1) { $rampSec / $level } else { 0 }

        $allResults = 1..$level | ForEach-Object -Parallel {
            $u = $_
            $delay = $using:delayPerUser * ($u - 1)
            if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]($delay * 1000)) }

            $local:battery     = $using:battery
            $local:filterVals  = $using:filterValues
            $local:scen        = $using:scenario
            $local:iter        = $using:iterForScenario
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

                    # Scenario filtering:
                    # - If query has $q.bucket (BYOQ mode), match scenario to bucket
                    #   exactly so BCS-folder queries run only in BCS scenario, and
                    #   WCS-folder queries run only in WCS scenario.
                    # - If query has no bucket (discovery mode, legacy), preserve
                    #   the old logic: WCS scenario keeps only wcsCapable queries.
                    if ($q.bucket) {
                        if ($q.bucket -ne $scen) { continue }
                    } else {
                        if ($scen -eq 'WCS' -and -not $q.wcsCapable) { continue }
                    }

                    $daxToRun = $q.dax
                    $filterUsed = $null
                    if ($q.wcsCapable -and -not $q.bucket) {
                        if ($scen -eq 'WCS') {
                            $sample = $filterVals[$rng.Next(0, $filterVals.Count)]
                        } else {
                            $sample = $filterVals[0]  # BCS: stable so caches hit
                        }
                        # Use the literal style that the smoke test confirmed works
                        # for this column. Falls back to 'string' if unset.
                        $style = if ($q.litStyle) { $q.litStyle } else { 'string' }
                        $lit = switch ($style) {
                            'numeric' { [string]$sample }
                            'date' {
                                $dt = Get-Date
                                if ([datetime]::TryParse([string]$sample, [ref]$dt)) {
                                    "DATE($($dt.Year), $($dt.Month), $($dt.Day))"
                                } else {
                                    '"' + ([string]$sample -replace '"','""') + '"'
                                }
                            }
                            default { '"' + ([string]$sample -replace '"','""') + '"' }
                        }
                        $daxToRun = $q.dax.Replace('{{F}}', $lit)
                        $filterUsed = [string]$sample
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
