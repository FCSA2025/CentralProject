# Verify batch program name mapping (remicsdev)
# Compares program names referenced in web code against files in D:\develbat

$progDir = 'D:\develbat'
$micsRoot = 'D:\inetpub\remicsdev\mics'

if (-not (Test-Path $progDir)) {
    Write-Error "Batch runtime directory not found: $progDir"
}

Write-Host "Scanning for prog_dir program references..."

$pattern = 'Session\["prog_dir"\]\.ToString\(\)\s*\+\s*"([A-Za-z0-9_.]+)"'
$files = Get-ChildItem $micsRoot -Recurse -Filter *.cs -File |
    Where-Object { $_.FullName -notmatch 'Backup|_vti' }

$nameSet = @{}
foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content) {
        foreach ($m in [regex]::Matches($content, $pattern)) {
            $key = $m.Groups[1].Value
            if (-not $nameSet.ContainsKey($key)) { $nameSet[$key] = $true }
        }
    }
}

$diskFiles = Get-ChildItem $progDir -File
$results = foreach ($name in ($nameSet.Keys | Sort-Object)) {
    $base = $name -replace '\.exe$',''
    $hit = $diskFiles | Where-Object { $_.BaseName -ieq $base } | Select-Object -First 1
    [PSCustomObject]@{
        CodeReference = $name
        FoundOnDisk   = [bool]$hit
        DiskName      = $(if ($hit) { $hit.Name } else { 'MISSING' })
    }
}

$found = @($results | Where-Object { $_.FoundOnDisk }).Count
$missing = @($results | Where-Object { -not $_.FoundOnDisk }).Count

$results | Format-Table -AutoSize
Write-Host "Summary: $found found, $missing missing (of $($results.Count) unique references)"
