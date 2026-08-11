#Requires -Version 5.1
<#
.SYNOPSIS
    Export TSIP parm run samples for report bitmask parity tests.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot '..\tests\remicsdev\fixtures\tsip-parm-samples.tsv'
$dir = Split-Path $out -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$tables = @(
  'frse.tp_agginttest_parm',
  'frse.tp_agt2w_parm',
  'rctl.tp_8up10_parm',
  'hulme.tp_23ghz_parm',
  'xci.tp_b190418a_parm',
  'ftrain.tp_ccexer1_parm'
)

$rows = @('sch	parm	runname	protype	envtype	reports')
foreach ($fq in $tables) {
  $parts = $fq.Split('.')
  $sch = $parts[0]
  $tbl = $parts[1]
  $parm = $tbl -replace '^tp_','' -replace '_parm$',''
  $q = "SELECT TOP 5 RTRIM(runname), RTRIM(protype), RTRIM(envtype), CAST(reports AS VARCHAR(20)) FROM $fq WHERE reports IS NOT NULL ORDER BY runname"
  try {
    $raw = & (Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1') -ReadOnly -Query $q 2>$null
    foreach ($line in $raw) {
      if ($line -match '^\s*runname' -or $line -match '^-+$' -or [string]::IsNullOrWhiteSpace($line)) { continue }
      $cols = $line -split '\|', -1 | ForEach-Object { $_.Trim() }
      if ($cols.Count -ge 4 -and $cols[3] -and $cols[3] -ne 'NULL') {
        $rows += ($sch + "`t" + $parm + "`t" + ($cols -join "`t"))
      }
    }
  } catch {
    Write-Warning "Skip $fq : $_"
  }
}

Set-Content -Path $out -Value $rows -Encoding UTF8
Write-Host ("Exported {0} samples to {1}" -f ($rows.Count - 1), $out)
