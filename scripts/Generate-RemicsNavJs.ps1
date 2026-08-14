# Emit remics-nav.js in classic TnavigationLeft depth-first order.
$classicPath = 'D:\inetpub\remicsdev\mics\TnavigationLeft.aspx'
$labels = @()
$levels = @()
$depth = 0
$inTree = $false

foreach ($line in Get-Content $classicPath) {
    if ($line -match 'RadTreeView1') { $inTree = $true; continue }
    if (-not $inTree) { continue }
    if ($line -match '</Nodes>\s*</telerik:RadTreeView') { break }

    if ($line -match '<Nodes>') {
        $depth++
        continue
    }
    if ($line -match '</Nodes>') {
        $depth--
        continue
    }
    if ($line -match 'Text="([^"]+)"') {
        $labels += $Matches[1]
        $levels += [Math]::Max(0, $depth - 1)
    }
}

$sdfTypes = @{
    'Antennas'='Ante'; 'Bands'='Band'; 'CTX Patterns'='Ctx'; 'Equipment'='Eqpt'; 'Notes'='Note'
    'Operator'='Oper'; 'Plan'='Plan'; 'Routes'='Rout'; 'Towers'='Towr'; 'Tower Notes'='Town'; 'Traffic'='Traf'
}

$auxTools = @{
    'Passive Calculations'='passive'; 'Pattern'='pattern'; 'PCS Coordination'='pcs'
    'Satellite Bearings'='sat'; 'Separation Angles'='sep'; 'Coordination Checks'='coord'
    'Orbit Intersection'='orbit'; 'Over Horizon Losses'='ohl'; 'NAD27-WGS84 Conversion'='nad27'
    'Terrain Profile'='terrain'; 'Area Coordination'='area'; 'Power Flux Density Contours'='pfd'
    'Generate CTX Curves'='genctx'; 'Check Band HiLo Frequencies'='hilo'
}

$postTsipByIndex = @{
    40='ohl'; 41='terrain'; 42='nad27'; 43='antennaRpe'; 44='ctx'
    45='tsesCsv'; 46='tstsCsv'; 47='tsesKml'; 48='tstsKml'; 49='genctx'
}

$hiddenSectionLabels = @(
    'Reports'
    'FCC Conversion'
    'ISED TS Conversion'
    'ISED Member TS Replacement'
    'ISED ES Conversion'
    'TAFL LAML'
    'COMSEARCH Conversion'
    'Build Radio Catalogue'
    'Maintenance'
    'Accounting Reports'
    'Release Updates'
)

$hiddenLabels = @(
    'Show Users'
    'Test Edit Lookups'
    'Test Datasearch Lookups'
    'Test TSIP Lookups'
)

function Get-Level0RootIndex {
    param([int]$Index)
    for ($i = $Index; $i -ge 0; $i--) {
        if ($levels[$i] -eq 0) { return $i }
    }
    return -1
}

function Test-IsHiddenSection {
    param([int]$Index)
    $rootIdx = Get-Level0RootIndex -Index $Index
    if ($rootIdx -lt 0) { return $false }
    return $hiddenSectionLabels -contains $labels[$rootIdx]
}

function Test-HasChildNodes {
    param([int]$Index)
    if ($Index -ge ($labels.Count - 1)) { return $false }
    return $levels[$Index + 1] -gt $levels[$Index]
}

function Get-NavAction {
    param([int]$Index, [string]$Label)
    if ($postTsipByIndex.ContainsKey($Index)) {
        return @{ view='tsip-post'; query="tool=$($postTsipByIndex[$Index])" }
    }
    switch ($Label) {
        'TS Data Files' { return @{ view='ts-tree' } }
        'ES Data Files' { return @{ view='es-tree' } }
        'Bulk Print TS Data' { return @{ view='bulk-print'; query='filetype=TS' } }
        'Bulk Print ES Data' { return @{ view='bulk-print'; query='filetype=ES' } }
        'TS Data' { return @{ view='ds-ts' } }
        'ES Data' { return @{ view='ds-es' } }
        'Open TSIP Parameter Files' { return @{ view='tsip-parm' } }
        'Retrieve TSIP Batch Reports' { return @{ view='tsip-reps' } }
        'Monitor TSIP' { return @{ view='tsip-batch'; query='monitor=1' } }
        'Delete TSIP Job' { return @{ view='tsip-batch'; query='monitor=1' } }
        'Distance and Bearing' { return @{ view='aux-eng'; query='tool=distance' } }
        'Change Passwords' { return @{ view='change-password' } }
        'Set Up Password Recovery' { return @{ view='pwd-recovery-setup' } }
        'Webmics Help' { return @{ help='micshelp/default.aspx' } }
        'TSIP Reference' { return @{ help='TSIPReference/default.aspx' } }
        'Engineering Considerations' { return @{ help='engineer/default.aspx' } }
        default { }
    }
    if ($Index -ge 8 -and $Index -le 18 -and $sdfTypes.ContainsKey($Label)) {
        return @{ view='sdf-tree'; query="type=$($sdfTypes[$Label])" }
    }
    if ($Index -ge 23 -and $Index -le 33 -and $sdfTypes.ContainsKey($Label)) {
        return @{ view='ds-sdf'; query="type=$($sdfTypes[$Label])" }
    }
    if ($Index -ge 67 -and $Index -le 81 -and $auxTools.ContainsKey($Label)) {
        return @{ view='aux-eng'; query="tool=$($auxTools[$Label])" }
    }
    return $null
}

function Test-HasVisibleChildNodes {
    param([int]$Index)
    for ($j = $Index + 1; $j -lt $labels.Count; $j++) {
        if ($levels[$j] -le $levels[$Index]) { break }
        if (-not (Test-IsHiddenSection -Index $j)) { return $true }
    }
    return $false
}

$dataPath = 'E:\AIProjects\CentralProject\config\remicsdev\source\mics\RemIcsReWrite\js\remics-nav-data.js'
$header = @"
// Generated from TnavigationLeft.aspx - do not edit by hand.
(function (global) {
  global.RemicsNavData = [

"@
$footer = @"

  ];
})(window);
"@
$entryLines = @()
$visibleCount = 0
for ($i = 0; $i -lt $labels.Count; $i++) {
    if (Test-IsHiddenSection -Index $i) { continue }
    if ($labels[$i] -in $hiddenLabels) { continue }
    $label = $labels[$i] -replace "'", "\'"
    $level = $levels[$i]
    $hasChildren = Test-HasVisibleChildNodes -Index $i
    $action = Get-NavAction -Index $i -Label $labels[$i]

    $parts = @("label: '$label'", "level: $level")
    if ($hasChildren) { $parts += 'folder: true' }
    if ($action) {
        if ($action.view) { $parts += "view: '$($action.view)'" }
        if ($action.query) { $parts += "query: '$($action.query)'" }
        if ($action.help) { $parts += "help: '$($action.help)'" }
    } elseif (-not $hasChildren) {
        $parts += 'disabled: true'
    }
    $comma = ','
    $entryLines += "    { $($parts -join ', ') }$comma"
    $visibleCount++
}
if ($entryLines.Count -gt 0) {
    $entryLines[$entryLines.Count - 1] = $entryLines[$entryLines.Count - 1] -replace ',$', ''
}
$content = $header + ($entryLines -join "`n") + $footer
[System.IO.File]::WriteAllText($dataPath, $content)
Write-Output "Wrote $visibleCount nav entries ($($labels.Count - $visibleCount) hidden) to $dataPath"
