$thisScript = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. ($thisScript + '.\dbv_common.ps1')

#Abort on any error
$ErrorActionPreference = "Stop"

$execution_path = (Get-ScriptDirectory).parent.FullName
$repository_path = "$execution_path\views"
$last_revision_number_file = "$execution_path\compiled\last_revised_number.txt"

#Check if any files have been committed in the repository since the views commit, introducing unexpected changes
$svnStatus = (svn status --show-updates "$execution_path\data" "$execution_path\views" "$last_revision_number_file") -NotMatch "^Status"
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error checking svn status. Please confirm you are connected to the network."
	Exit 1
}

if ($svnStatus.Length -gt 0 -And $svnStatus -ne $False) { 
	ShowMessage -message "Please update your local repository, confirm that there are no pending changes, and then execute this script again."
	Exit 2
}

#get the last revision number from a file
$last_rev = Get-Content $last_revision_number_file

#get the latest revision number
$current_rev = (svn info -r HEAD $repository_path | Select-String -Pattern "Last Changed Rev:[\s]*([0-9]+)").Matches.Groups[1].Value
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error checking latest SVN revision. Please speak to your Team Lead."
	Exit 3
}

#get the list of changed files and split via new line
$revision_range_text = $last_rev + ":" + $current_rev

#match only added and modified (Start with 'A' or 'M' in diff output, and match files which end in .sql
$list_text = @(svn diff $repository_path -r $revision_range_text --summarize) -match "^[AM][^\r\n]+\.sql"
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error checking list of changed files. Please speak to your Team Lead."
	Exit 4
}

#if there are no changes to views, then exit
if ($list_text.Length -eq 0) { Exit 0 }

#delete the file if it exists
$temp_views_file = [System.IO.Path]::GetTempFileName()
If (Test-Path $temp_views_file) { Remove-Item $temp_views_file }

#fetch the list of all files and append to the same file
$list_text | foreach {
		$_ = $_.Substring(2).trim(" ")
		$next_data = Get-Content $_
		
		$f = Split-Path $_ -Leaf
		Add-Content $temp_views_file "-- -------------------------------------"
		Add-Content $temp_views_file "-- $f"
		Add-Content $temp_views_file "-- -------------------------------------"
		Add-Content $temp_views_file $next_data
}

Set-Content $last_revision_number_file $current_rev

$FullFolder = CreateNextRevisionDir -repositoryRoot $execution_path

$VIEWS =  Join-Path $FullFolder "views.sql"
Move-Item $temp_views_file $VIEWS

$Folder = Split-Path -leaf $FullFolder
$message =  "$Folder automatic update"

svn add --parents $VIEWS
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error adding files to SVN. Please speak to your Team Lead."
	Exit 5
}

svn commit -m $message "$FullFolder" "$VIEWS" "$last_revision_number_file"
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error committing changed files. Please speak to your Team Lead."
	Exit 6
}