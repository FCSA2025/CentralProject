# Creates D:\MicsEmailStaging on IIS-REMICS-PROD and SMB share for SQL Agent on EC2AMAZ-9DKDM82.
param(
    [string]$StagingRoot = 'D:\MicsEmailStaging',
    [string]$ShareName = 'MicsEmailStaging'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null

$share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if (-not $share) {
    New-SmbShare -Name $ShareName -Path $StagingRoot -FullAccess 'Everyone' -ChangeAccess 'CLOUDMICSDEV\IISReMicsSer' | Out-Null
    Write-Host "Created SMB share \\$env:COMPUTERNAME\$ShareName -> $StagingRoot"
} else {
    Write-Host "Share already exists: \\$env:COMPUTERNAME\$ShareName"
}

icacls $StagingRoot /grant 'Everyone:(OI)(CI)RX' /grant 'CLOUDMICSDEV\IISReMicsSer:(OI)(CI)M' | Out-Null
Write-Host "Staging ready. UNC root: \\$env:COMPUTERNAME\$ShareName"
