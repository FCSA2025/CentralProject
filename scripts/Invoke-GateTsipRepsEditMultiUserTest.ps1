#Requires -Version 5.1
<#
.SYNOPSIS
    Alias for Invoke-GateCTsipRepsEditTest.ps1 (Gate C post-run coverage).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://remicsdev.cloudmicsdev.ca/mics/',
    [string[]]$Users = @('bchy1', 'rctl1', 'xci1'),
    [string]$Password = ''
)

$script = Join-Path $PSScriptRoot 'Invoke-GateCTsipRepsEditTest.ps1'
& $script -BaseUrl $BaseUrl -Users $Users -Password $Password
exit $LASTEXITCODE
