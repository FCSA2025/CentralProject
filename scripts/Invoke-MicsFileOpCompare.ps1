#Requires -Version 5.1
<#
.SYNOPSIS
    Run Export/Print, Import, or Validate against a pinned remicsdev fixture and emit compare JSON.

.DESCRIPTION
    CLI wrappers around ftPrint / ftImport / ftValidate using the same MICS env style as
    Invoke-LastTsipCompare.     Writes isolated outputs under D:\inetpub\fcsa\admin\file-ops\{jobTag}\
    and returns a shared verdict schema (ok, match, op, l1/l2/l3, summary).
    After import/validate/roundtrip, drops allowlisted auto-import tables via ftImport -x.
.PARAMETER Op
    print | import | validate | roundtrip (print -> import fresh name -> validate)

.PARAMETER Fixture
    Fixture id from tests/remicsdev/fixtures/baselines.yaml (cat, ecomm2602, ecomm2601b).

.PARAMETER ResultPath
    Optional path for atomic JSON result (admin job polling).

.PARAMETER Json
    Emit compressed JSON on stdout.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('print', 'import', 'validate', 'roundtrip')]
    [string]$Op,

    [string]$Fixture = '',
    [string]$Password = '',
    [switch]$Json,
    [string]$ResultPath = '',
    [int]$TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sqlScript = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$baselinesPath = Join-Path $RepoRoot 'tests\remicsdev\fixtures\baselines.yaml'
$filesRoot = Join-Path $RepoRoot 'tests\remicsdev\fixtures\files'
$fileOpsRoot = 'D:\inetpub\fcsa\admin\file-ops'

$ftPrint = 'D:\develbat\ftPrint.exe'
$ftImport = 'D:\develbat\ftImport.exe'
$ftValidate = 'D:\develbat\ftValidate.exe'

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $RepoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Invoke-SqlRows {
    param([string]$Query)
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $sqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object {
        $_ -and
        $_ -notmatch '^---' -and
        $_ -notmatch '^-+$' -and
        $_ -notmatch '^\(' -and
        $_ -notmatch 'rows affected'
    })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|')
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-+$') { continue }
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = [ordered]@{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $obj[$headers[$ci].Trim()] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Get-SqlScalarInt {
    param([string]$Query, [int]$Default = 0)
    $rows = @(Invoke-SqlRows -Query $Query)
    if ($rows.Count -lt 1) { return $Default }
    $val = $rows[-1] | Select-Object -ExpandProperty c -ErrorAction SilentlyContinue
    if ($null -eq $val) {
        $firstProp = @($rows[-1].PSObject.Properties)[0]
        if ($firstProp) { $val = $firstProp.Value }
    }
    $asText = [string]$val
    if ($asText -match '^-?\d+$') { return [int]$asText }
    return $Default
}

function Write-Result {
    param([hashtable]$Data, [int]$ExitCode = 0)
    $clean = [ordered]@{}
    foreach ($key in $Data.Keys) {
        $val = $Data[$key]
        if ($null -eq $val) {
            $clean[$key] = $null
        } elseif ($val -is [bool] -or $val -is [int] -or $val -is [long] -or $val -is [double]) {
            $clean[$key] = $val
        } else {
            $clean[$key] = [string]$val
        }
    }
    if (-not $clean.Contains('status')) { $clean['status'] = 'complete' }
    if (-not $clean.Contains('op')) { $clean['op'] = $Op }
    $jsonText = ($clean | ConvertTo-Json -Compress -Depth 6)

    if ($ResultPath) {
        $dir = Split-Path -Parent $ResultPath
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        $tmp = "$ResultPath.tmp"
        [System.IO.File]::WriteAllText($tmp, $jsonText, [System.Text.UTF8Encoding]::new($false))
        Move-Item -Path $tmp -Destination $ResultPath -Force
    }

    if ($Json) { $jsonText }
    else { $Data.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value } }
    exit $ExitCode
}

function Read-Baselines {
    if (-not (Test-Path $baselinesPath)) {
        throw "Baselines file not found: $baselinesPath"
    }
    # Minimal YAML reader for our flat-ish baselines structure (no external module).
    $text = Get-Content $baselinesPath -Raw
    $fx = @{}
    $defaults = @{}
    $currentFixture = $null
    $inDefaults = $false
    $inTsip = $false
    foreach ($rawLine in ($text -split "`r?`n")) {
        $line = $rawLine
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^defaults:\s*$') { $inDefaults = $true; $currentFixture = $null; $inTsip = $false; continue }
        if ($line -match '^fixtures:\s*$') { $inDefaults = $false; continue }
        if ($inDefaults -and $line -match '^\s{2}([A-Za-z0-9_]+):\s*(.+)\s*$') {
            $defaults[$Matches[1]] = $Matches[2].Trim().Trim('"')
            continue
        }
        if ($line -match '^\s{2}([A-Za-z0-9_]+):\s*$') {
            $currentFixture = $Matches[1]
            $fx[$currentFixture] = @{ id = $currentFixture; tsip = @{} }
            $inTsip = $false
            $inDefaults = $false
            continue
        }
        if ($null -eq $currentFixture) { continue }
        if ($line -match '^\s{4}tsip:\s*$') { $inTsip = $true; continue }
        if ($inTsip -and $line -match '^\s{6}([A-Za-z0-9_]+):\s*(.+)\s*$') {
            $v = $Matches[2].Trim().Trim('"')
            if ($v -eq 'null') { $v = $null }
            $fx[$currentFixture].tsip[$Matches[1]] = $v
            continue
        }
        if ($line -match '^\s{4}([A-Za-z0-9_]+):\s*(.+)\s*$') {
            $inTsip = $false
            $key = $Matches[1]
            $v = $Matches[2].Trim()
            if ($v -match '^\[(.*)\]$') {
                $fx[$currentFixture][$key] = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
            } else {
                $fx[$currentFixture][$key] = $v.Trim('"')
            }
        }
    }
    return @{ fixtures = $fx; defaults = $defaults }
}

function Set-MicsBatchEnv {
    param([string]$WorkDir, [string]$Project, [string]$Pwd)
    $env:MICSUSER = 'rctl1'
    $env:PASSWORD = $Pwd
    $env:Domain = 'CLOUDMICSDEV'
    $env:odbc = 'remicsdev'
    $env:DBName = 'remicsdev'
    $env:SqlInstance = 'EC2AMAZ-9DKDM82\REMICS_DEV'
    $env:MICS_PROJECT = $Project
    $env:work_dir = $WorkDir
    $env:WORK_DIR = $WorkDir
    $env:webdrive = 'D:'
}

function Get-TableCounts {
    param([string]$Schema, [string]$Table)
    return @{
        sites = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM ${Schema}.ft_${Table}_site"
        chans = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM ${Schema}.ft_${Table}_chan"
        antes = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM ${Schema}.ft_${Table}_ante"
        titl  = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$Schema' AND TABLE_NAME='ft_${Table}_titl'"
    }
}

# Auto-import name prefixes produced by New-ImportTableName (plus legacy bug orphans).
$script:TestTablePrefixes = @('cata', 'e2602a', 'e2601a', 'cat_auto')
$script:PinnedTableRoots = @('cat', 'ecomm2602', 'ecomm2601b')

function New-ImportTableName {
    param([string]$FixtureId)
    # ft_* root names are limited (~16 chars). Keep unique, short auto names.
    $map = @{
        cat        = 'cata'
        ecomm2602  = 'e2602a'
        ecomm2601b = 'e2601a'
    }
    $prefix = if ($map.ContainsKey($FixtureId)) { $map[$FixtureId] } else {
        $clean = ($FixtureId -replace '[^A-Za-z0-9]', '')
        if ($clean.Length -lt 1) { $clean = 'fx' }
        $clean.Substring(0, [Math]::Min(5, $clean.Length)) + 'a'
    }
    $suffix = Get-Date -Format 'HHmmss'
    $name = $prefix + $suffix
    if ($name.Length -gt 16) { $name = $name.Substring(0, 16) }
    return $name
}

function Test-IsAllowlistedTestTableName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.Trim().ToLowerInvariant()
    foreach ($pinned in $script:PinnedTableRoots) {
        if ($n -eq $pinned.ToLowerInvariant()) { return $false }
    }
    foreach ($prefix in $script:TestTablePrefixes) {
        if ($n.StartsWith($prefix.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Test-TableExists {
    param([string]$Schema, [string]$Table)
    $c = Get-SqlScalarInt "SELECT COUNT(*) AS c FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='$Schema' AND TABLE_NAME='ft_${Table}_titl'"
    return ($c -gt 0)
}

function Remove-TestImportTables {
    <#
    .SYNOPSIS
        Drop an allowlisted auto-import table set via ftImport -x (drop then exit).
        Never touches pinned fixture roots (cat, ecomm2602, ecomm2601b).
    #>
    param(
        [string]$ImportRoot,
        [string]$Schema,
        [string]$Project,
        [string]$LogDir
    )
    $result = [ordered]@{
        name    = $ImportRoot
        ok      = $false
        skipped = $false
        message = ''
    }
    if ([string]::IsNullOrWhiteSpace($ImportRoot)) {
        $result.ok = $true
        $result.skipped = $true
        $result.message = 'No import name; nothing to clean up'
        return $result
    }
    if (-not (Test-IsAllowlistedTestTableName -Name $ImportRoot)) {
        $result.ok = $true
        $result.skipped = $true
        $result.message = "Skipped cleanup: '$ImportRoot' is not an allowlisted test table name"
        return $result
    }
    if (-not (Test-Path $ftImport)) {
        $result.message = "ftImport.exe missing; cannot clean up $ImportRoot"
        return $result
    }
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    if (-not (Test-TableExists -Schema $Schema -Table $ImportRoot)) {
        $result.ok = $true
        $result.skipped = $true
        $result.message = "No tables to drop for $ImportRoot"
        return $result
    }
    $junk = Join-Path $LogDir ("cleanup_{0}.junk" -f $ImportRoot)
    Set-Content -Path $junk -Value 'x' -Encoding ASCII
    $run = Invoke-ExeCapture -FilePath $ftImport -ArgumentList @('remicsdev', $Project, $ImportRoot, $junk, '-x') `
        -LogPath (Join-Path $LogDir ("ftImport_cleanup_$ImportRoot"))
    $stillThere = Test-TableExists -Schema $Schema -Table $ImportRoot
    if (-not $stillThere) {
        $result.ok = $true
        $result.message = "Dropped ft_${ImportRoot}_* via ftImport -x (exit $($run.ExitCode))"
    } else {
        $result.ok = $false
        $result.message = "Cleanup failed for $ImportRoot exit=$($run.ExitCode); tables still present"
        if ($run.StdOut) { $result.message += ("`n" + $run.StdOut.Trim()) }
    }
    return $result
}

function Invoke-ExeCapture {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$LogPath)
    $stdout = "$LogPath.out.txt"
    $stderr = "$LogPath.err.txt"
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $outText = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
    $errText = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
    return @{
        ExitCode = $proc.ExitCode
        StdOut   = $outText
        StdErr   = $errText
    }
}

# ---- main ----
if (-not (Test-Path $sqlScript)) {
    Write-Result @{ ok = $false; match = $false; error = "SQL helper missing: $sqlScript" } -ExitCode 1
}

$baselineDoc = Read-Baselines
if (-not $Fixture) {
    switch ($Op) {
        'print' { $Fixture = $baselineDoc.defaults['default_print_fixture'] }
        'import' { $Fixture = $baselineDoc.defaults['default_import_fixture'] }
        'validate' { $Fixture = $baselineDoc.defaults['default_validate_fixture'] }
        default { $Fixture = $baselineDoc.defaults['default_print_fixture'] }
    }
}
if (-not $baselineDoc.fixtures.ContainsKey($Fixture)) {
    Write-Result @{ ok = $false; match = $false; error = "Unknown fixture '$Fixture'" } -ExitCode 1
}
$fx = $baselineDoc.fixtures[$Fixture]
$table = [string]$fx.table
$schema = 'rctl'
$project = 'rctl1_0'
$workDir = "D:\Inetpub\remicsdev\mics\userdirs\$schema\rctl1\"
$expectedBytes = 0
if ($fx.export_bytes -match '^\d+$') { $expectedBytes = [int]$fx.export_bytes }
$minBytes = 1025
if ($fx.min_export_bytes -match '^\d+$') { $minBytes = [int]$fx.min_export_bytes }

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

if (-not (Test-Path $workDir)) {
    Write-Result @{ ok = $false; match = $false; error = "Work dir missing: $workDir" } -ExitCode 1
}

$jobTag = ('{0}_{1}_{2}' -f $Op, $Fixture, (Get-Date -Format 'yyyyMMdd_HHmmss'))
$outDir = Join-Path $fileOpsRoot $jobTag
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Set-MicsBatchEnv -WorkDir $workDir -Project $project -Pwd $Password

$startedUtc = (Get-Date).ToUniversalTime().ToString('o')
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("File-op compare: op=$Op fixture=$Fixture table=$table")
$summary.Add("outputs: $outDir")

$l1 = $false
$l2 = $false
$l3 = $false
$match = $false
$actualBytes = $null
$importName = $null
$printPath = $null
$details = @{}
$cleanup = $null

try {
    switch ($Op) {
        'print' {
            if (-not (Test-Path $ftPrint)) { throw "ftPrint.exe not found at $ftPrint" }
            $printPath = Join-Path $outDir ("{0}.txt" -f $table)
            $run = Invoke-ExeCapture -FilePath $ftPrint -ArgumentList @('remicsdev', $project, ("-o{0}" -f $printPath), 'L', $table) -LogPath (Join-Path $outDir 'ftPrint')
            $l1 = ($run.ExitCode -eq 0)
            $summary.Add(("ftPrint exit={0}" -f $run.ExitCode))
            if (-not (Test-Path $printPath)) { throw "ftPrint produced no output file" }
            $actualBytes = [int](Get-Item $printPath).Length
            $summary.Add(("export bytes={0} (baseline={1}, min={2})" -f $actualBytes, $expectedBytes, $minBytes))
            $l2 = ($actualBytes -gt $minBytes -and $actualBytes -ne 1024)
            if ($actualBytes -eq 1024) { $summary.Add('L2 FAIL: exactly 1024 bytes (historic truncate bug)') }
            $tol = [Math]::Max(32, [int]([Math]::Ceiling($expectedBytes * 0.05)))
            $l3 = ($expectedBytes -gt 0 -and [Math]::Abs($actualBytes - $expectedBytes) -le $tol)
            $summary.Add(("L3 size within +/-{0}: {1}" -f $tol, $l3))
            $golden = Join-Path $filesRoot ([IO.Path]::GetFileName([string]$fx.export_file))
            if (Test-Path $golden) {
                $gLen = (Get-Item $golden).Length
                $summary.Add(("golden file {0} bytes={1}" -f $golden, $gLen))
            }
            $details['print_path'] = $printPath
            $details['stdout'] = $run.StdOut
        }

        'import' {
            if (-not (Test-Path $ftImport)) { throw "ftImport.exe not found at $ftImport" }
            $src = Join-Path $filesRoot ([IO.Path]::GetFileName([string]$fx.export_file))
            if (-not (Test-Path $src)) { throw "Fixture export missing: $src" }
            $importName = New-ImportTableName -FixtureId $Fixture
            $tmpPath = Join-Path $outDir ("{0}.tmp" -f $importName)
            Copy-Item $src $tmpPath -Force
            # Strip blank lines like the web import path.
            $lines = Get-Content $tmpPath | Where-Object { $_ -match '\S' }
            $lines | Set-Content -Path $tmpPath -Encoding ASCII
            $run = Invoke-ExeCapture -FilePath $ftImport -ArgumentList @('remicsdev', $project, $importName, $tmpPath, '-f') -LogPath (Join-Path $outDir 'ftImport')
            $l1 = ($run.ExitCode -eq 0)
            $summary.Add(("ftImport name={0} exit={1}" -f $importName, $run.ExitCode))
            $exists = Test-TableExists -Schema $schema -Table $importName
            $counts = if ($exists) { Get-TableCounts -Schema $schema -Table $importName } else { @{ sites = 0; chans = 0; antes = 0; titl = 0 } }
            $summary.Add(("tables exist={0}; sites={1} chans={2} antes={3}" -f $exists, $counts.sites, $counts.chans, $counts.antes))
            $l2 = ($exists -and $counts.sites -gt 0 -and $counts.chans -gt 0)
            $expSites = 0; $expChans = 0
            if ($fx.sites -match '^\d+$') { $expSites = [int]$fx.sites }
            if ($fx.chans -match '^\d+$') { $expChans = [int]$fx.chans }
            $l3 = ($l2 -and $counts.sites -eq $expSites -and $counts.chans -eq $expChans)
            $summary.Add(("L3 row counts vs baseline sites/chans {0}/{1}: {2}" -f $expSites, $expChans, $l3))
            $details['import_name'] = $importName
            $details['stdout'] = $run.StdOut
            if (-not $l1 -and $run.StdOut) { $summary.Add($run.StdOut.Trim()) }
        }

        'validate' {
            if (-not (Test-Path $ftImport)) { throw "ftImport.exe not found at $ftImport" }
            if (-not (Test-Path $ftValidate)) { throw "ftValidate.exe not found at $ftValidate" }
            # Always import a fresh copy first - FtValidate mutates tables.
            $src = Join-Path $filesRoot ([IO.Path]::GetFileName([string]$fx.export_file))
            if (-not (Test-Path $src)) { throw "Fixture export missing: $src" }
            $importName = New-ImportTableName -FixtureId $Fixture
            $tmpPath = Join-Path $outDir ("{0}.tmp" -f $importName)
            Copy-Item $src $tmpPath -Force
            $lines = Get-Content $tmpPath | Where-Object { $_ -match '\S' }
            $lines | Set-Content -Path $tmpPath -Encoding ASCII
            $imp = Invoke-ExeCapture -FilePath $ftImport -ArgumentList @('remicsdev', $project, $importName, $tmpPath, '-f') -LogPath (Join-Path $outDir 'ftImport')
            if ($imp.ExitCode -ne 0) { throw "Pre-validate import failed: exit $($imp.ExitCode)`n$($imp.StdOut)" }
            $valOut = Join-Path $outDir 'validate.log'
            $run = Invoke-ExeCapture -FilePath $ftValidate -ArgumentList @('remicsdev', $project, $importName, ("-o{0}" -f $valOut)) -LogPath (Join-Path $outDir 'ftValidate')
            $l1 = ($run.ExitCode -eq 0)
            $summary.Add(("ftValidate target={0} exit={1}" -f $importName, $run.ExitCode))
            $l2 = ($l1 -and (Test-Path $valOut))
            # L3: exit 0 and no *ERROR* lines in validate log / stderr (warnings OK).
            $valText = ''
            if (Test-Path $valOut) { $valText = Get-Content $valOut -Raw }
            $hasHardError = ($valText -match '\*ERROR\*') -or ($run.StdOut -match '\*ERROR\*')
            $l3 = ($l1 -and -not $hasHardError)
            $summary.Add(("L3 no *ERROR* markers: {0}" -f $l3))
            $details['import_name'] = $importName
            $details['validate_log'] = $valOut
            $details['stdout'] = $run.StdOut
        }

        'roundtrip' {
            if (-not (Test-Path $ftPrint)) { throw "ftPrint.exe not found" }
            if (-not (Test-Path $ftImport)) { throw "ftImport.exe not found" }
            if (-not (Test-Path $ftValidate)) { throw "ftValidate.exe not found" }

            $printPath = Join-Path $outDir ("{0}_export.txt" -f $table)
            $pr = Invoke-ExeCapture -FilePath $ftPrint -ArgumentList @('remicsdev', $project, ("-o{0}" -f $printPath), 'L', $table) -LogPath (Join-Path $outDir 'ftPrint')
            if ($pr.ExitCode -ne 0) { throw "roundtrip print failed: $($pr.ExitCode)" }
            $actualBytes = [int](Get-Item $printPath).Length
            if ($actualBytes -le $minBytes -or $actualBytes -eq 1024) { throw "roundtrip export size bad: $actualBytes" }

            $importName = New-ImportTableName -FixtureId $Fixture
            $tmpPath = Join-Path $outDir ("{0}.tmp" -f $importName)
            Copy-Item $printPath $tmpPath -Force
            $lines = Get-Content $tmpPath | Where-Object { $_ -match '\S' }
            $lines | Set-Content -Path $tmpPath -Encoding ASCII
            $im = Invoke-ExeCapture -FilePath $ftImport -ArgumentList @('remicsdev', $project, $importName, $tmpPath, '-f') -LogPath (Join-Path $outDir 'ftImport')
            if ($im.ExitCode -ne 0) { throw "roundtrip import failed: $($im.ExitCode)`n$($im.StdOut)" }
            if (-not (Test-TableExists -Schema $schema -Table $importName)) { throw "roundtrip import tables missing" }

            $valOut = Join-Path $outDir 'validate.log'
            $va = Invoke-ExeCapture -FilePath $ftValidate -ArgumentList @('remicsdev', $project, $importName, ("-o{0}" -f $valOut)) -LogPath (Join-Path $outDir 'ftValidate')
            $l1 = ($pr.ExitCode -eq 0 -and $im.ExitCode -eq 0 -and $va.ExitCode -eq 0)
            $counts = Get-TableCounts -Schema $schema -Table $importName
            $l2 = ($actualBytes -gt $minBytes -and $counts.sites -gt 0)
            $expSites = 0; $expChans = 0
            if ($fx.sites -match '^\d+$') { $expSites = [int]$fx.sites }
            if ($fx.chans -match '^\d+$') { $expChans = [int]$fx.chans }
            $l3 = ($counts.sites -eq $expSites -and $counts.chans -eq $expChans -and $va.ExitCode -eq 0)
            $summary.Add(("roundtrip print={0}B import={1} validate_exit={2}" -f $actualBytes, $importName, $va.ExitCode))
            $summary.Add(("counts sites/chans/antes={0}/{1}/{2} (expect {3}/{4})" -f $counts.sites, $counts.chans, $counts.antes, $expSites, $expChans))
            $details['import_name'] = $importName
            $details['print_path'] = $printPath
        }
    }

    $match = ($l1 -and $l2 -and $l3)
    $summary.Add('')
    $summary.Add(("L1={0} L2={1} L3={2}" -f $l1, $l2, $l3))
    if ($match) {
        $summary.Add('OVERALL: MATCH')
    } elseif ($l1 -and $l2 -and -not $l3) {
        $summary.Add('OVERALL: NO MATCH (WARN_DRIFT) - process/structure OK, baseline metrics differ')
    } else {
        $summary.Add('OVERALL: FAILED')
    }

    # Soft cleanup: drop auto-imported tables; never fail the compare verdict on cleanup error.
    if ($importName -and $Op -ne 'print') {
        $cleanup = Remove-TestImportTables -ImportRoot $importName -Schema $schema -Project $project -LogDir $outDir
        $summary.Add(('cleanup: {0}' -f $cleanup.message))
        if (-not $cleanup.ok) {
            $summary.Add('WARN: cleanup failed (compare verdict unchanged)')
        }
    }

    $fullSummary = $summary -join "`n"
    $summaryPath = Join-Path $outDir 'compare-summary.txt'
    [System.IO.File]::WriteAllText($summaryPath, $fullSummary, [System.Text.UTF8Encoding]::new($false))

    Write-Result @{
        ok = $true
        match = $match
        op = $Op
        fixture = $Fixture
        table = $table
        l1 = $l1
        l2 = $l2
        l3 = $l3
        actual_export_bytes = $(if ($null -ne $actualBytes) { $actualBytes } else { $null })
        baseline_export_bytes = $expectedBytes
        import_name = $importName
        cleanup_ok = $(if ($cleanup) { [bool]$cleanup.ok } else { $null })
        cleanup_skipped = $(if ($cleanup) { [bool]$cleanup.skipped } else { $null })
        cleanup_message = $(if ($cleanup) { [string]$cleanup.message } else { $null })
        outputs_dir = $outDir
        compare_summary_path = $summaryPath
        print_path = $printPath
        started_utc = $startedUtc
        summary = $fullSummary
        message = if ($match) { "MATCH ($Op / $Fixture)" } elseif ($l1 -and $l2) { "NO MATCH / WARN_DRIFT ($Op / $Fixture)" } else { "FAILED ($Op / $Fixture)" }
    } -ExitCode 0
}
catch {
    $msg = [string]$_.Exception.Message
    $summary.Add("ERROR: $msg")
    if ($importName -and $Op -ne 'print') {
        try {
            $cleanup = Remove-TestImportTables -ImportRoot $importName -Schema $schema -Project $project -LogDir $outDir
            $summary.Add(('cleanup: {0}' -f $cleanup.message))
        } catch {
            $summary.Add(('cleanup ERROR: {0}' -f $_.Exception.Message))
            $cleanup = [ordered]@{ name = $importName; ok = $false; skipped = $false; message = $_.Exception.Message }
        }
    }
    $fullSummary = $summary -join "`n"
    try {
        [System.IO.File]::WriteAllText((Join-Path $outDir 'compare-summary.txt'), $fullSummary, [System.Text.UTF8Encoding]::new($false))
    } catch { }
    Write-Result @{
        ok = $false
        match = $false
        op = $Op
        fixture = $Fixture
        table = $table
        l1 = $l1
        l2 = $l2
        l3 = $l3
        error = $msg
        outputs_dir = $outDir
        import_name = $importName
        cleanup_ok = $(if ($cleanup) { [bool]$cleanup.ok } else { $null })
        cleanup_skipped = $(if ($cleanup) { [bool]$cleanup.skipped } else { $null })
        cleanup_message = $(if ($cleanup) { [string]$cleanup.message } else { $null })
        started_utc = $startedUtc
        summary = $fullSummary
        message = "FAILED ($Op / $Fixture): $msg"
    } -ExitCode 1
}
