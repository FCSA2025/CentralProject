#Requires -Version 5.1
<#
.SYNOPSIS
    CentralProject plaintext DB-auth helpers for dbo.t_UserDetails (Phase 1 AD-free prep).

.DESCRIPTION
    Dot-source this file, then call the exported functions. Schema comes only from
    PrimarySchema — never dbo.user_schema / user_schema2022. Passwords are plaintext
    in the Password column for remicsdev testing; PasswordHash is unused here.

.EXAMPLE
    . .\scripts\MicsDbAuth.ps1
    Get-MicsDbPrimarySchema -MicsId rctl1
    Test-MicsDbPassword -MicsId dbautht1 -Password 'secret'
#>

Set-StrictMode -Version Latest

$script:MicsDbAuth_RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:MicsDbAuth_SqlHelper = Join-Path $PSScriptRoot 'Invoke-RemicsDevSql.ps1'

function Invoke-MicsDbAuthSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query
    )
    if (-not (Test-Path $script:MicsDbAuth_SqlHelper)) {
        throw "SQL helper missing: $($script:MicsDbAuth_SqlHelper)"
    }
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:MicsDbAuth_SqlHelper -Query $Query 2>&1 | Out-String
    return $raw
}

function ConvertFrom-MicsDbAuthSqlTable {
    param([string]$Raw)
    $lines = @($Raw -split "`r?`n" | Where-Object {
        $_ -and
        $_ -notmatch '^---' -and
        $_ -notmatch '^Msg ' -and
        $_ -notmatch '^\(' -and
        $_ -notmatch 'rows affected'
    })
    # Drop decorative separator lines that are only dashes/spaces
    $lines = @($lines | Where-Object { $_ -notmatch '^[\s\-\|]+$' })
    if ($lines.Count -lt 2) { return @() }
    $headers = @($lines[0] -split '\|' | ForEach-Object { $_.Trim() })
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $parts = @($lines[$i] -split '\|')
        if ($parts.Count -lt $headers.Count) { continue }
        $obj = [ordered]@{}
        for ($ci = 0; $ci -lt $headers.Count; $ci++) {
            $obj[$headers[$ci]] = $parts[$ci].Trim()
        }
        $rows += [pscustomobject]$obj
    }
    return $rows
}

function Escape-MicsSqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace "'", "''")
}

function Get-MicsDbUser {
    <#
    .SYNOPSIS
        Load a t_UserDetails row for a micsId (does not return Password value).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MicsId
    )
    $id = Escape-MicsSqlLiteral -Value $MicsId.Trim()
    $q = @"
SELECT
  RTRIM(micsId) AS micsId,
  RTRIM(PrimarySchema) AS PrimarySchema,
  RTRIM(ultrixid) AS ultrixid,
  RTRIM(oper) AS oper,
  RTRIM(IsActiveYN) AS IsActiveYN,
  CASE WHEN Password IS NULL OR RTRIM(Password) = '' THEN 'N' ELSE 'Y' END AS PasswordSet,
  CASE WHEN PasswordHash IS NULL OR RTRIM(CONVERT(NVARCHAR(500), PasswordHash)) = '' THEN 'N' ELSE 'Y' END AS HashSet,
  FailedLoginAttempts,
  CONVERT(VARCHAR(30), LockoutEnd, 126) AS LockoutEnd
FROM dbo.t_UserDetails
WHERE RTRIM(micsId) = '$id'
"@
    $rows = @(ConvertFrom-MicsDbAuthSqlTable -Raw (Invoke-MicsDbAuthSql -Query $q))
    if ($rows.Count -lt 1) { return $null }
    return $rows[0]
}

function Get-MicsDbPrimarySchema {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MicsId
    )
    $user = Get-MicsDbUser -MicsId $MicsId
    if ($null -eq $user) { return $null }
    $schema = [string]$user.PrimarySchema
    if ([string]::IsNullOrWhiteSpace($schema)) { return $null }
    return $schema.Trim()
}

function Test-MicsDbPassword {
    <#
    .SYNOPSIS
        Returns $true if micsId is active and plaintext Password matches (trim-aware).
        Never prints the stored password.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MicsId,
        [Parameter(Mandatory = $true)]
        [string]$Password
    )
    $id = Escape-MicsSqlLiteral -Value $MicsId.Trim()
    $pwd = Escape-MicsSqlLiteral -Value $Password
    # Compare trimmed stored password; require IsActiveYN = Y
    $q = @"
SELECT CASE
  WHEN EXISTS (
    SELECT 1 FROM dbo.t_UserDetails
    WHERE RTRIM(micsId) = '$id'
      AND RTRIM(IsActiveYN) = 'Y'
      AND RTRIM(Password) = RTRIM('$pwd')
  ) THEN 1 ELSE 0 END AS ok
"@
    $rows = @(ConvertFrom-MicsDbAuthSqlTable -Raw (Invoke-MicsDbAuthSql -Query $q))
    if ($rows.Count -lt 1) { return $false }
    $ok = [string]$rows[0].ok
    return ($ok -eq '1')
}

function Set-MicsDbPassword {
    <#
    .SYNOPSIS
        Update plaintext Password for micsId. Leaves PasswordHash unchanged.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MicsId,
        [Parameter(Mandatory = $true)]
        [string]$NewPassword
    )
    if ([string]::IsNullOrWhiteSpace($NewPassword)) {
        throw 'NewPassword must not be empty'
    }
    $id = Escape-MicsSqlLiteral -Value $MicsId.Trim()
    $pwd = Escape-MicsSqlLiteral -Value $NewPassword
    $exists = Get-MicsDbUser -MicsId $MicsId
    if ($null -eq $exists) {
        throw "No dbo.t_UserDetails row for micsId='$($MicsId.Trim())'"
    }
    $q = @"
UPDATE dbo.t_UserDetails
SET Password = '$pwd',
    FailedLoginAttempts = 0,
    LockoutEnd = NULL
WHERE RTRIM(micsId) = '$id';
SELECT @@ROWCOUNT AS c
"@
    $raw = Invoke-MicsDbAuthSql -Query $q
    if ($raw -match 'Msg \d+') {
        throw "Set-MicsDbPassword SQL error: $raw"
    }
    return $true
}

function Ensure-MicsDbPilotUser {
    <#
    .SYNOPSIS
        Ensure a dedicated remicsdev pilot row exists for DB-auth testing (no AD account required).
    #>
    param(
        [string]$MicsId = 'dbautht1',
        [string]$PrimarySchema = 'rctl',
        [string]$Password = 'dbauth-test'
    )
    $id = Escape-MicsSqlLiteral -Value $MicsId.Trim()
    $schema = Escape-MicsSqlLiteral -Value $PrimarySchema.Trim()
    $pwd = Escape-MicsSqlLiteral -Value $Password
    $existing = Get-MicsDbUser -MicsId $MicsId
    if ($null -ne $existing) {
        $q = @"
UPDATE dbo.t_UserDetails
SET PrimarySchema = '$schema',
    ultrixid = '$schema',
    oper = '$schema',
    IsActiveYN = 'Y',
    Password = '$pwd',
    FailedLoginAttempts = 0,
    LockoutEnd = NULL
WHERE RTRIM(micsId) = '$id'
"@
        Invoke-MicsDbAuthSql -Query $q | Out-Null
        Ensure-MicsUserDir -MicsId $MicsId -PrimarySchema $PrimarySchema
        return (Get-MicsDbUser -MicsId $MicsId)
    }

    # ID is smallint identity-like; find next free ID
    $qIns = @"
DECLARE @nid SMALLINT = (SELECT ISNULL(MAX(ID), 0) + 1 FROM dbo.t_UserDetails);
INSERT INTO dbo.t_UserDetails (
  ID, ultrixid, micsId, oper, PrimarySchema, email,
  IsManagerYN, IsMMCRepresentative, IsMTGRepresentative, IsProjectAdmin,
  CentralPointOfContactYN, SendPhantomLinksReportYN, SendMissingLinksReportYN, SendDataDumpYN,
  IsActiveYN, IsFCSAYN, IsContractorYN, EmailIssueYN,
  DateAdded, Password, IsCompanyActiveYN, FailedLoginAttempts
) VALUES (
  @nid, '$schema', '$id', '$schema', '$schema', 'dbautht1@localhost',
  'N','N','N','N',
  'N','N','N','N',
  'Y','N','N','N',
  GETDATE(), '$pwd', 'Y', 0
);
SELECT RTRIM(micsId) AS micsId, RTRIM(PrimarySchema) AS PrimarySchema, RTRIM(IsActiveYN) AS IsActiveYN
FROM dbo.t_UserDetails WHERE RTRIM(micsId) = '$id'
"@
    Invoke-MicsDbAuthSql -Query $qIns | Out-Null
    Ensure-MicsUserDir -MicsId $MicsId -PrimarySchema $PrimarySchema
    return (Get-MicsDbUser -MicsId $MicsId)
}

function Ensure-MicsUserDir {
    <#
    .SYNOPSIS
        Create userdirs\{company}\{micsid} so a new account can import/validate/PCN.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MicsId,
        [string]$PrimarySchema = '',
        [string]$UserDirsRoot = 'D:\Inetpub\remicsdev\mics\userdirs'
    )
    if (-not (Test-Path $UserDirsRoot)) { return $false }
    $company = if ($PrimarySchema) { $PrimarySchema.Trim() } else { '' }
    if (-not $company) {
        $id = $MicsId.ToLowerInvariant()
        $best = $null
        Get-ChildItem $UserDirsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $_.Name.ToLowerInvariant()
            if ($id.StartsWith($p) -and ($null -eq $best -or $p.Length -gt $best.Length)) {
                $best = $_.Name
            }
        }
        $company = $best
    }
    if (-not $company) { return $false }
    $companyPath = Join-Path $UserDirsRoot $company
    $userPath = Join-Path $companyPath $MicsId.Trim()
    if (-not (Test-Path $companyPath)) {
        New-Item -ItemType Directory -Path $companyPath | Out-Null
    }
    if (-not (Test-Path $userPath)) {
        New-Item -ItemType Directory -Path $userPath | Out-Null
    }
    return $true
}
