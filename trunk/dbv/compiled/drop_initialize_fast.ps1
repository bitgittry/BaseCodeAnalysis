Param (
	[string]$mysql_path = "$env:ProgramFiles\MySQL\MySQL Server 5.6\bin\mysql.exe",
	[string]$dbuser = "root",
	[string]$dbpass = "QTkq81vE",
	[Parameter(Mandatory=$True)]
	[string]$dbname = "Shakira_db_does_not_exist",
	[string]$dbhost = "127.0.0.1",
	[string]$dbport = "3306",
	[bool]$useOnlyPort = $False,
	[bool]$silentMode = $False
 )

$ErrorActionPreference = "Stop"

#$currentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$currentPath = $PSScriptRoot

. "$currentPath\dbv_common.ps1"

Load-MySqlDataLib

If ($useOnlyPort) {
	$dbnameForCheck = ""
}
else {
	$dbnameForCheck = $dbname
}

$mysql_args = Get-MySQLArgs -dbhost $dbhost -dbuser $dbuser -dbpass $dbpass -dbname $dbname -dbnameForCheck $dbnameForCheck -dbport $dbport
$ConnectionString = Get-ConnectionString -dbhost $dbhost -dbuser  $dbuser  -dbpass $dbpass -dbnameForCheck $dbnameForCheck -dbport $dbport

$dropQuery = "DROP DATABASE IF EXISTS ``$dbname``;"
$createQuery = "CREATE DATABASE ``$dbname``;"

If (!$silentMode)
{
  Write-Progress -Id 2 -Activity "Drop database $dbname"
}

$ret = RunQuery -Query $dropQuery -isScalar $False 
$ret = RunQuery -Query $createQuery -isScalar $False

If (!$silentMode)
{
  Write-Progress -Id 2 -Activity "Initialize database $dbname"
}

RunFileSafe -scriptfile "$dbvDataRevPath\initialize\initialize_v_3_9_30.sql"

If (!$silentMode)
{
  Write-Progress -Id 2 -Activity "Generating upgrade database $dbname..."
}
$extraDBVFile = "$currentPath\extra_dbv.sql"
& "$currentPath\extract_versions.ps1" -rev 0300903000011 -outputFile $extraDBVFile -reports $True -data $True -storedProcedure $True -views $True -schema $True -multilingual $True -systemcomponents $True -parentProgressId 2 -silentMode $silentMode -dbPort

If (!$silentMode)
{
  Write-Progress -Id 2 -Activity "Upgrading database $dbname"
}
RunFileSafe -scriptfile $extraDBVFile

If (!$silentMode)
{
  Write-Progress -Id 2 -Activity "End initialization database $dbname" -Completed
}
