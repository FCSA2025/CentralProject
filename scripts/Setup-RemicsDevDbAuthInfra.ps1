#Requires -Version 5.1
# Step C: universal SQL grants + userdirs ACL for IISReMicsSer (all company schemas)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlHelper = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$grantSql = Join-Path $PSScriptRoot '..\docs\remicsdev\ddl\grant-iisremicsser-universal.sql'
& powershell -NoProfile -ExecutionPolicy Bypass -File $sqlHelper -InputFile $grantSql

$dirRoot = 'D:\inetpub\remicsdev\mics\userdirs'
if (-not (Test-Path $dirRoot)) { throw "userdirs not found: $dirRoot" }

$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'CLOUDMICSDEV\IISReMicsSer',
    'Modify',
    'ContainerInherit,ObjectInherit',
    'None',
    'Allow')

$acl = Get-Acl $dirRoot
$acl.SetAccessRule($rule)
Set-Acl -Path $dirRoot -AclObject $acl
Write-Host "ACL OK: $dirRoot"

Get-ChildItem $dirRoot -Directory | ForEach-Object {
    $childAcl = Get-Acl $_.FullName
    $childAcl.SetAccessRule($rule)
    Set-Acl -Path $_.FullName -AclObject $childAcl
    Write-Host "ACL OK: $($_.FullName)"
}

Write-Host 'Step C complete'
