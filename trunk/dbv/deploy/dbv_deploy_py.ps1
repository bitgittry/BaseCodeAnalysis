<#
.SYNOPSIS
    This script run dbv_deploy.py python script

.DESCRIPTION
    This script run dbv_deploy.py python script

.EXAMPLE
    PS> .\dbv_deploy_py.ps1
#>
# Enable for local debugging
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

if (Get-Command 'python.exe' -ErrorAction SilentlyContinue)
{
    $p = Start-Process "python.exe" -ArgumentList (Join-Path $currentPath 'dbv_deploy.py') -PassThru -Wait -NoNewWindow
	if ($p.ExitCode -ne 0)
	{
		Write-Error "Something goes wrong calling dbv_deploy.py. Please, check the error message from the python script if available"
	}
}
else
{
    Write-Error "python.exe is not available. Please, install (required version 2.7) and make sure that is available from PATH environment."
}
