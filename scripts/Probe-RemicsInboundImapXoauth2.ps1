#Requires -Version 5.1
<#
.SYNOPSIS
    Phase 0b: obtain Entra client-credentials token and IMAP XOAUTH2 to jscott@fcsa.ca.

.DESCRIPTION
    Loads config/remicsdev/.env.inbound-imap.local (or -EnvFile), requests
    https://outlook.office365.com/.default, then AUTHENTICATE XOAUTH2 on
    outlook.office365.com:993. Does not print secrets or access tokens.

.PARAMETER EnvFile
    Path to env file. Default: repo config/remicsdev/.env.inbound-imap.local
#>
[CmdletBinding()]
param(
    [string]$EnvFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $EnvFile) {
    $EnvFile = Join-Path $RepoRoot 'config\remicsdev\.env.inbound-imap.local'
}
if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Error @"
Missing env file: $EnvFile

Copy docs\remicsdev\inbound-imap.env.example to that path and fill
INBOUND_TENANT_ID, INBOUND_CLIENT_ID, INBOUND_CLIENT_SECRET.
See docs\remicsdev\inbound-imap-xoauth2-setup.md
"@
}

function Import-DotEnvFile {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
    }
}

Import-DotEnvFile -Path $EnvFile

$required = @(
    'INBOUND_TENANT_ID',
    'INBOUND_CLIENT_ID',
    'INBOUND_CLIENT_SECRET',
    'INBOUND_IMAP_USER'
)
foreach ($k in $required) {
    $v = [Environment]::GetEnvironmentVariable($k)
    if ([string]::IsNullOrWhiteSpace($v)) {
        Write-Error "Missing or empty $k in $EnvFile"
    }
}

$hostName = if ($env:INBOUND_IMAP_HOST) { $env:INBOUND_IMAP_HOST } else { 'outlook.office365.com' }
$port = if ($env:INBOUND_IMAP_PORT) { [int]$env:INBOUND_IMAP_PORT } else { 993 }
$scope = if ($env:INBOUND_TOKEN_SCOPE) { $env:INBOUND_TOKEN_SCOPE } else { 'https://outlook.office365.com/.default' }

$py = @'
import imaplib, json, os, ssl, sys, urllib.parse, urllib.request

tenant = os.environ["INBOUND_TENANT_ID"].strip()
client_id = os.environ["INBOUND_CLIENT_ID"].strip()
client_secret = os.environ["INBOUND_CLIENT_SECRET"].strip()
user = os.environ["INBOUND_IMAP_USER"].strip()
host = os.environ.get("INBOUND_IMAP_HOST", "outlook.office365.com").strip()
port = int(os.environ.get("INBOUND_IMAP_PORT", "993"))
scope = os.environ.get("INBOUND_TOKEN_SCOPE", "https://outlook.office365.com/.default").strip()

token_url = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
body = urllib.parse.urlencode({
    "client_id": client_id,
    "client_secret": client_secret,
    "scope": scope,
    "grant_type": "client_credentials",
}).encode("utf-8")

print(f"Token: POST .../{tenant}/oauth2/v2.0/token scope={scope}")
try:
    req = urllib.request.Request(token_url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
except Exception as e:
    err_body = ""
    if hasattr(e, "read"):
        try:
            err_body = e.read().decode("utf-8", errors="replace")
        except Exception:
            pass
    print("TOKEN FAIL:", type(e).__name__, e)
    if err_body:
        print("TOKEN BODY:", err_body[:500])
    sys.exit(2)

token = payload.get("access_token")
if not token:
    print("TOKEN FAIL: no access_token in response keys:", list(payload.keys()))
    sys.exit(2)
print(f"Token: OK (expires_in={payload.get('expires_in')}, token_type={payload.get('token_type')})")

def xoauth2_string(user_name, access_token):
    return f"user={user_name}\x01auth=Bearer {access_token}\x01\x01".encode("utf-8")

ctx = ssl.create_default_context()
print(f"IMAP: connect {host}:{port} as {user}")
try:
    M = imaplib.IMAP4_SSL(host, port, ssl_context=ctx, timeout=60)
    typ, data = M.capability()
    print("CAPABILITY:", typ, (data[0][:180] if data and data[0] else data))
    def auth_cb(_challenge):
        return xoauth2_string(user, token)
    typ, data = M.authenticate("XOAUTH2", auth_cb)
    print("AUTHENTICATE XOAUTH2:", typ, data)
    typ, data = M.select("INBOX", readonly=True)
    print("SELECT INBOX:", typ, data)
    typ, data = M.status("INBOX", "(MESSAGES UNSEEN)")
    print("STATUS:", typ, data)
    M.logout()
    print("RESULT: XOAUTH2 IMAP succeeded")
except imaplib.IMAP4.error as e:
    print("IMAP AUTH/SELECT FAIL:", e)
    print("RESULT: XOAUTH2 rejected (check IMAP.AccessAsApp consent + Exchange New-ServicePrincipal + mailbox FullAccess)")
    sys.exit(1)
except Exception as e:
    print("IMAP ERROR:", type(e).__name__, e)
    sys.exit(3)
'@

$env:INBOUND_IMAP_HOST = $hostName
$env:INBOUND_IMAP_PORT = "$port"
$env:INBOUND_TOKEN_SCOPE = $scope

Write-Host "EnvFile: $EnvFile"
Write-Host "Mailbox: $env:INBOUND_IMAP_USER  Host: ${hostName}:${port}"
python -c $py
$exit = $LASTEXITCODE

# Clear secrets from process env
foreach ($k in @('INBOUND_CLIENT_SECRET', 'INBOUND_CLIENT_ID', 'INBOUND_TENANT_ID')) {
    Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue
}

exit $exit
