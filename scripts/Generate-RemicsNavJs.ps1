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

# Aux Eng tools are in-shell rewrites. Area Coordination is hidden (classic never shipped).

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
    'Email us'
)

$hiddenLabels = @(
    'Area Coordination'
    'Show Users'
    'Test Edit Lookups'
    'Test Datasearch Lookups'
    'Test TSIP Lookups'
    'Auto Delete TSIP Reports'
    'Database Queries'
    'SQL scripts'
    'SQL to Flat File'
    'Monthly Updates'
    'Monthly Connects'
    'NET Session Info'
    'Documention Forms'
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
        if ($postTsipByIndex[$Index] -eq 'genctx') {
            return @{ view='aux-eng'; query='tool=genctx' }
        }
        if ($postTsipByIndex[$Index] -eq 'ohl') {
            return @{ view='aux-eng'; query='tool=ohl' }
        }
        if ($postTsipByIndex[$Index] -eq 'terrain') {
            return @{ view='aux-eng'; query='tool=terrain' }
        }
        if ($postTsipByIndex[$Index] -eq 'nad27') {
            return @{ view='aux-eng'; query='tool=nad27' }
        }
        if ($postTsipByIndex[$Index] -eq 'antennaRpe') {
            return @{ view='ds-sdf'; query='type=Ante' }
        }
        if ($postTsipByIndex[$Index] -eq 'ctx') {
            return @{ view='ds-sdf'; query='type=Ctx' }
        }
        if ($postTsipByIndex[$Index] -eq 'tsesCsv') {
            return @{ view='tsip-casedet'; query='mode=TSES&kind=csv' }
        }
        if ($postTsipByIndex[$Index] -eq 'tstsCsv') {
            return @{ view='tsip-casedet'; query='mode=TSTS&kind=csv' }
        }
        if ($postTsipByIndex[$Index] -eq 'tsesKml') {
            return @{ view='tsip-casedet'; query='mode=TSES&kind=kml' }
        }
        if ($postTsipByIndex[$Index] -eq 'tstsKml') {
            return @{ view='tsip-casedet'; query='mode=TSTS&kind=kml' }
        }
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
        'Delete TSIP Job' { return @{ view='tsip-batch'; query='monitor=1&delete=1' } }
        'Distance and Bearing' { return @{ view='aux-eng'; query='tool=distance' } }
        'Generate CTX Curves' { return @{ view='aux-eng'; query='tool=genctx' } }
        'Separation Angles' { return @{ view='aux-eng'; query='tool=sep' } }
        'Pattern' { return @{ view='aux-eng'; query='tool=pattern' } }
        'Coordination Checks' { return @{ view='aux-eng'; query='tool=coord' } }
        'PCS Coordination' { return @{ view='aux-eng'; query='tool=pcs' } }
        'Check Band HiLo Frequencies' { return @{ view='aux-eng'; query='tool=hilo' } }
        'NAD27-WGS84 Conversion' { return @{ view='aux-eng'; query='tool=nad27' } }
        'Satellite Bearings' { return @{ view='aux-eng'; query='tool=sat' } }
        'Orbit Intersection' { return @{ view='aux-eng'; query='tool=orbit' } }
        'Over Horizon Losses' { return @{ view='aux-eng'; query='tool=ohl' } }
        'Terrain Profile' { return @{ view='aux-eng'; query='tool=terrain' } }
        'Power Flux Density Contours' { return @{ view='aux-eng'; query='tool=pfd' } }
        'Passive Calculations' { return @{ view='aux-eng'; query='tool=passive' } }
        'Session Timeout' { return @{ view='ses-timeout' } }
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
    return $null
}

function Test-HasVisibleChildNodes {
    param([int]$Index)
    for ($j = $Index + 1; $j -lt $labels.Count; $j++) {
        if ($levels[$j] -le $levels[$Index]) { break }
        if ((Test-IsHiddenSection -Index $j)) { continue }
        if ($labels[$j] -in $hiddenLabels) { continue }
        return $true
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
$nested = @()
foreach ($line in $entryLines) {
    if ($line -match "label: 'Session Timeout'") {
        $nested += $line
        $nested += "    { label: 'Contact Information', level: 2, view: 'contact' },"
        $visibleCount++
        continue
    }
    if ($line -match "label: 'Help', level: 0") {
        $nested += $line
        $nested += "    { label: 'Getting Started', level: 1, view: 'welcome', query: 'start=1' },"
        $visibleCount++
        continue
    }
    if ($line -match "label: 'Change Passwords'") {
        $nested += "    { label: 'User Account Maintenance', level: 1, folder: true },"
        $visibleCount++
        $line = $line -replace "level: 1", "level: 2"
    }
    elseif ($line -match "label: 'Set Up Password Recovery'") {
        $line = $line -replace "level: 1", "level: 2"
    }
    $nested += $line
}
$entryLines = $nested
if ($entryLines.Count -gt 0) {
    $entryLines[$entryLines.Count - 1] = $entryLines[$entryLines.Count - 1] -replace ',$', ''
}
$content = $header + ($entryLines -join "`n") + $footer
[System.IO.File]::WriteAllText($dataPath, $content)
Write-Output "Wrote $visibleCount nav entries ($($labels.Count - $visibleCount) hidden) to $dataPath"
