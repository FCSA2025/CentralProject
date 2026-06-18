# Extract Session["key"] references from MICS source (remicsdev)
# Usage: .\scripts\extract-session-keys.ps1

$micsRoot = 'D:\inetpub\remicsdev\mics'
$pattern = 'Session\[\s*"([^"]+)"\s*\]'

$keys = @{}
Get-ChildItem $micsRoot -Recurse -Filter *.cs -File |
    Where-Object { $_.FullName -notmatch 'Backup|_vti|\\obj\\' } |
    ForEach-Object {
        $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            foreach ($m in [regex]::Matches($content, $pattern)) {
                $k = $m.Groups[1].Value
                if (-not $keys.ContainsKey($k)) { $keys[$k] = 0 }
                $keys[$k]++
            }
        }
    }

Write-Host "Unique Session keys (excluding Backup folders):" -ForegroundColor Cyan
$keys.GetEnumerator() | Sort-Object Name | ForEach-Object {
    [PSCustomObject]@{ Key = $_.Key; References = $_.Value }
} | Format-Table -AutoSize

Write-Host "Total unique keys: $($keys.Count)"
