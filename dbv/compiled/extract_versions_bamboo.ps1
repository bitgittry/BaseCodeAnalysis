Param (
  [string]$mysql_path = "$env:ProgramFiles\MySQL\MySQL Server 5.6\bin\mysql.exe",
  [string]$dbuser = "root",
  [string]$dbpass = "QTkq81vE",
  [Parameter(Mandatory=$True)]
  [string]$dbname = "Shakira_db_does_not_exist",
  [string]$dbhost = "127.0.0.1",
  [string]$dbport = "3306",
  [bool]$schema = $True,
  [bool]$storedProcedures = $True,
  [bool]$views = $True,
  [bool]$data = $True,
  [bool]$reports = $True,
  [bool]$multilingual = $True,
  [bool]$systemcomponents = $True,
  [bool]$silentMode = $False
)

$ErrorActionPreference = "Stop"

#$currentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$currentPath = $PSScriptRoot

. "$currentPath\dbv_common.ps1"

Load-MySqlDataLib

$mysql_args = Get-MySQLArgs -dbhost $dbhost -dbuser $dbuser -dbpass $dbpass -dbname $dbname -dbport $dbport
$ConnectionString = Get-ConnectionString $dbhost $dbuser $dbpass $dbname $dbport $dbport
$DBVVerQuery = "SELECT dbv_version FROM gaming_system_versions WHERE system_version_id = 1;"

$rev = RunQuery -Query $DBVVerQuery -isScalar $True

if ($rev -eq [DBNull]::Value) {
	$rev = 0
}

$count = Count-AvailableRevisions $rev

if ($count -gt 0)
{
  If (!$silentMode)
  {
    Write-Progress -Id 2 -Activity "Upgrading database $dbname"
  }
  $extraDBVFile = "$currentPath\extra_dbv_bamboo.sql"
  & "$currentPath\extract_versions.ps1" -rev $rev -outputFile $extraDBVFile -schema $schema -storedProcedures $storedProcedures -views $views -data $data -reports $reports -multilingual $multilingual -systemcomponents $systemcomponents -progressParentId 2 -silentMode $silentMode
  RunFileSafe -scriptfile $extraDBVFile
  
  If (!$silentMode)
  {
    Write-Progress -Id 2 -Activity "Extracted revisions" -Completed
  }
}
else 
{
  Write-Output "No changes since revision: $rev"
}
