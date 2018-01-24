param 
(
  [string]$rev = "",
  [string]$outputFile = "",
  [bool]$schema = $True,
  [bool]$storedProcedures = $true,
  [bool]$views = $true,
  [bool]$data = $True,
  [bool]$reports = $True,
  [bool]$multilingual = $True,
  [bool]$systemcomponents = $True,
  [int]$parentProgressId = -1,
  [bool]$silentMode = $False
)

$interactive = $false

#$currentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$currentPath = $PSScriptRoot

. "$currentPath\dbv_common.ps1"

$revFile = "$currentPath\revisions.txt"

if($rev -eq "") {
	$rev = Read-Host "From which revision? (NOT included)"
	$interactive = $true
}

if(-Not ($rev -match "^\d+$")) {
	throw "Revision from which to start is required as an integer"
}

RemoveFileSafe "$currentPath\*.tmp"
$tempFile = ("$currentPath\" +[System.Guid]::NewGuid().toString())+".tmp"

$count = Count-AvailableRevisions $rev

if ($count -gt 0)
{
  If (!$silentMode)
  {
    Write-Progress -Id 1 -ParentId $parentProgressId -Activity "Extract revisions from $rev"
  }
  
  Get-ChildItem -Directory -Path $dbvDataRevPath\* | Where-Object { $_.Name -match "^\d+$" -and [decimal]$_.Name -gt $rev } | ForEach-Object { $_.Name } | Out-File $revFile

  Add-Content $tempFile "SET character_set_client  = utf8;" -Encoding UTF8
  Add-Content $tempFile "SET character_set_results = utf8;" -Encoding UTF8
  Add-Content $tempFile "SET collation_connection  = utf8_general_ci;" -Encoding UTF8
  Add-Content $tempFile "" -Encoding UTF8

  $i = 0;
  $last_rev = $rev
  ForEach ($revision in Get-Content $revFile )
  {
    $i++
    $last_rev = $revision

    If (!$silentMode)
    {   
      $percentComplete = [Math]::Floor($i / $count * 100)
      Write-Progress -Id 1 -ParentId $parentProgressId -Activity "Extract revisions..." -CurrentOperation "$revision" -Status "Processing $percentComplete%" -PercentComplete $percentComplete
    }

    $item_path = "$dbvDataRevPath\$revision"
    
    if ($schema -eq $true) {
      AppendFile -outputFile $tempFile -inputFile "$item_path\schema.sql"
    }
    
    if ($storedProcedures -eq $true) {
      AppendFile -outputFile $tempFile -inputFile "$item_path\storedProcedures.sql"
    }
	
	if ($views -eq $true) {
      AppendFile -outputFile $tempFile -inputFile "$item_path\views.sql"
    }
    
    if ($data -eq $true) 
    {
      AppendFile -outputFile $tempFile -inputFile "$item_path\data.sql"
    }
    
    if ($reports -eq $true) 
    {
      AppendFile -outputFile $tempFile -inputFile "$item_path\reports.sql"
    }
    
    if ($multilingual -eq $true) 
    {
      AppendFile -outputFile $tempFile -inputFile "$item_path\multilingual_references.sql"
    }
    
    if ($systemcomponents -eq $true)
    {
	  AppendFile -outputFile $tempFile -inputFile "$item_path\systemcomponents.sql"
      AppendFile -outputFile $tempFile -inputFile "$item_path\controller_changes.sql"
      AppendFile -outputFile $tempFile -inputFile "$item_path\method_changes.sql"
      AppendFile -outputFile $tempFile -inputFile "$item_path\ribbon_changes.sql"
      AppendFile -outputFile $tempFile -inputFile "$item_path\internal_page_changes.sql"
      AppendFile -outputFile $tempFile -inputFile "$item_path\page_method_linking_changes.sql"
    }

    Add-Content $tempFile "UPDATE gaming_system_versions SET dbv_version = '$last_rev' WHERE system_version_id = 1;"
    Add-Content $tempFile ""
  }
  
  if ($outputFile -eq "")
  {
    $outputFile = "$currentPath\version_from_{0}_to_{1}.sql" -f $rev, $last_rev
  }

  RemoveFileSafe $outputFile
  Move-Item -Path $tempFile -Destination $outputFile -Force
  
  Write-Output "Created file $outputFile"

  RemoveFileSafe $revFile
  
  If (!$silentMode)
  {
    Write-Progress -Id 1 -ParentId $parentProgressId -Activity "Extracted revisions" -Completed
  }
}
else
{
  Write-Output "No changes since revision: $rev"
}

if($interactive) {
  Write-Output "Press any key to continue..."
  $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
