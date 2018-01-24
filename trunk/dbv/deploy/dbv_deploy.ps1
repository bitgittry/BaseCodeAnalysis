<#
.SYNOPSIS
    This script allows to manange database creation/upgrading

.DESCRIPTION
    This script allows to manange database creation/upgrading

.EXAMPLE
    PS> .\dbv_deploy.ps1
#>
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

. (Join-Path $currentPath "dbv_lib.ps1")

function Main
{
    $start_at = Get-Date
    try {
        Write-Host ('*' * 60)
        Write-Host ('dbv_deploy - start at {0}' -f $start_at)
        Write-Host ('*' * 60)

        Deploy-Initialize
    }
    catch [System.Exception] {
        Write-Host ("`n" + ('=' * 60))
        Write-Host "Exception occorred:"
        Write-Host ('-' * 60)
        Write-Host $_.Exception | format-list -force
        Write-Host ("`n" + ('=' * 60))
        throw
    }
    finally {
        $end_at = Get-Date
        Write-Host ("`n" + ('*' * 60))
        Write-Host ('dbv_deploy - end at {0}' -f $end_at)
        Write-Host ('*' * 60)
        Write-Host ("dbv_deploy - duration: {0}`n" -f ($end_at - $start_at))
    }
}

function Deploy-Initialize
{
    Write-Host "dbv_deploy - init"

    # Read config.json
    read_config_json

    # Database apps
    Write-Host ("dbv_deploy - script performed with mysql apps user (octopus) '{0}'" -f $config.db_octopus.mysql_apps.user)
    #extract_revisions '0300900019043'
    build_database_connections_apps
    #cleanup_db_apps
    build_db_apps

    # Database reports
    Write-Host ("dbv_deploy - script performed with mysql reports user (octopus) '{0}'" -f $config.db_octopus.mysql_rep.user)
    build_database_connections_reports
    #cleanup_db_reports
    build_db_reports
}

Main
