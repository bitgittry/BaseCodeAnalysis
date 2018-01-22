<#
.SYNOPSIS
    This script allows to manange database creation/upgrading

.DESCRIPTION
    This script allows to manange database creation/upgrading

.EXAMPLE
    PS> .\dbv.ps1
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
        Write-Host ('dbv - start at {0}' -f $start_at)
        Write-Host ('*' * 60)

        DB-Initialize
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
        Write-Host ('dbv - end at {0}' -f $end_at)
        Write-Host ('*' * 60)
        Write-Host ("dbv - duration: {0}`n" -f ($end_at - $start_at))
    }
}

<#
.SYNOPSIS
Drop and initialize a new database
#>
function DB-Initialize
{
    Write-Host "dbv - init"

    #Read config.json
    read_config_json

    # Database apps
    Write-Host ("  script performed with mysql apps user (octopus) '{0}'" -f $config.db_octopus.mysql_apps.user)
    build_database_connections_apps
    delete_database $dba_apps_conn_string $config.db_apps.name
    db_create_apps

    # Database reports
    Write-Host ("  script performed with mysql reports user (octopus) '{0}'" -f $config.db_octopus.mysql_rep.user)
    build_database_connections_reports
    delete_database $dba_rep_conn_string $config.db_reports.name
    db_create_reports
}

Main
