Param (
	[string]$mysql_path = "$env:ProgramFiles\MySQL\MySQL Server 5.6\bin\mysql.exe",
	[string]$dbuser = "root",
	[string]$dbpass = "QTkq81vE",
	[Parameter(Mandatory=$True)]
	[string]$dbname = "Shakira_db_does_not_exist",
	[string]$dbhost = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
[void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

$thisScript = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. ($thisScript + '.\dbv_common.ps1')

$mysql_args = "-u$dbuser -h $dbhost -p$dbpass --default-character-set=utf8 --connect_timeout=300 -C $dbname "
$ConnectionString = "server=" + $dbhost + ";port=3306;uid=" + $dbuser + ";pwd=" + $dbpass + ";CharSet=utf8;Connection Timeout=300;default command timeout=300;"

$dropQuery = "DROP DATABASE IF EXISTS ``$dbname``;"
$createQuery = "CREATE DATABASE ``$dbname``;"

$repository = (Get-ScriptDirectory).parent.FullName

$DBVersion = RunQuery -Query $dropQuery -isScalar $False
$DBVersion = RunQuery -Query $createQuery -isScalar $False

RunFileSafe -scriptfile "$repository\data\revisions\initialize\initialize_v_3_9_30.sql"

& "$repository\compiled\extract_versions_bamboo.ps1" -mysql_path $mysql_path -dbuser $dbuser -dbpass $dbpass -dbname $dbname -dbhost $dbhost -data $True -storedProcedures $True -views $True -schema $True -reports $True -multilingual $True