param (
	[string]$rev = "",
	[string]$branch = "",
	[bool]$data = $true,
	[bool]$storedProcedures = $true,
	[bool]$schema = $true, 
	[bool]$reports = $true,
	[bool]$multilingual = $true,
	[bool]$systemcomponents = $true
)

$interactive = $FALSE

$thisScript = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
. ($thisScript + '.\dbv_common.ps1')

$currentBranchName = Split-Path (Get-ScriptDirectory).parent.parent.FullName -Leaf
$repository  = (Get-ScriptDirectory).parent.FullName
$last_merged_rev_file = "$repository\compiled\last_merged_versions.txt"
$last_merged_file= ""

$svnStatus = (svn status --show-updates "$repository\data") -NotMatch "^Status"
if ($LastExitCode -gt 0) {
	ShowMessage -message "Error checking svn status. Please confirm you are connected to the network."
	Exit 1
}

if ($svnStatus.Length -gt 0 -And $svnStatus -ne $False) { 
	ShowMessage -message "Please update your local repository, confirm that there are no pending changes, and then execute this script again."
	Exit 2
}

if($branch -eq "") {
	$branch = Read-Host 'For which branch are you merging'
}

 (Get-Content ($last_merged_rev_file)) | Foreach-Object {
	if ($_ -match "$branch.*"){
		$rev = $_.Substring($branch.length + 3)
	}
 } 
 
if($rev -eq "") {
	$rev = Read-Host 'From which revision? (NOT included)'
	$interactive = $TRUE
	Add-Content $last_merged_rev_file "$branch : $rev"
}



if(-Not ($rev -match "^\d+$")) {
	throw "Revision from which to start is required as an integer"
}


$last_rev = $rev
$items = Get-ChildItem -Path "$repository\data\revisions" |  Where-Object {$_.Name -match "^\d+$"} | sort-object -Property {[decimal]$_.Name} | Where-Object {[decimal]$_.Name -gt $rev}

if ($branch -eq 'trunk'){
						
	$mergeLocation = (Get-ScriptDirectory).parent.parent.parent.parent
	$mergeLocation = "$mergeLocation\trunk\dbv\data\revisions"
	$mergeLocation
}
else {
	$mergeLocation = (Get-ScriptDirectory).parent.parent.parent
	$mergeLocation = "$mergeLocation\branches\$branch\dbv\data\revisions"
	$mergeLocation
}

if($items.Length -gt 0) {
	$last_rev = $items[$items.Length-1].Name

	$output_path_schema = "$repository\compiled\schema.sql"
	$output_path_data = "$repository\compiled\data.sql"
	$output_path_reports = "$repository\compiled\reports.sql"
	$output_path_ml = "$repository\compiled\multilingual_references.sql"
	$output_path_sc = "$repository\compiled\systemcomponents.sql"
	$output_path_cc = "$repository\compiled\controller_changes.sql"
	$output_path_mc = "$repository\compiled\method_changes.sql"
	$output_path_rc = "$repository\compiled\ribbon_changes.sql"
	$output_path_ip = "$repository\compiled\internal_page_changes.sql"
	$output_path_lc = "$repository\compiled\page_method_linking_changes.sql"

	If (Test-Path $output_path_schema){Remove-Item $output_path_schema}
	If (Test-Path $output_path_data){Remove-Item $output_path_data}
	If (Test-Path $output_path_reports){Remove-Item $output_path_reports}
	If (Test-Path $output_path_ml){Remove-Item $output_path_ml}
	If (Test-Path $output_path_sc){Remove-Item $output_path_sc}
	If (Test-Path $output_path_cc){Remove-Item $output_path_cc}
	If (Test-Path $output_path_mc){Remove-Item $output_path_mc}
	If (Test-Path $output_path_rc){Remove-Item $output_path_rc}
	If (Test-Path $output_path_ip){Remove-Item $output_path_ip}
	If (Test-Path $output_path_lc){Remove-Item $output_path_lc}

	foreach ($d in $items)
	{	
		
		$item = $d.Name
		$item_path = "$repository\data\revisions\"+$item
		$svnLog = svn log $item_path

		if ($svnLog -like "*Merge from "+$branch+"*"){
			Write-Host "Skipped $item"
			continue
		}

		if ($schema -eq $true) {
			AppendFile -outputFile $output_path_schema -inputFile "$item_path\schema.sql"
		}
		
		if ($data -eq $true) 
		{
			AppendFile -outputFile $output_path_data -inputFile "$item_path\data.sql"
		}
		
		if ($reports -eq $true) 
		{
			AppendFile -outputFile $output_path_reports -inputFile "$item_path\reports.sql"
		}
		
		if ($multilingual -eq $true) 
		{
			AppendFile -outputFile $output_path_ml -inputFile "$item_path\multilingual_references.sql"
		}
		
		if ($systemcomponents -eq $true)
		{
			AppendFile -outputFile $output_path_sc -inputFile "$item_path\systemcomponents.sql"
			AppendFile -outputFile $output_path_cc -inputFile "$item_path\controller_changes.sql"
			AppendFile -outputFile $output_path_mc -inputFile "$item_path\method_changes.sql"
			AppendFile -outputFile $output_path_rc -inputFile "$item_path\ribbon_changes.sql"
			AppendFile -outputFile $output_path_ip -inputFile "$item_path\internal_page_changes.sql"
			AppendFile -outputFile $output_path_lc -inputFile "$item_path\page_method_linking_changes.sql"
		}
		
		$last_merged_file = $item
	}
	(Get-Content ($last_merged_rev_file)) | Foreach-Object {
		$_ -replace "$branch.*", ("$branch : $last_merged_file")
	}  | Set-Content  ($last_merged_rev_file)

	Write-Host "Created file $output_path"
} else {
	Write-Host "No changes since revision: $rev"
}

if($interactive) {
	Write-Host "Press any key to continue ..."
	$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}