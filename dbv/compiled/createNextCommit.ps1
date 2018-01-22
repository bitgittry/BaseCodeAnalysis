$thisScript = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. ($thisScript + '.\dbv_common.ps1')

$repositoryRoot = (Get-ScriptDirectory).parent.FullName

#Check if there are pending changes which have not been committed in the repository, introducing unexpected changes
$svnStatus = (svn status --show-updates "$repositoryRoot\data") -NotMatch "^Status"
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error checking svn status. Please confirm you are connected to the network."
	Exit 1
}

if ($svnStatus.Length -gt 0 -And $svnStatus -ne $False) { 
	ShowMessage -message "Please update your local repository, confirm that there are no pending changes, and then execute this script again."
	Exit 2
}

$FullFolder = CreateNextRevisionDir -repositoryRoot $repositoryRoot

$Data = Join-Path $FullFolder "data.sql"
$Schema = Join-Path $FullFolder "schema.sql"
$Reports = Join-Path $FullFolder "reports.sql"

New-Item $Data -type file
New-Item $Schema  -type file
New-Item $Reports  -type file