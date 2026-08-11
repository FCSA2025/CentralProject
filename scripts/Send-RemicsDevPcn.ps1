#Requires -Version 5.1
param(
    [string]$User = 'rctl1',
    [string]$Password = 'Welcome#2022',
    [string]$TsName = 'ecomm2601'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$base = 'http://localhost/mics/'
$rewrite = $base + 'RemIcsReWrite/'
$asmx = $base + 'Tfileactions/TwsTabUtil.asmx/'

function Invoke-Asmx {
    param($Session, [string]$Method, [hashtable]$Params)
    $json = ($Params | ConvertTo-Json -Compress)
    $r = Invoke-WebRequest -Uri ($asmx + $Method) -Method POST -Body $json `
        -ContentType 'application/json; charset=utf-8' -WebSession $Session `
        -UseBasicParsing -TimeoutSec 300
    return (($r.Content | ConvertFrom-Json).d)
}

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
Write-Host '=== Login ==='
$null = Invoke-WebRequest -Uri ($rewrite + 'login.aspx') -Method POST `
    -Body @{ user = $User; password = $Password } -WebSession $session `
    -MaximumRedirection 10 -UseBasicParsing -TimeoutSec 120

Write-Host '=== exportTable (optional) ==='
try {
    $ex = Invoke-Asmx $session 'exportTable' @{ filename = $TsName; filetype = 'TS'; projectCode = '' }
    Write-Host $ex
} catch {
    Write-Host "exportTable skipped/failed: $($_.Exception.Message)"
    $exportPath = "D:\Inetpub\remicsdev\mics\userdirs\rctl\$User\$TsName.txt"
    if (-not (Test-Path $exportPath)) {
        $fallback = "D:\Inetpub\remicsdev\mics\userdirs\rctl\rctl3\$TsName.txt"
        if (Test-Path $fallback) {
            Copy-Item -Force $fallback $exportPath
            Write-Host "Copied export from rctl3 to $exportPath"
        }
    }
}

Write-Host '=== PCN scan ==='
$scanR = Invoke-WebRequest -Uri ($rewrite + 'pcn.ashx') -Method POST -Body @{
    action = 'scan'; name = $TsName; filetype = 'TS'; cDist = '200'; projectCode = ''
} -WebSession $session -UseBasicParsing -TimeoutSec 300
$scan = $scanR.Content | ConvertFrom-Json
if (-not $scan.ok) { throw "Scan failed: $($scanR.Content)" }

Write-Host '=== PCN operators ==='
$opsUrl = $rewrite + 'pcn.ashx?action=operators&name=' + $TsName + '&filetype=TS&logserial=' + $scan.logserial
$ops = (Invoke-WebRequest -Uri $opsUrl -WebSession $session -UseBasicParsing).Content | ConvertFrom-Json
if (-not $ops.ok) { throw "Operators failed" }
$toEmails = ($ops.emails | ForEach-Object { $_.display }) -join ';'

Write-Host '=== PCN send ==='
$sendR = Invoke-WebRequest -Uri ($rewrite + 'pcn.ashx') -Method POST -Body @{
    action = 'send'; name = $TsName; filetype = 'TS'; tmpdir = $ops.tmpdir
    notes = 'Test PCN after from-address fix - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    cc = ''; senderEmail = $ops.senderEmail; toEmails = $toEmails; attachKml = '0'
} -WebSession $session -UseBasicParsing -TimeoutSec 300
Write-Host $sendR.Content
