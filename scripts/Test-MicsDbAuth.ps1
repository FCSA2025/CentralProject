#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 1 smoke for MicsDbAuth.ps1 (plaintext verify/set/schema).
#>
[CmdletBinding()]
param(
    [string]$PilotMicsId = 'dbautht1',
    [string]$PilotPassword = 'dbauth-test',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'MicsDbAuth.ps1')

$summary = [ordered]@{
    phase = 1
    started_utc = (Get-Date).ToUniversalTime().ToString('o')
    checks = [ordered]@{}
    overall = $false
    notes = New-Object System.Collections.Generic.List[string]
}

$pilot = Ensure-MicsDbPilotUser -MicsId $PilotMicsId -PrimarySchema 'rctl' -Password $PilotPassword
$summary.notes.Add(("Pilot ensured: {0} schema={1}" -f $pilot.micsId, $pilot.PrimarySchema))

$schema = Get-MicsDbPrimarySchema -MicsId $PilotMicsId
$summary.checks.schema = ($schema -eq 'rctl')
if (-not $summary.checks.schema) { $summary.notes.Add("FAIL: PrimarySchema expected rctl got '$schema'") }

$okGood = Test-MicsDbPassword -MicsId $PilotMicsId -Password $PilotPassword
$summary.checks.verify_good = [bool]$okGood
if (-not $okGood) { $summary.notes.Add('FAIL: good password should verify') }

$okBad = Test-MicsDbPassword -MicsId $PilotMicsId -Password 'definitely-wrong-password'
$summary.checks.verify_bad = (-not $okBad)
if ($okBad) { $summary.notes.Add('FAIL: bad password should not verify') }

$tempPwd = 'dbauth-temp-' + (Get-Date -Format 'HHmmss')
Set-MicsDbPassword -MicsId $PilotMicsId -NewPassword $tempPwd | Out-Null
$afterSet = Test-MicsDbPassword -MicsId $PilotMicsId -Password $tempPwd
$oldStill = Test-MicsDbPassword -MicsId $PilotMicsId -Password $PilotPassword
$summary.checks.set_password = ([bool]$afterSet -and -not $oldStill)
if (-not $summary.checks.set_password) { $summary.notes.Add('FAIL: Set-MicsDbPassword did not rotate password') }

# Restore stable pilot password for later phases
Set-MicsDbPassword -MicsId $PilotMicsId -NewPassword $PilotPassword | Out-Null
$restored = Test-MicsDbPassword -MicsId $PilotMicsId -Password $PilotPassword
$summary.checks.restore = [bool]$restored
if (-not $restored) { $summary.notes.Add('FAIL: could not restore pilot password') }

# Inactive rejection: temporarily flip IsActiveYN (restore after)
$idEsc = ($PilotMicsId.Trim() -replace "'", "''")
Invoke-MicsDbAuthSql -Query "UPDATE dbo.t_UserDetails SET IsActiveYN='N' WHERE RTRIM(micsId)='$idEsc'" | Out-Null
$inactiveOk = Test-MicsDbPassword -MicsId $PilotMicsId -Password $PilotPassword
Invoke-MicsDbAuthSql -Query "UPDATE dbo.t_UserDetails SET IsActiveYN='Y' WHERE RTRIM(micsId)='$idEsc'" | Out-Null
$summary.checks.inactive_rejected = (-not $inactiveOk)
if ($inactiveOk) { $summary.notes.Add('FAIL: inactive user should not verify') }

$summary.overall = (
    $summary.checks.schema -and
    $summary.checks.verify_good -and
    $summary.checks.verify_bad -and
    $summary.checks.set_password -and
    $summary.checks.restore -and
    $summary.checks.inactive_rejected
)
$summary.completed_utc = (Get-Date).ToUniversalTime().ToString('o')
if ($summary.overall) { $summary.notes.Add('Phase 1 gate: PASS') } else { $summary.notes.Add('Phase 1 gate: FAIL') }

$resultPath = Join-Path $RepoRoot 'docs\remicsdev\ad-free-auth-phase1-results.json'
[System.IO.File]::WriteAllText($resultPath, ($summary | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

if ($Json) {
    $summary | ConvertTo-Json -Depth 6
} else {
    Write-Host ("Phase 1 overall={0}" -f $summary.overall)
    $summary.checks.GetEnumerator() | ForEach-Object { Write-Host ("  {0}={1}" -f $_.Key, $_.Value) }
    Write-Host ("Results: {0}" -f $resultPath)
    foreach ($n in $summary.notes) { Write-Host ("  - {0}" -f $n) }
}

if (-not $summary.overall) { exit 1 }
exit 0
