#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 0 prove path for AD-free DB auth (no remicsdev code changes).

.DESCRIPTION
    - Looks up micsId -> PrimarySchema / IsActiveYN / PasswordSet from dbo.t_UserDetails
    - Optionally ensures pilot user dbautht1
    - Optionally re-runs CLI print + import (existing harness) to prove AD-free batch

.PARAMETER MicsIds
    Users to inspect (default: rctl1, rctl10, dbautht1).

.PARAMETER EnsurePilot
    Create/update dedicated pilot dbautht1 (schema rctl, password dbauth-test).

.PARAMETER RunBatch
    Run Invoke-MicsFileOpCompare print + import for fixture cat.

.PARAMETER Json
    Emit JSON summary on stdout.
#>
[CmdletBinding()]
param(
    [string[]]$MicsIds = @('rctl1', 'rctl10', 'dbautht1'),
    [switch]$EnsurePilot,
    [switch]$RunBatch,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'MicsDbAuth.ps1')

$summary = [ordered]@{
    phase = 0
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    users = @()
    pilot = $null
    batch = $null
    gate = [ordered]@{
        schema_lookup_ok = $false
        known_mapping_ok = $false
        pilot_ready = $false
        batch_ok = $null
        overall = $false
    }
    notes = New-Object System.Collections.Generic.List[string]
}

$summary.notes.Add('Schema source: dbo.t_UserDetails.PrimarySchema only (no user_schema2022).')
$summary.notes.Add('Phase 0 does not modify remicsdev login / JobSubmit / Global.asax.')

if ($EnsurePilot) {
    $pilot = Ensure-MicsDbPilotUser -MicsId 'dbautht1' -PrimarySchema 'rctl' -Password 'dbauth-test'
    $summary.pilot = [ordered]@{
        micsId = [string]$pilot.micsId
        PrimarySchema = [string]$pilot.PrimarySchema
        IsActiveYN = [string]$pilot.IsActiveYN
        PasswordSet = [string]$pilot.PasswordSet
    }
    $summary.notes.Add('Pilot dbautht1 ensured (password not logged).')
}

foreach ($id in $MicsIds) {
    $u = Get-MicsDbUser -MicsId $id
    if ($null -eq $u) {
        $summary.users += [ordered]@{ micsId = $id; found = $false }
        continue
    }
    $summary.users += [ordered]@{
        micsId = [string]$u.micsId
        found = $true
        PrimarySchema = [string]$u.PrimarySchema
        ultrixid = [string]$u.ultrixid
        oper = [string]$u.oper
        IsActiveYN = [string]$u.IsActiveYN
        PasswordSet = [string]$u.PasswordSet
        HashSet = [string]$u.HashSet
    }
}

$foundAny = @($summary.users | Where-Object { $_.found -eq $true }).Count -gt 0
$summary.gate.schema_lookup_ok = $foundAny

$rctl1 = @($summary.users | Where-Object { $_.found -and $_.micsId -eq 'rctl1' }) | Select-Object -First 1
$summary.gate.known_mapping_ok = ($null -ne $rctl1 -and [string]$rctl1.PrimarySchema -eq 'rctl')
if (-not $summary.gate.known_mapping_ok) {
    $summary.notes.Add('FAIL: expected rctl1.PrimarySchema = rctl')
} else {
    $summary.notes.Add('OK: rctl1 PrimarySchema = rctl')
}

$pilotRow = @($summary.users | Where-Object { $_.found -and $_.micsId -eq 'dbautht1' }) | Select-Object -First 1
if ($null -eq $pilotRow -and $null -ne $summary.pilot) {
    $pilotRow = $summary.pilot
}
$summary.gate.pilot_ready = (
    $null -ne $pilotRow -and
    [string]$pilotRow.IsActiveYN -eq 'Y' -and
    [string]$pilotRow.PrimarySchema -eq 'rctl' -and
    [string]$pilotRow.PasswordSet -eq 'Y'
)
if ($EnsurePilot -and -not $summary.gate.pilot_ready) {
    $summary.notes.Add('FAIL: pilot dbautht1 not ready after EnsurePilot')
}

if ($RunBatch) {
    $printScript = Join-Path $PSScriptRoot 'Invoke-MicsFileOpCompare.ps1'
    $printJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $printScript -Op print -Fixture cat -Json 2>&1 | Out-String
    $importJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $printScript -Op import -Fixture cat -Json 2>&1 | Out-String
    $printOk = $printJson -match '"match"\s*:\s*true'
    $importOk = $importJson -match '"match"\s*:\s*true' -and $importJson -match '"cleanup_ok"\s*:\s*true'
    $summary.batch = [ordered]@{
        print_match = [bool]$printOk
        import_match = [bool]$importOk
        note = 'Used existing CLI harness (MICSUSER env; no AD LogonUser).'
    }
    $summary.gate.batch_ok = ($printOk -and $importOk)
    if ($summary.gate.batch_ok) {
        $summary.notes.Add('OK: CLI print+import cat MATCH (AD-free batch path)')
    } else {
        $summary.notes.Add('FAIL: CLI print/import did not MATCH')
    }
} else {
    $summary.notes.Add('Batch skipped (pass -RunBatch to execute CLI prove).')
}

$batchGate = if ($null -eq $summary.gate.batch_ok) { $true } else { [bool]$summary.gate.batch_ok }
$summary.gate.overall = (
    [bool]$summary.gate.schema_lookup_ok -and
    [bool]$summary.gate.known_mapping_ok -and
    $batchGate
)
# Pilot is required only when EnsurePilot was requested
if ($EnsurePilot) {
    $summary.gate.overall = $summary.gate.overall -and [bool]$summary.gate.pilot_ready
}

$summary.completed_utc = (Get-Date).ToUniversalTime().ToString('o')

$docsDir = Join-Path $RepoRoot 'docs\remicsdev'
if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Force -Path $docsDir | Out-Null }
$resultPath = Join-Path $docsDir 'ad-free-auth-phase0-results.json'
$jsonText = ($summary | ConvertTo-Json -Depth 8)
[System.IO.File]::WriteAllText($resultPath, $jsonText, [System.Text.UTF8Encoding]::new($false))

if ($Json) {
    $jsonText
} else {
    Write-Host ("Phase 0 overall={0}" -f $summary.gate.overall)
    Write-Host ("  schema_lookup_ok={0}" -f $summary.gate.schema_lookup_ok)
    Write-Host ("  known_mapping_ok={0}" -f $summary.gate.known_mapping_ok)
    Write-Host ("  pilot_ready={0}" -f $summary.gate.pilot_ready)
    Write-Host ("  batch_ok={0}" -f $summary.gate.batch_ok)
    Write-Host ("Results: {0}" -f $resultPath)
    foreach ($n in $summary.notes) { Write-Host ("  - {0}" -f $n) }
    foreach ($u in $summary.users) {
        if ($u.found) {
            Write-Host ("  user {0}: schema={1} active={2} pwdSet={3}" -f $u.micsId, $u.PrimarySchema, $u.IsActiveYN, $u.PasswordSet)
        } else {
            Write-Host ("  user {0}: NOT FOUND" -f $u.micsId)
        }
    }
}

if (-not $summary.gate.overall) { exit 1 }
exit 0
