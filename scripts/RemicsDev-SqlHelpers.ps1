#Requires -Version 5.1
<#
.SYNOPSIS
    Shared sqlcmd result parsing for remicsdev PowerShell scripts.
#>

function Invoke-RemicsDevSqlScalar {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [string]$SqlScript = (Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1')
    )
    $raw = & $SqlScript -Query $Query 2>&1 | Out-String
    $lines = @($raw -split "`r?`n" | Where-Object { $_ -and $_ -notmatch 'rows affected' -and $_ -notmatch '^\(' -and $_ -notmatch '^Msg ' })
    if ($lines.Count -lt 1) { return $null }

    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^[-|]+$') { $sepIdx = $i; break }
    }
    if ($sepIdx -ge 0 -and ($sepIdx + 1) -lt $lines.Count) {
        $dataLine = $lines[$sepIdx + 1]
        if ($dataLine -match '\|') { return ($dataLine -split '\|' | Select-Object -Last 1).Trim() }
        return $dataLine.Trim()
    }

    $last = $lines[-1]
    if ($last -match '\|') { return ($last -split '\|' | Select-Object -Last 1).Trim() }
    return $last.Trim()
}
