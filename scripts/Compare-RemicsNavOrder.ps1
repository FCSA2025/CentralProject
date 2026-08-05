$classicPath = 'D:\inetpub\remicsdev\mics\TnavigationLeft.aspx'
$rewritePath = 'E:\AIProjects\CentralProject\config\remicsdev\source\mics\RemIcsReWrite\js\remics-nav-data.js'

$classic = [regex]::Matches((Get-Content $classicPath -Raw), 'Text="([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value }

$navJs = Get-Content $rewritePath -Raw
$rewrite = [regex]::Matches($navJs, "label: '((?:\\'|[^'])*)'") | ForEach-Object { $_.Groups[1].Value -replace "\\'", "'" }

$rewriteMeta = @()
foreach ($m in [regex]::Matches($navJs, "\{ label: '((?:\\'|[^'])*)'([^}]+)\}")) {
    $block = $m.Groups[2].Value
    $rewriteMeta += [pscustomobject]@{
        Label = ($m.Groups[1].Value -replace "\\'", "'")
        Active = ($block -match "view:")
        Disabled = ($block -match 'disabled: true')
        Folder = ($block -match 'folder: true')
    }
}

Write-Output "CLASSIC: $($classic.Count) | REWRITE: $($rewrite.Count)"
Write-Output ''

$matchCount = 0
$diffs = @()
for ($i = 0; $i -lt [Math]::Max($classic.Count, $rewrite.Count); $i++) {
    $c = if ($i -lt $classic.Count) { $classic[$i] } else { $null }
    $r = if ($i -lt $rewrite.Count) { $rewrite[$i] } else { $null }
    if ($c -eq $r) { $matchCount++ } else {
        $diffs += [pscustomobject]@{ Pos = $i + 1; Classic = $c; Rewrite = $r }
    }
}

Write-Output "=== LABEL ORDER MATCH: $matchCount / $($classic.Count) positions ==="
Write-Output ''
if ($diffs.Count -eq 0) {
    Write-Output 'All positions match classic labels.'
} else {
    Write-Output '=== POSITION MISMATCHES ==='
    $diffs | Format-Table -AutoSize
}

$active = @($rewriteMeta | Where-Object { $_.Active })
$disabled = @($rewriteMeta | Where-Object { $_.Disabled })
$folders = @($rewriteMeta | Where-Object { $_.Folder })

Write-Output ''
Write-Output "=== REWRITE NAV SUMMARY ==="
Write-Output "Active (migrated): $($active.Count)"
Write-Output "Disabled stubs: $($disabled.Count)"
Write-Output "Folder nodes: $($folders.Count)"
Write-Output ''

Write-Output '=== ACTIVE ITEMS (migrated, clickable) ==='
$active | ForEach-Object { $_.Label }

Write-Output ''
Write-Output '=== MISSING FROM REWRITE (disabled stubs, not yet migrated) ==='
$disabled | ForEach-Object { $_.Label }

$removed = @(
    'CASEDET Extract', 'Import txt file', 'TS Search', 'ES Search', 'SDF Search',
    'DS Reports (TS)', 'DS Reports (ES)', 'Info Files', 'Bulk Print', 'Monitor Queue',
    'TSIP Parameters', 'Aux Eng tools…', 'Welcome', 'Diagnostic harness', 'System'
)
Write-Output ''
Write-Output '=== OLD REWRITE-ONLY LABELS (removed to match classic order) ==='
$removed | ForEach-Object { Write-Output $_ }
