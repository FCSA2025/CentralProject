#Requires -Version 5.1
# Step C: SQL grants + userdirs ACL for IISReMicsSer / dbautht1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlHelper = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'
$query = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'CLOUDMICSDEV\IISReMicsSer')
BEGIN
  CREATE USER [CLOUDMICSDEV\IISReMicsSer] FOR LOGIN [CLOUDMICSDEV\IISReMicsSer];
END
GRANT SELECT, UPDATE ON OBJECT::dbo.t_UserDetails TO [CLOUDMICSDEV\IISReMicsSer];
GRANT SELECT ON SCHEMA::adm TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE ON OBJECT::dbo.getnextsession TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE ON OBJECT::dbo.user_project2022 TO [CLOUDMICSDEV\IISReMicsSer];
SELECT 'grants_applied' AS status;
"@

& powershell -NoProfile -ExecutionPolicy Bypass -File $sqlHelper -Query $query

$dirRoot = 'D:\inetpub\remicsdev\mics\userdirs\rctl'
$dirUser = Join-Path $dirRoot 'dbautht1'
New-Item -ItemType Directory -Force -Path $dirUser | Out-Null

foreach ($d in @($dirRoot, $dirUser)) {
    $acl = Get-Acl $d
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'CLOUDMICSDEV\IISReMicsSer',
        'Modify',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $d -AclObject $acl
    Write-Host "ACL OK: $d"
}

Write-Host 'Step C complete'
