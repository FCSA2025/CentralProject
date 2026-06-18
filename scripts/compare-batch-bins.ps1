# Compare batch executable directories (remicsdev)

param(
    [string[]] $Dirs = @('D:\develbat', 'D:\devel\bin', 'D:\prod\bin', 'D:\MicsBatchProgs\MicsBat\_bin\Release')
)

$all = @{}
foreach ($d in $Dirs) {
    if (-not (Test-Path $d)) {
        Write-Warning "Missing: $d"
        continue
    }
    Get-ChildItem $d -Filter *.exe -File -ErrorAction SilentlyContinue | ForEach-Object {
        $key = $_.BaseName.ToLowerInvariant()
        if (-not $all.ContainsKey($key)) {
            $all[$key] = [ordered]@{ Name = $_.BaseName }
        }
        $leaf = Split-Path $d -Leaf
        if ($d -match '_bin') { $leaf = '_bin\Release' }
        $all[$key][$leaf] = $_.Name
    }
}

Write-Host "Executable presence by directory (case-insensitive base name):" -ForegroundColor Cyan
$results = foreach ($key in ($all.Keys | Sort-Object)) {
    $row = [ordered]@{ Program = $all[$key].Name }
    foreach ($d in $Dirs) {
        $leaf = Split-Path $d -Leaf
        if ($d -match '_bin') { $leaf = '_bin\Release' }
        $row[$leaf] = if ($all[$key].Contains($leaf)) { 'Y' } else { '-' }
    }
    [PSCustomObject]$row
}
$results | Format-Table -AutoSize

$onlyStaging = $all.Keys | Where-Object {
    $k = $_
    $all[$k].Contains('_bin\Release') -and -not $all[$k].Contains('develbat') -and -not $all[$k].Contains('bin')
}
Write-Host "`nIn _bin\Release only (not in develbat or devel\bin): $($onlyStaging.Count)" -ForegroundColor Yellow
