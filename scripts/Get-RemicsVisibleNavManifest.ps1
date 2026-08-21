#Requires -Version 5.1
<#
.SYNOPSIS
    Parse remics-nav-data.js into structured entries for test automation.
#>
param(
    [string]$NavDataPath = ''
)

function Get-RemicsVisibleNavManifest {
    param([string]$Path = '')
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (-not $Path) {
        $Path = Join-Path $repoRoot 'config\remicsdev\source\mics\RemIcsReWrite\js\remics-nav-data.js'
    }
    if (-not (Test-Path $Path)) {
        throw "Nav data not found: $Path"
    }

    $content = Get-Content $Path -Raw
    $entries = @()
    foreach ($m in [regex]::Matches($content, "\{ label: '((?:\\'|[^'])*)'([^}]+)\}")) {
        $block = $m.Groups[2].Value
        $label = $m.Groups[1].Value -replace "\\'", "'"
        $entry = [ordered]@{
            label = $label
            view = $null
            query = $null
            disabled = ($block -match 'disabled: true')
            folder = ($block -match 'folder: true')
        }
        if ($block -match "view: '([^']+)'") { $entry.view = $Matches[1] }
        if ($block -match "query: '([^']+)'") { $entry.query = $Matches[1] }
        $entries += [pscustomobject]$entry
    }

    $postTsipWraps = @{}

    $auxEngWraps = @{}

    function Resolve-NavWrapPath {
        param([string]$View, [string]$Query)
        if ($View -eq 'tsip-post' -and $Query -match '^tool=(.+)$') {
            $tool = $Matches[1]
            if ($postTsipWraps.ContainsKey($tool)) { return $postTsipWraps[$tool] }
        }
        if ($View -eq 'aux-eng' -and $Query -match '^tool=(.+)$') {
            $tool = $Matches[1]
            if ($tool -eq 'nad27') { return $null }
            if ($auxEngWraps.ContainsKey($tool)) { return $auxEngWraps[$tool] }
        }
        return $null
    }

    # Views that open classic popups only — no views/{name}.html shell fragment.
    $wrapOnlyViews = @()

    $active = @($entries | Where-Object { $_.view -and -not $_.disabled })
    $views = @($active | Select-Object -ExpandProperty view -Unique | Where-Object { $wrapOnlyViews -notcontains $_ })
    $wrapChecks = @()
    foreach ($a in $active) {
        $wrapPath = Resolve-NavWrapPath -View $a.view -Query $a.query
        if ($wrapPath) {
            $wrapChecks += [pscustomobject]@{
                label = $a.label
                path = $wrapPath
                view = $a.view
                query = $a.query
            }
        }
    }

    return [pscustomobject]@{
        navDataPath = $Path
        totalEntries = $entries.Count
        activeEntries = $active.Count
        disabledVisible = @($entries | Where-Object { $_.disabled }).Count
        folderEntries = @($entries | Where-Object { $_.folder }).Count
        views = $views
        wrapOnlyViews = $wrapOnlyViews
        active = $active
        wrapChecks = $wrapChecks
        sdfTypes = @($active | Where-Object { $_.view -eq 'sdf-tree' -and $_.query -match 'type=(.+)' } | ForEach-Object {
            if ($_.query -match 'type=(.+)$') { $Matches[1] }
        } | Select-Object -Unique)
        dsSdfTypes = @($active | Where-Object { $_.view -eq 'ds-sdf' -and $_.query -match 'type=(.+)' } | ForEach-Object {
            if ($_.query -match 'type=(.+)$') { $Matches[1] }
        } | Select-Object -Unique)
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Get-RemicsVisibleNavManifest -Path $NavDataPath | Format-List *
}
