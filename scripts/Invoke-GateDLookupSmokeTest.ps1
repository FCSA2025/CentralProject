#Requires -Version 5.1
<#
.SYNOPSIS
    Gate D: lookup JS integrity + rewrite lookup type inventory smoke test.

.DESCRIPTION
    Verifies lookup-js.ashx serves parseable JS (including <= operators in lookuptsip),
    lookup1.aspx uses dynamic cache-bust, and every data-lookup type used in RemIcsReWrite
    resolves to a function in the served lookup bundles.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string]$User = 'bchy1',
    [string]$Password = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-EnvLocalValue {
    param([string]$Key)
    $envFile = Join-Path $repoRoot '.env.local'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

if (-not $Password) { $Password = $env:MICS_TEST_PASSWORD }
if (-not $Password) { $Password = Get-EnvLocalValue 'MICS_TEST_PASSWORD' }
if (-not $Password) { $Password = 'x' }

$base = $BaseUrl.TrimEnd('/') + '/'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/login.aspx') -Method POST -Body @{ user = $User; password = $Password } -WebSession $session -MaximumRedirection 10 -UseBasicParsing

$failures = @()

# --- lookup-js.ashx bundles ---
$bundles = @{
    lookupfcns = $null
    lookuped   = $null
    lookuptsip = $null
}

foreach ($key in @('lookupfcns', 'lookuped', 'lookuptsip')) {
    $url = $base + 'lookupscrns/lookup-js.ashx?f=' + $key + '&v=gateD'
    $resp = Invoke-WebRequest -Uri $url -WebSession $session -UseBasicParsing
    if ($resp.StatusCode -ne 200) {
        $failures += "lookup-js.ashx f=$key returned $($resp.StatusCode)"
        continue
    }
    $body = [string]$resp.Content
    if ($body.Length -lt 500) {
        $failures += "lookup-js.ashx f=$key body too short ($($body.Length) bytes)"
        continue
    }
    if ($body -notmatch 'function\s+\w+') {
        $failures += "lookup-js.ashx f=$key has no function declarations"
        continue
    }
    $bundles[$key] = $body
    Write-Host "OK lookup-js.ashx f=$key ($($body.Length) bytes)"
}

if ($bundles.lookuptsip) {
    if ($bundles.lookuptsip -notmatch '<=') {
        $failures += 'lookuptsip.js missing <= (tag-strip may have broken for-loops)'
    } else {
        Write-Host 'OK lookuptsip.js contains <= operator'
    }
}

$allJs = ($bundles.Values | Where-Object { $_ }) -join "`n"

function Test-LookupFunction {
    param([string]$Type)
    $aliases = @{
        TrafficCode = 'TrafCode'
    }
    $candidates = @($Type)
    if ($aliases.ContainsKey($Type)) { $candidates += $aliases[$Type] }
    foreach ($name in $candidates) {
        if ($allJs -match ('function\s+' + [regex]::Escape($name) + '\s*\(')) { return $true }
    }
    return $false
}

# --- lookup1.aspx dynamic loader ---
$lookupPage = Invoke-WebRequest -Uri ($base + 'lookupscrns/lookup1.aspx') -WebSession $session -UseBasicParsing
if ($lookupPage.Content -notmatch 'loadLookupScripts') {
    $failures += 'lookup1.aspx missing loadLookupScripts (cache-bust policy)'
} else {
    Write-Host 'OK lookup1.aspx dynamic lookup script loader'
}
if ($lookupPage.Content -match 'lookup-js\.ashx\?f=lookupfcns&amp;v=202608') {
    $failures += 'lookup1.aspx still has hardcoded static lookup script tags'
}

# --- inventory data-lookup types from rewrite views + sdf-types ---
$rewriteRoot = Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite'
$lookupTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

Get-ChildItem -Path (Join-Path $rewriteRoot 'views') -Filter '*.html' -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    foreach ($m in [regex]::Matches($content, 'data-lookup="([^"]+)"')) {
        [void]$lookupTypes.Add($m.Groups[1].Value)
    }
}

$sdfTypesPath = Join-Path $rewriteRoot 'js\remics-sdf-types.js'
if (Test-Path $sdfTypesPath) {
    $sdfContent = Get-Content $sdfTypesPath -Raw
    foreach ($m in [regex]::Matches($sdfContent, "lookup:\s*'([^']+)'")) {
        [void]$lookupTypes.Add($m.Groups[1].Value)
    }
}

# Types that use a custom popup instead of lookup1.aspx resolveLookup
$customLookupTypes = @('TsipCallOper')

Write-Host "Inventory: $($lookupTypes.Count) rewrite lookup types"

foreach ($type in ($lookupTypes | Sort-Object)) {
    if ($customLookupTypes -contains $type) {
        Write-Host "OK lookup type $type (custom popup, skipped JS function check)"
        continue
    }
    if (-not (Test-LookupFunction -Type $type)) {
        $failures += "lookup type '$type' has no function in lookup-js bundles"
    } else {
        Write-Host "OK lookup type $type"
    }
}

# --- remics-app.js blur suppress for lookups ---
$appJs = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/js/remics-app.js?v=gateD') -WebSession $session -UseBasicParsing
if ($appJs.Content -notmatch 'suppressBlurForLookupClick') {
    $failures += 'remics-app.js missing suppressBlurForLookupClick'
} else {
    Write-Host 'OK remics-app.js lookup blur suppress'
}

# --- tsip run form: no onfocus traps on proname/envname/tsorbout ---
$runForm = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/js/remics-tsip-run-form.js?v=gateD') -WebSession $session -UseBasicParsing
$runFormFailures = @()
if ($runForm.Content -match "tr-proname'\)\.onfocus\s*=\s*function") {
    $runFormFailures += 'tr-proname onfocus handler'
}
if ($runForm.Content -match "tr-envname'\)\.onfocus\s*=\s*function") {
    $runFormFailures += 'tr-envname onfocus handler'
}
if ($runForm.Content -match "tr-tsorbout'\)\.onfocus\s*=\s*function") {
    $runFormFailures += 'tr-tsorbout onfocus handler'
}
if ($runFormFailures.Count -gt 0) {
    $failures += 'remics-tsip-run-form.js still sets onfocus: ' + ($runFormFailures -join ', ')
} else {
    Write-Host 'OK remics-tsip-run-form.js blur-only focus handlers'
}

# --- import wizard: single consolidated missing-key alert ---
$tsJs = Invoke-WebRequest -Uri ($base + 'RemIcsReWrite/js/remics-ts.js?v=gateD') -WebSession $session -UseBasicParsing
if ($tsJs.Content -notmatch 'function showMissingImportKeys') {
    $failures += 'remics-ts.js missing showMissingImportKeys'
} elseif (($tsJs.Content | Select-String -Pattern 'showMissingImportKeys[\s\S]*?function' -AllMatches).Matches[0].Value -match 'alert\(') {
    $block = [regex]::Match($tsJs.Content, 'function showMissingImportKeys\(up\)\s*\{([\s\S]*?)\n  \}').Groups[1].Value
    $alertCount = ([regex]::Matches($block, '\balert\s*\(')).Count
    if ($alertCount -gt 1) {
        $failures += "showMissingImportKeys still has $alertCount alert() calls (expected 1)"
    } else {
        Write-Host 'OK remics-ts.js consolidated import missing-key alert'
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'FAIL Gate D lookup smoke:'
    $failures | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

Write-Host "PASS Gate D lookup smoke ($User, $($lookupTypes.Count) types)"
