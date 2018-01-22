<#
.SYNOPSIS
    This script provides functions/helpers to manage database creation/upgrading

.DESCRIPTION
    This script provides functions/helpers to manage database creation/upgrading

.NOTES
    The script not follow the PowerShell convention. Then consider that should be replaced with Python
#>

$__dbvmap__ = @{}
$config = $null
$dba_apps_conn_string = $null
$dba_rep_conn_string = $null
$apps_conn_string = $null
$rep_conn_string = $null

<#
.SYNOPSIS
Build database connections for dba, applications
#>
function build_database_connections_apps
{
    $mysql_apps_config = $config.db_octopus.mysql_apps

    # dba connection apps
    $script:dba_apps_conn_string = ("server={0};port={1};uid={2};pwd={3};CharSet=utf8;Pooling=false;Connection Timeout={4};default command timeout={4};" -f `
            $mysql_apps_config.host, $mysql_apps_config.port, $mysql_apps_config.user, $mysql_apps_config.password, $mysql_apps_config.connection_timeout)
    # connection apps
    $script:apps_conn_string = ("server={0};port={1};uid={2};pwd={3};CharSet=utf8;Pooling=false;Connection Timeout={4};default command timeout={4};database={5}" -f `
            $mysql_apps_config.host, $mysql_apps_config.port, $mysql_apps_config.user, $mysql_apps_config.password, $mysql_apps_config.connection_timeout, $config.db_apps.name)
}

<#
.SYNOPSIS
Build database connections for dba, reports
#>
function build_database_connections_reports
{
    $mysql_rep_config = $config.db_octopus.mysql_rep

    # dba connection reports
    $script:dba_rep_conn_string = ("server={0};port={1};uid={2};pwd={3};CharSet=utf8;Pooling=false;Connection Timeout={4};default command timeout={4};" -f `
            $mysql_rep_config.host, $mysql_rep_config.port, $mysql_rep_config.user, $mysql_rep_config.password, $mysql_rep_config.connection_timeout)
    # connection reports
    $script:rep_conn_string = ("server={0};port={1};uid={2};pwd={3};CharSet=utf8;Pooling=false;Connection Timeout={4};default command timeout={4};database={5}" -f `
            $mysql_rep_config.host, $mysql_rep_config.port, $mysql_rep_config.user, $mysql_rep_config.password, $mysql_rep_config.connection_timeout, $config.db_reports.name)
}

<#
.SYNOPSIS
Build MySQL database apps and related users (included privileges)
#>
function build_db_apps
{
    Write-Host "dbv - build database apps"

    create_user_apps_service
    db_create_or_upgrade_apps
    create_user_and_privileges $dba_apps_conn_string $config.db_apps
}

<#
.SYNOPSIS
Create or upgrade database apps
#>
function db_create_or_upgrade_apps
{
    Write-Host "dbv - create or upgrade database apps"
    if (!(mysql_test_database_exists $dba_apps_conn_string $config.db_apps.name)) {
        db_create_apps
    }
    else {
        db_upgrade_apps
    }
}

function ConvertTo-Hashtable
{
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$InputObject,
        [parameter(Mandatory=$false)]
        [int]$Depth=2        
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $hash = $InputObject.PSObject.Properties | % { $ht = @{} } { $ht[$_.Name] = $_.Value } { $ht }
    return $hash
}

<#
.SYNOPSIS
Create a new database apps
#>
function db_create_apps
{
    Write-Host "dbv - create database apps"
    _init_dbvmap

    [System.Console]::Write("  creation database '{0}' ... ", $config.db_apps.name)
    mysql_new_database $dba_apps_conn_string $config.db_apps.name
    Write-Host "done"

    $mysql_apps_config = $config.db_octopus.mysql_apps

    # get mysql command and arguments
    $basedir = (mysql_get_basedir $dba_apps_conn_string)
    $mysql_cmd = (mysql_get_mysql_cmd $basedir)
    $config_options = $config.options | ConvertTo-Hashtable
    $config_options['my_option_file'] = (create_my_option_file $mysql_apps_config $config_options 'apps')
    $config_options['db_name'] = $config.db_apps.name
    $mysql_args = mysql_get_mysql_cmd_args $mysql_apps_config ($config_options | ConvertTo-Json | ConvertFrom-Json)

    # run initialize sql file
    $init_sql = (Join-Path $__dbvmap__['data.revisions.initialize'] $config.dbv.init_sql)
    [System.Console]::Write("  initialize database '{0}' ... ", $init_sql)
    mysql_run_batch_sql $mysql_cmd $mysql_args $init_sql
    Write-Host "done"

    _apply_revisions_and_routines $mysql_cmd $mysql_args $config.dbv.init_rev $config.dbv.last_rev
}

<#
.SYNOPSIS
Upgrade database apps
#>
function db_upgrade_apps
{
    Write-Host "dbv - upgrade database apps"
    _init_dbvmap

    [System.Console]::Write("  upgrading database '{0}' ... ", $config.db_apps.name)

    $mysql_apps_config = $config.db_octopus.mysql_apps

    # get mysql command and arguments
    $basedir = (mysql_get_basedir $dba_apps_conn_string)
    $mysql_cmd = (mysql_get_mysql_cmd $basedir)
    $config_options = $config.options | ConvertTo-Hashtable
    $config_options['my_option_file'] = (create_my_option_file $mysql_apps_config $config_options 'apps')
    $config_options['db_name'] = $config.db_apps.name
    $mysql_args = mysql_get_mysql_cmd_args $mysql_apps_config ($config_options | ConvertTo-Json | ConvertFrom-Json)

    # get current revision number
    $init_rev = (_get_current_dbv_version $apps_conn_string)
    Write-Host ("current version '{0}'" -f $init_rev)

    _apply_revisions_and_routines $mysql_cmd $mysql_args $init_rev $config.dbv.last_rev
}

<#
.SYNOPSIS
Apply revisions and routines
#>
function _apply_revisions_and_routines
{
    param
    (
        [string]$mysql_cmd,
        [string]$mysql_args,
        [string]$init_rev,
        [string]$last_rev
    )

    $count = _count_revisions_available $init_rev $last_rev
    if ($count -gt 0) {
        $proc_sql = (Join-Path $__dbvmap__['dbv_base'] 'proc.sql')
        $script:config.dbv.rev_stored_routines = !(Test-Path $proc_sql)

        if ($config.options.disable_rev_stored_routines_when_proc) {
            $proc_sql = (Join-Path $__dbvmap__['dbv_base'] 'proc.sql')
            $script:config.dbv.rev_stored_routines = !(Test-Path $proc_sql)
        }

        $revs_file = (extract_revisions $init_rev $last_rev)
        [System.Console]::Write("  run batch '{0}' ... " -f $revs_file)
        mysql_run_batch_sql $mysql_cmd $mysql_args $revs_file
        Write-Host "done"
        _create_or_upgrade_routines $mysql_cmd $mysql_args
    }
    else {
        Write-Host "  no new revisions available"
    }
}

<#
.SYNOPSIS
Clean up MySQL database apps and related users (included privileges)
#>
function cleanup_db_apps
{
    Write-Host "dbv - cleanup database apps"

    # Delete user apps and revoke privileges
    $hostnames = $config.db_apps.host.Split(',')
    foreach($hostname in $hostnames) {
        _delete_user $dba_apps_conn_string $config.db_apps.user $hostname
    }

    # Delete user application service and revoke privileges
    _delete_user $dba_apps_conn_string $config.db_apps_service.user $config.db_apps_service.host

    # Flush privileges (clean cache)
    mysql_flush_privileges $dba_apps_conn_string

    # Delete database apps
    delete_database $dba_apps_conn_string $config.db_apps.name
}

<#
.SYNOPSIS
Build MySQL database reports and related users (included privileges)
#>
function build_db_reports
{
    Write-Host "dbv - build database reports"

    db_create_or_upgrade_reports
    create_user_and_privileges $dba_rep_conn_string $config.db_reports
}

<#
.SYNOPSIS
Create or upgrade database reports
#>
function db_create_or_upgrade_reports
{
    Write-Host "dbv - create or upgrade database reports"

    if (!(mysql_test_database_exists $dba_rep_conn_string $config.db_reports.name)) {
        db_create_reports
    }
#    else {
#        db_upgrade_reports
#    }
}

<#
.SYNOPSIS
Create database reports
#>
function db_create_reports
{
    Write-Host "dbv - create database reports"
    Write-Host ("  creation database reports '{0}' ... " -f $config.db_reports.name)
    if (!(mysql_test_database_exists $dba_rep_conn_string $config.db_reports.name)) {
        mysql_new_database $dba_rep_conn_string $config.db_reports.name
        Write-Host "done"
    }
    else {
        Write-Host "already exists"
    }
}

<#
.SYNOPSIS
Clean up MySQL database reports and related users (included privileges)
#>
function cleanup_db_reports
{
    Write-Host "dbv - cleanup database reports"

    # Delete user reports and revoke privileges
    $hostnames = $config.db_reports.host.Split(',')
    foreach($hostname in $hostnames) {
        _delete_user $dba_rep_conn_string $config.db_reports.user $hostname
    }

    # Flush privileges (clean cache)
    mysql_flush_privileges $dba_rep_conn_string

    # Delete database reports
    delete_database $dba_rep_conn_string $config.db_reports.name
}

<#
.SYNOPSIS
Create user application service if not exists
#>
function create_user_apps_service
{
    Write-Host "dbv - create user applications service"
    [System.Console]::Write("  creation user '{0}@{1}' ... ", $config.db_apps_service.user, $config.db_apps_service.host)
    if (!(mysql_test_user_exists $dba_apps_conn_string $config.db_apps_service.user $config.db_apps_service.host)) {
        mysql_new_user $dba_apps_conn_string $config.db_apps_service.user $config.db_apps_service.host $config.db_apps_service.password
        Write-Host "done"
        # it's not possible testing global privileges as per database'
        [System.Console]::Write("  grant user '{0}@{1}' to '*.*' ... ", $config.db_apps_service.user, $config.db_apps_service.host)
        mysql_grant_privileges $dba_apps_conn_string $config.db_apps_service.user $config.db_apps_service.host $config.db_apps_service.priv_type
        Write-Host "done"
        Write-Host ("    priv_type: '{0}'" -f $config.db_apps_service.priv_type)
    }
    else {
        Write-Host "already exists"
    }
}

<#
.SYNOPSIS
Create user if not exists and grants privilges

.PARAMETER $connection

.PARAMETER $db_user
#>
function create_user_and_privileges
{
    param
    (
        [string]$connection,
        $db_user
    )

    Write-Host "dbv - create user and privileges"
    $hostnames = $db_user.host.Split(',')
    foreach ($hostname in $hostnames) {
        _create_user $connection $db_user $hostname
        _grant_user_privileges $connection $db_user $hostname
    }
}

<#
.SYNOPSIS
Extract revisions sql file based on given inputs

.PARAMETER $init_rev

.PARAMETER $last_rev
#>
function extract_revisions
{
    param
    (
        [string]$init_rev,
        [string]$last_rev=$null
    )

    Write-Host "dbv - extract revisions"
    _init_dbvmap
    _guard_revisions $init_rev $last_rev
    $revs_file = (Join-Path $__dbvmap__['deploy'] ('revs_{0}_{1}.sql' -f $init_rev, $last_rev))
    _build_revisions_file $init_rev $last_rev $revs_file
    return $revs_file
}

<#
.SYNOPSIS
Create user application service if not exists
#>
function _init_dbvmap
{
    $dbv_base = _get_dbv_base_folder
    $__dbvmap__ = @{
        'dbv_base' = $dbv_base;
        'compiled' = (Join-Path $dbv_base 'compiled');
        'data' = (Join-Path $dbv_base 'data');
        'data.revisions' = 'revisions';
        'data.revisions.initialize' = 'initialize';
        'deploy' = (Join-Path $dbv_base 'deploy');
        'stored_routines' = (Join-Path $dbv_base 'stored_routines')
    }

    $__dbvmap__['data.revisions'] = (Join-Path $__dbvmap__['data'] $__dbvmap__['data.revisions'])
    $__dbvmap__['data.revisions.initialize'] = (Join-Path $__dbvmap__['data.revisions'] $__dbvmap__['data.revisions.initialize'])
    $script:__dbvmap__ = $__dbvmap__
}

<#
.SYNOPSIS
Return base dbv folder
#>
function _get_dbv_base_folder
{
    $dbv_base = (Join-Path $config.extract_path 'dbv')
    return $dbv_base
}

<#
.SYNOPSIS
Delete database

.PARAMETER $connection

.PARAMETER $schema
#>
function delete_database
{
    param
    (
        [string]$connection,
        [string]$schema
    )

    [System.Console]::Write("  deleting database '{0}' ... ", $schema)
    if (mysql_test_database_exists $connection $schema) {
        mysql_delete_database $connection $schema
        Write-Host "done"
    }
    else {
        Write-Host "not exists"
    }
}

<# .SYNOPSIS
Create user if not exists

.PARAMETER $connection

.PARAMETER $db_user

.PARAMETER $hostname
#>
function _create_user
{
    param
    (
        [string]$connection,
        $db_user,
        [string]$hostname
    )

    [System.Console]::Write("  creation user '{0}@{1}' ... ", $db_user.user, $hostname)
    if (!(mysql_test_user_exists $connection $db_user.user $hostname)) {
        mysql_new_user $connection $db_user.user $hostname $db_user.password
        Write-Host "done"
    }
    else {
        Write-Host "already exists"
    }
}

<#
.SYNOPSIS
Delete user

.PARAMETER $connection

.PARAMETER $username

.PARAMETER $hostname
#>
function _delete_user
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname
    )

    [System.Console]::Write("  deleting user '{0}@{1}' ... ", $username, $hostname)
    if (mysql_test_user_exists $connection $username $hostname) {
        mysql_delete_user $connection $username $hostname
        Write-Host "done"
    }
    else {
        Write-Host "not exists"
    }
}

<#
.SYNOPSIS
Grant user privileges

.PARAMETER $connection

.PARAMETER $db_user

.PARAMETER $hostname
#>
function _grant_user_privileges
{
    param
    (
        [string]$connection,
        $db_user,
        [string]$hostname
    )

    [System.Console]::Write("  grant user '{0}@{1}' to '{2}' ... ", $db_user.user, $hostname, $db_user.name)
    if (!(mysql_test_user_grants $connection $db_user.user $db_user.name $hostname)) {
        mysql_grant_privileges $connection $db_user.user $hostname $db_user.priv_type $db_user.priv_level
        Write-Host "done"
        Write-Host ("    priv_type: '{0}'" -f $db_user.priv_type)
        Write-Host ("    priv_level: '{0}'" -f $db_user.priv_level)
    }
    else {
        Write-Host "already granted"
    }
}

<#
.SYNOPSIS
Revoke user privileges

.PARAMETER $connection

.PARAMETER $db_user

.PARAMETER $hostname
#>
function _revoke_user_privileges
{
    param
    (
        [string]$connection,
        $db_user,
        [string]$hostname
    )

    [System.Console]::Write("  revoke on '{0}' from '{1}@{2}' ... ", $db_user.priv_level, $db_user.user, $hostname)
    if (mysql_test_user_grants $connection $db_user.user $db_user.name $hostname) {
        mysql_revoke_privileges $connection $db_user.user $hostname -priv_level db_user.priv_level
        Write-Host "done"
    }
    else {
        Write-Host "no privileges"
    }
}

<#
.SYNOPSIS
Count available revisions based on given inputs
#>
function _count_revisions_available
{
    param
    (
        [string]$init_rev,
        [string]$last_rev
    )

    _guard_revisions $init_rev $last_rev
    $revs_dirs = $__dbvmap__['data.revisions']
    $count = (Get-ChildItem -Directory $revs_dirs | ? {
                $_.Name -match "^\d+$" -and [decimal]$_.Name -gt $init_rev -and `
                (!$last_rev -or ($_.Name -match "^\d+$" -and [decimal]$_.Name -le $last_rev))
             }).Count

    return $count
}

function _guard_revisions
{
    param
    (
        [string]$init_rev,
        [string]$last_rev
    )

    if ($init_rev -notmatch "^\d+$")
    {
        throw "Revision init_rev is required as an integer"
    }

    if (!(IsNull $last_rev)) {
        if ($last_rev -notmatch "^\d+$") {
            throw "Revision last_rev is required as an integer"
        }
    }
}

<#
.SYNOPSIS
Build revisions file based on given inputs (init_rev < rev <= last_rev)
#>
function _build_revisions_file
{
    param
    (
        [string]$init_rev,
        [string]$last_rev,
        [string]$revs_file
    )

    [System.Console]::Write("  generate revisions file from '{0}' to '{1}' ... ", $init_rev, $last_rev)
    $revs_txt = (Join-Path $__dbvmap__['deploy'] ('revs_{0}_{1}.txt' -f $init_rev, $last_rev))
    _build_revisions_file_available $init_rev $last_rev $revs_txt

    $workFile = (Join-Path $__dbvmap__['deploy'] ([System.Guid]::NewGuid().toString() + ".tmp"))
    Add-Content $workFile ("--  generate revisions file from '{0}' to '{1}'" -f $init_rev, $last_rev) -Encoding UTF8

    _dbv_revisions_header $workFile
    _dbv_revisions_content $workFile $revs_txt

    Write-Host "done"

    Remove-FileSafe $revs_file
    Move-Item $workFile -Destination $revs_file -Force
    Remove-FileSafe $revs_txt
}

<# .SYNOPSIS
Build file of available revisions based on given inputs
#>
function _build_revisions_file_available
{
    param
    (
        [string]$init_rev,
        [string]$last_rev,
        [string]$revs_txt
    )

    Remove-FileSafe $revs_txt
    $revs_dirs = $__dbvmap__['data.revisions']
    (Get-ChildItem -Directory $revs_dirs | ? {
        $_.Name -match "^\d+$" -and [decimal]$_.Name -gt $init_rev -and `
        (!$last_rev -or ($_.Name -match "^\d+$" -and [decimal]$_.Name -le $last_rev))
    }) | % { Add-Content $revs_txt $_.Name -Encoding UTF8 }
}

<#
.SYNOPSIS
Write revisions header
#>
function _dbv_revisions_header
{
    param
    (
        [string]$f
    )

    Add-Content $f 'SET character_set_client  = utf8;' -Encoding UTF8
    Add-Content $f 'SET character_set_results = utf8;' -Encoding UTF8
    Add-Content $f "SET collation_connection  = utf8_general_ci;`n" -Encoding UTF8
}

<#
.SYNOPSIS
Write revisions content given revisions file
#>
function _dbv_revisions_content
{
    param
    (
        [string]$fout,
        [string]$frev
    )

    foreach($rev in Get-Content $frev) {
        $base_path = (Join-Path $__dbvmap__['data.revisions'] $rev)

        Add-Content $fout ("-- {{START}}: {0}`n" -f $rev) -Encoding UTF8

        if ($config.dbv.rev_schema) {
            _append_content_to_file (Join-Path $base_path 'schema.sql') $fout
        }

        if ($config.dbv.rev_stored_routines) {
            _append_content_to_file (Join-Path $base_path 'storedProcedures.sql') $fout
        }

        if ($config.dbv.rev_data) {
            _append_content_to_file (Join-Path $base_path 'data.sql') $fout
        }

        if ($config.dbv.rev_reports) {
            _append_content_to_file (Join-Path $base_path 'reports.sql') $fout
        }

        if ($config.dbv.rev_multilingual) {
            _append_content_to_file (Join-Path $base_path 'multilingual_references.sql') $fout
        }

        if ($config.dbv.rev_system_components) {
            _append_content_to_file (Join-Path $base_path 'systemcomponents.sql') $fout
            _append_content_to_file (Join-Path $base_path 'controller_changes.sql') $fout
            _append_content_to_file (Join-Path $base_path 'method_changes.sql') $fout
            _append_content_to_file (Join-Path $base_path 'ribbon_changes.sql') $fout
            _append_content_to_file (Join-Path $base_path 'internal_page_changes.sql') $fout
            _append_content_to_file (Join-Path $base_path 'page_method_linking_changes.sql') $fout
        }

        Add-Content $fout ("UPDATE gaming_system_versions SET dbv_version = '{0}' WHERE system_version_id = 1;" -f $rev) -Encoding UTF8
        Add-Content $fout ("`n-- {{END}}: {0}`n" -f $rev) -Encoding UTF8
    }
}

<#
.SYNOPSIS
Append content safely from input (fin) file to output (fout) file
#>
function _append_content_to_file
{
    param
    (
        $fin,
        $fout
    )

    if ((Test-Path $fin) -and (Get-Item $fin).Length -gt 0) {
        $content = Get-Content $fin -Encoding UTF8 | Out-String

        # Replace all references to DEFINER with DEFINER=`bit8_admin`@`127.0.0.1`
        if ($content -like '*DEFINER*') {
            $content = $content -replace 'DEFINER[\s]*=[\s]*`[^`]+`@[\s]*`[^`]+`', 'DEFINER=`bit8_admin`@`127.0.0.1` '
        }

        # Replace all references of UpdateExistingReport to avoid issue during MySQL execution
        if ($content -like '*UpdateExistingReport*') {
            $content = ($content -replace '(?s)((SELECT UpdateExistingReport).+?,\s1\));', '$1 INTO @updateExistingReport;')
        }

        ## ComponentsController
        if ($content -like '*ComponentsControllerCreate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsControllerCreate).+?''\));', '$1 INTO @ComponentsController;')
        }
        if ($content -like '*ComponentsControllerDelete*') {
            $content = ($content -replace '(?s)((SELECT ComponentsControllerDelete).+?''\));', '$1 INTO @ComponentsController;')
        }
        if ($content -like '*ComponentsControllerUpdate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsControllerUpdate).+?''\));', '$1 INTO @ComponentsController;')
        }
        ## End-ComponentsController

        ## ComponentsFunction
        if ($content -like '*ComponentsFunctionCreate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsFunctionCreate).+?,\s(0|1)\));', '$1 INTO @ComponentsFunction;')
        }
        if ($content -like '*ComponentsFunctionDelete*') {
            $content = ($content -replace '(?s)((SELECT ComponentsFunctionDelete).+?''\));', '$1 INTO @ComponentsFunction;')
        }
        if ($content -like '*ComponentsFunctionUpdate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsFunctionUpdate).+?''\));', '$1 INTO @ComponentsFunction;')
        }
        ## End-ComponentsFunction

        ## ComponetsInternal
        if ($content -like '*ComponentsInternalPageCreate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsInternalPageCreate).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        if ($content -like '*ComponentsInternalPageDelete*') {
            $content = ($content -replace '(?s)((SELECT ComponentsInternalPageDelete).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        if ($content -like '*ComponentsInternalPageUpdate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsInternalPageUpdate).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        ## End-ComponetsInternal

        ## ComponentsPageMethodLinking
        if ($content -like '*ComponentsPageMethodLinkingCreate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsPageMethodLinkingCreate).+?''\));', '$1 INTO @ComponentsPageMethodLinking;')
        }
        if ($content -like '*ComponentsPageMethodLinkingDelete*') {
            $content = ($content -replace '(?s)((SELECT ComponentsPageMethodLinkingDelete).+?''\));', '$1 INTO @ComponentsPageMethodLinking;')
        }
        ## End-ComponentsPageMethodLinking

        ## ComponentsRibbon
        if ($content -like '*ComponentsRibbonCreate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsRibbonCreate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($content -like '*ComponentsRibbonDelete*') {
            $content = ($content -replace '(?s)((SELECT ComponentsRibbonDelete).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($content -like '*ComponentsRibbonSaveOrderUpdate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsRibbonSaveOrderUpdate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($content -like '*ComponentsRibbonUpdate*') {
            $content = ($content -replace '(?s)((SELECT ComponentsRibbonUpdate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        ## End-ComponentsRibbon

        Add-Content $fout $content -Encoding UTF8
    }
}

<#
.SYNOPSIS
Create or upgrade routines
#>
function _create_or_upgrade_routines
{
    param
    (
        $mysql_cmd,
        $mysql_args
    )

    $proc_sql = (Join-Path $__dbvmap__['dbv_base'] 'proc.sql')
    if (Test-Path $proc_sql) {
        [System.Console]::Write("  deleting procedures ... ")
        mysql_delete_procedures $dba_apps_conn_string $config.db_apps.name

        Write-Host "done"
        [System.Console]::Write("  run batch '{0}' ... ", $proc_sql)
        mysql_run_batch_sql $mysql_cmd $mysql_args $proc_sql
        Write-Host "done"
    }
}

<#
.SYNOPSIS
Return current dbv version
#>
function _get_current_dbv_version
{
    param
    (
        [string]$connection
    )

    $sqlText = "SELECT dbv_version FROM gaming_system_versions WHERE system_version_id = 1;"
    $result = mysql_run_db_command_scalar $connection $sqlText
    if ($result -eq [System.DBNull]::Value) {
        result = 0
    }

    return $result
}

<#
.SYNOPSIS
Read config file in json format
#>
function read_config_json
{
    param
    (
        [string]$configName="config.json"
    )

    Write-Host ("  read config.json '{0}" -f $configName)

    $script:config = Get-Content -Raw (Join-Path $currentPath $configName) | ConvertFrom-Json
}

<#
.SYNOPSIS
See https://www.codykonior.com/2013/10/17/checking-for-null-in-powershell/ for more explanation
#>
function IsNull($objectToCheck) {
    if (!$objectToCheck) {
        return $true
    }

    if ($objectToCheck -is [String] -and $objectToCheck -eq [String]::Empty) {
        return $true
    }

    if ($objectToCheck -is [DBNull] -or $objectToCheck -is [System.Management.Automation.Language.NullString]) {
        return $true
    }

    return $false
}

<#
.SYNOPSIS
Remove file safely
#>
function Remove-FileSafe
{
    param
    (
        [Parameter(Mandatory = $true)]
        [String]$FilePath
    )

    if (Test-Path $FilePath) {
        Remove-Item $FilePath
    }
}

<#
#===========================================================================
# MySQL utilities
#===========================================================================
#>

#=============================================================================
# Run database commands
#=============================================================================

<#
.SYNOPSIS
Load MySQL.Data.dll
#>
$is_mysql_data_loaded = $false
function Load-MySQLData
{
    if (!$is_mysql_data_loaded) {
        $assemblyName = (Join-Path $currentPath "libs" | Join-Path -ChildPath "MySql.Data.dll")
        [void][System.Reflection.Assembly]::LoadFrom($assemblyName)
        $is_mysql_data_loaded = $true
    }
}

<#
.SYNOPSIS
Run a sql query that return just one value
#>
function mysql_run_db_command_scalar
{
    param
    (
        [string]$connectionString,
        [string]$sqlText,
        $kwargs=$null
    )

    Load-MySQLData

    $connection = $null
    try {
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = $sqlText

        if ($kwargs) {
            foreach($key in $kwargs.Keys) {
                $command.Parameters.Add("@$key", $kwargs[$key]) > $null
            }
        }

        $scalar = $command.ExecuteScalar()
        return $scalar
    }
    catch {
        Write-Host ''
        Write-Host ("Try to execute sql scalar '{0}'" -f $sqlText)
        throw
    }
    finally {
        if ($connection -ne $null -and $connection.State -eq [System.Data.ConnectionState]::Open) {
            $connection.Close()
        }
    }
}

<#
.SYNOPSIS
Run a sql query don't need to retrieve data
#>
function mysql_run_db_command_no_query
{
    param
    (
        [string]$connectionString,
        [string]$sqlText,
        $kwargs=$null
    )

    Load-MySQLData

    $connection = $null
    try {
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = $sqlText

        if ($kwargs) {
            foreach($key in $kwargs.Keys) {
                $command.Parameters.Add("@$key", $kwargs[$key]) > $null
            }
        }

        $affectedRows = $command.ExecuteNonQuery()
        return $affectedRows
    }
    catch {
        Write-Host ''
        Write-Host ("Try to execute sql no query '{0}'" -f $sqlText)
        throw
    }
    finally {
        if ($connection -ne $null -and $connection.State -eq [System.Data.ConnectionState]::Open) {
            $connection.Close()
        }
    }
}

<#
.SYNOPSIS
Run batch (script) sql using mysql command
#>
function mysql_run_batch_sql
{
    param
    (
        [string]$mysql_cmd,
        [string]$mysql_args,
        [string]$batch_sql
    )

    $stdOutFile = $null
    $stdErrFile = $null

    try {
        $stdOutFile = [System.IO.Path]::GetTempFileName()
        $stdErrFile = [System.IO.Path]::GetTempFileName()

        $p = Start-Process $mysql_cmd -ArgumentList $mysql_args -PassThru -Wait -NoNewWindow `
                -RedirectStandardInput $batch_sql `
                -RedirectStandardOutput $stdOutFile `
                -RedirectStandardError $stdErrFile

        Write-Host (Get-Content $stdOutFile | Out-String)

        if ($p.ExitCode -ne 0) {
            $stdErrContent = (Get-Content $stdErrFile | Out-String)
            $stdErrContent = "`nExit code $($p.ExitCode)`n" + $stdErrContent
            throw $stdErrContent
        }
    }
    catch {
        Write-Host ("`nTry to run batch script '{0}'" -f $batch_sql)
        throw
    }
    finally {
        if ($stdOutFile) { Remove-Item $stdOutFile }
        if ($stdErrFile) { Remove-Item $stdErrFile }
    }
}

#=============================================================================
# MySQL metadata or other info related to
#=============================================================================
<#
.SYNOPSIS
Return basedir's value of MySQL variable
#>
function mysql_get_basedir
{
    param
    (
        [string]$connection
    )

    $sqlText = "SELECT @@basedir"
    $basedir = (mysql_run_db_command_scalar $connection $sqlText)
    return $basedir
}

<#
.SYNOPSIS
Return mysql command
#>
function mysql_get_mysql_cmd
{
    param
    (
        [string]$basedir
    )

    $mysql_cmd = (Join-Path $basedir 'bin' | Join-Path -ChildPath 'mysql.exe')
    return $mysql_cmd
}

<#
.SYNOPSIS
Create mysql option file
#>
function create_my_option_file
{
    param (
        [object]$db_config,
        [object]$options,
        [string]$prefix
    )

    $option_file = $null
    if ($options.use_mysql_option_file) {
        $option_file = Join-Path $__dbvmap__['deploy'] ($prefix + '_my.cnf')        
        '[client]' | Set-Content $option_file
        ('user={0}' -f $db_config.user) | Add-Content $option_file
        ('password={0}' -f $db_config.password) | Add-Content $option_file
        ('host={0}' -f $db_config.host) | Add-Content $option_file
        ('port={0}' -f $db_config.port) | Add-Content $option_file
    }

    return $option_file
}
<#
.SYNOPSIS
Return mysql args to be used on command line
#>
function mysql_get_mysql_cmd_args
{
    param
    (
        [object]$db_config,
        [object]$options
    )

    $my_args = @()

    if ($options.use_mysql_option_file) {
        $my_args += ('--defaults-file={0}' -f $options.my_option_file)
    }
    else {
        $my_args += ('--user={0}' -f $db_config.user)
        $my_args += ('--password={0}' -f $db_config.password)
        $my_args += ('--host={0}' -f $db_config.host)
        $my_args += ('--port={0}' -f $db_config.port)
    }

    $my_args += '--batch'
    $my_args += '--comments'
    $my_args += '--compress'
    $my_args += '--default-character-set=utf8'
    $my_args += '--line-numbers'

    if ($options.db_name) {
        $my_args += ('--database={0}' -f $options.db_name)
    }

    $mysql_args = $my_args -join ' '
    Write-Host "`$mysql_args = $mysql_args" -ForegroundColor DarkYellow
    return $mysql_args
}

#=============================================================================
# Operative functions
#=============================================================================

<#
.SYNOPSIS
Add new MySQL database
#>
function mysql_new_database
{
    param
    (
        [string]$connection,
        [string]$new_schema
    )

    $sqlText = ("CREATE DATABASE ``{0}`` DEFAULT CHARACTER SET 'utf8';" -f $new_schema)
    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Delete MySQL database
#>
function mysql_delete_database
{
    param
    (
        [string]$connection,
        [string]$schema
    )

    $sqlText = ("DROP DATABASE ``{0}``;" -f $schema)
    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Add new MySQL user
#>
function mysql_new_user
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname='%',
        [string]$password=$null
    )

    $is_native_password = (IsNull $password)
    if ($is_native_password) {
        $sqlText = ("CREATE USER '{0}'@'{1}' IDENTIFIED WITH mysql_native_password AS '*ABCDEFGHIJKLMNOPQRSTUVWXYZ';" -f $username, $hostname) # the "AS..." part to bypass validate_password plugin in case no password set
    }
    else {
        $sqlText = ("CREATE USER '{0}'@'{1}' IDENTIFIED BY '{2}';" -f $username, $hostname, $password)
    }

    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Delete a MySQL user and their privileges
#>
function mysql_delete_user
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname='%'
    )

    $sqlText = ("DROP USER '{0}'@'{1}';" -f $username, $hostname)
    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Grant MySQL privileges to specified user
#>
function mysql_grant_privileges
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname='%',
        [string]$priv_type='ALL',
        [string]$priv_level='*.*'
    )

    $sqlText = ("GRANT {0} ON {1} TO '{2}'@'{3}';" -f $priv_type, $priv_level, $username, $hostname)
    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Revoke MySQL privileges to specified user
#>
function mysql_revoke_privileges
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname='%',
        [string]$priv_type='ALL',
        [string]$priv_level='*.*',
        [bool]$auto_flush=$false
    )

    if ('ALL' -eq $priv_type) {
        $sqlText = ("REVOKE ALL, GRANT OPTION FROM '{0}'@'{1}';" -f $username, $hostname)
    }
    else {
        $sqlText = ("REVOKE {0} ON {1} FROM '{2}'@'{3}';" -f $priv_type, $priv_level, $username, $hostname)
    }

    mysql_run_db_command_no_query $connection $sqlText > $null

    if ($auto_flush) { mysql_flush_privileges $connection }
}

<#
.SYNOPSIS
Reloads the privileges from the grant tables in the mysql database
#>
function mysql_flush_privileges
{
    param
    (
        [string]$connection
    )

    $sqlText = "FLUSH PRIVILEGES;"
    mysql_run_db_command_no_query $connection $sqlText > $null
}

<#
.SYNOPSIS
Delete MySQL procedures from specified database
#>
function mysql_delete_procedures
{
    param
    (
        [string]$connection,
        [string]$database
    )

    $sqlText = "DELETE FROM mysql.proc WHERE db = @database;"
    $data = @{
        "database" = $database
    }

    mysql_run_db_command_no_query $connection $sqlText $data > $null
}

#=============================================================================
# Test functions
#=============================================================================

<#
.SYNOPSIS
Test if MySQL database exists
#>
function mysql_test_database_exists
{
    param
    (
        [string]$connection,
        [string]$schema
    )

    $sqlText = "SELECT COUNT(*) AS counter FROM information_schema.SCHEMATA where `schema_name` = @schema;"
    $data = @{
        "schema" = $schema
    }

    $result = (mysql_run_db_command_scalar $connection $sqlText $data)
    return ($result -eq 1)
}

<#
.SYNOPSIS
Test if MySQL user exists
#>
function mysql_test_user_exists
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$hostname
    )

    $sqlText = "SELECT COUNT(*) AS counter FROM mysql.user WHERE `user` = @username and `host` = @hostname;"
    $data = @{
        "username" = $username;
        "hostname" = $hostname
    }

    $result = (mysql_run_db_command_scalar $connection $sqlText $data)
    return ($result -eq 1)
}

<#
.SYNOPSIS
Test if MySQL user grants access to specified database
#>
function mysql_test_user_grants
{
    param
    (
        [string]$connection,
        [string]$username,
        [string]$database,
        [string]$hostname='%'
    )

    $sqlText = "SELECT COUNT(*) AS counter FROM mysql.db WHERE `user` = @username AND `host` = @hostname AND db = @database;"
    $data = @{
        "username" = $username;
        "hostname" = $hostname;
        "database" = $database
    }

    $result = (mysql_run_db_command_scalar $connection $sqlText $data)
    return ($result -eq 1)
}
