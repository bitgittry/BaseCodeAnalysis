function Get-ScriptPath
{
  $scriptDir = Get-Variable PSScriptRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.Value }

  if (!$scriptDir)
  {
    if ($MyInvocation.MyCommand.Path)
    {
      $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
    }
  }

  if (!$scriptDir)
  {
    if ($ExecutionContext.SessionState.Module.Path)
    {
      $scriptDir = Split-Path (Split-Path $ExecutionContext.SessionState.Module.Path)
    }
  }

  if (!$scriptDir)
  {
    $scriptDir = $PWD
  }

  return $scriptDir
}

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  get-item (Split-Path $Invocation.MyCommand.Path)
}

Function AppendFile
{
  Param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $outputFile = "",

    [Parameter(Mandatory=$true)]
    [String]
    $inputFile = ""
  )

  Process
  {
    If (Test-Path "$inputFile")
    {
      If((Get-Item $inputFile).length -gt 0)
      {
        #Write-Output "Adding file $inputFile"
        $q = Get-Content $inputFile  -Encoding UTF8 | Out-String 

        # Replace all references to DEFINER with DEFINER=`bit8_admin`@`127.0.0.1`
        if ($q -like '*DEFINER*')
        {
          $q = $q -replace 'DEFINER[\s]*=[\s]*`[^`]+`@[\s]*`[^`]+`', 'DEFINER=`bit8_admin`@`127.0.0.1` '
        }

        # Replace all references of UpdateExistingReport to avoid issue during MySQL execution
        if ($q -like '*UpdateExistingReport*')
        {
          $q = ($q -replace '(?s)((SELECT UpdateExistingReport).+?,\s1\));', '$1 INTO @updateExistingReport;')
        }

        ## ComponentsController
        if ($q -like '*ComponentsControllerCreate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsControllerCreate).+?''\));', '$1 INTO @ComponentsController;')
        }
        if ($q -like '*ComponentsControllerDelete*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsControllerDelete).+?''\));', '$1 INTO @ComponentsController;')
        }
        if ($q -like '*ComponentsControllerUpdate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsControllerUpdate).+?''\));', '$1 INTO @ComponentsController;')
        }
        ## End-ComponentsController
        
        ## ComponentsFunction 
        if ($q -like '*ComponentsFunctionCreate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsFunctionCreate).+?,\s(0|1)\));', '$1 INTO @ComponentsFunction;')
        }
        if ($q -like '*ComponentsFunctionDelete*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsFunctionDelete).+?''\));', '$1 INTO @ComponentsFunction;')
        }
        if ($q -like '*ComponentsFunctionUpdate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsFunctionUpdate).+?''\));', '$1 INTO @ComponentsFunction;')
        }
        ## End-ComponentsFunction 
        
        ## ComponetsInternal 
        if ($q -like '*ComponentsInternalPageCreate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsInternalPageCreate).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        if ($q -like '*ComponentsInternalPageDelete*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsInternalPageDelete).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        if ($q -like '*ComponentsInternalPageUpdate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsInternalPageUpdate).+?''\));', '$1 INTO @ComponetsInternal;')
        }
        ## End-ComponetsInternal 
        
        ## ComponentsPageMethodLinking 
        if ($q -like '*ComponentsPageMethodLinkingCreate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsPageMethodLinkingCreate).+?''\));', '$1 INTO @ComponentsPageMethodLinking;')
        }
        if ($q -like '*ComponentsPageMethodLinkingDelete*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsPageMethodLinkingDelete).+?''\));', '$1 INTO @ComponentsPageMethodLinking;')
        }
        ## End-ComponentsPageMethodLinking 
        
        ## ComponentsRibbon 
        if ($q -like '*ComponentsRibbonCreate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsRibbonCreate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($q -like '*ComponentsRibbonDelete*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsRibbonDelete).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($q -like '*ComponentsRibbonSaveOrderUpdate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsRibbonSaveOrderUpdate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        if ($q -like '*ComponentsRibbonUpdate*')
        {
          $q = ($q -replace '(?s)((SELECT ComponentsRibbonUpdate).+?''\));', '$1 INTO @ComponentsRibbon;')
        }
        ## End-ComponentsRibbon 

        Add-Content $outputFile $q
      }
    }
  }
}

Function RunQuery
{
  Param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $Query = "",

    [Parameter(Mandatory=$true)]
    [bool]
    $isScalar = $False
  )

  Process
  {
    $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection
    $Connection.ConnectionString = $ConnectionString

    Try
    {
      $Connection.Open()

      $cmd = $Connection.CreateCommand()                                        # Create command object
      $cmd.CommandText = $Query                                                 # Load query into object
      if([bool]$isScalar)
      {
        $ret = $cmd.ExecuteScalar()                                             # Execute command returning result
      }
      else
      {
        $ret = $cmd.ExecuteNonQuery()                                           # Execute command returning rows changed
      }

      return $ret
    }
    Catch
    {
      Write-Output "ERROR : Unable to run query : $Query"
      throw
    }
    Finally
    {
      $Connection.Close()
    }
  }
}

Function RunFileSafe
{
  Param
  (
    [Parameter(Mandatory=$True)]
    [String]
    $scriptfile = "",	
    $isDebug = $False
  )

  Process
  {
	Write-Output "$scriptfile"
  
    If (Test-Path $scriptfile)
    {
      If((Get-Item $scriptfile).length -gt 0)
      {
		$filename = [System.IO.Path]::GetTempFileName()
        $outputFile = [System.IO.Path]::GetTempFileName()
        $errorFile = [System.IO.Path]::GetTempFileName()
		
        Write-Output "Running file $scriptfile"

        # Replace all references to DEFINER with DEFINER=`bit8_admin`@`127.0.0.1`
        #$q = $q -replace 'DEFINER[\s]*=[\s]*`[^`]+`@[\s]*`[^`]+`', 'DEFINER=`bit8_admin`@`127.0.0.1` '
       
		$q = Get-Content $scriptfile -Encoding UTF8  | Out-String
		$dummy = Add-Content $filename $q -Encoding UTF8
		$dummy = Add-Content $filename "SELECT 'Please check syntax for this commit';" -Encoding UTF8
		$dummy = Add-Content $filename "DELIMITER ;" -Encoding UTF8
		
		# Start-Process takes input encoding from the parent console input stream settings. 
		# Therefore - set the input encoding to UTF8 before starting the process to avoid
		# having garbled encoding in the mysql input stream, since the input file is UTF8
		$originalEncoding = [Console]::InputEncoding
		[Console]::InputEncoding = [System.Text.Encoding]::UTF8
				
        $p = Start-Process -Wait -NoNewWindow -PassThru -RedirectStandardInput $filename -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -FilePath $mysql_path -ArgumentList $mysql_args
		
		# Restore the input encoding, just to be sure
		[Console]::InputEncoding = $originalEncoding
		
        if (!$isDebug)
        {
          Remove-Item $filename
          Remove-Item $outputFile
        }
        else
        {
          Write-Output "MySQL input: $filename"
          Write-Output "MySQL output: $outputFile"
        }

        if($p.ExitCode -ne 0) 
        {
          $errorFileContent = Get-Content $errorFile | Out-String
          Remove-Item $errorFile
          
          $errorMsg = @"
Last script run was unsuccessful for: $scriptfile.
`t
[MySQL Error]
`t
$errorFileContent
`t
[End-MySQL Error]
`t
"@
          Write-Error $errorMsg
          throw "DB script failed"
        }
        else 
        {
          Remove-Item $errorFile
        }
      }
    }
  }
}

Function GetFolderCreatedRevisions
{
  Param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $path = ""
  )

  Process
  {
    [xml]$svnlog = svn log -r 900:HEAD --verbose --xml $path

    $revs = @{}

    $xml = $svnlog.CreateNavigator().Evaluate('/log/logentry/paths/path[@action="A" and @kind="dir" ]')
    foreach ($x in $xml)
    {
      if($x.ToString() -match "\/([0-9]+)$")
      {
        $dummy = $x.MoveToParent()
        $dummy = $x.MoveToParent()
        Write-Output $matches[1] $x.GetAttribute("revision","")
        $revs.Set_Item($matches[1], $x.GetAttribute("revision",""))
      }
    }

    Write-Output $revs
    return $revs
  }
}

Function CreateNextRevisionDir
{
  Param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $repositoryRoot = ""
  )

  Process
  {
    #get the current platform version number from a file
    $versionFile = Join-Path $repositoryRoot "compiled\current_version.txt"
    $current_version_txt = Get-Content $versionFile -Encoding UTF8

    #split the version number on the fullstop dot
    $version_array = $current_version_txt.split(".")

    #convert the numbers to a string with prefixed zeros
    $Major = ([int]$version_array[0]).ToString("00")
    $Feature = ([int]$version_array[1]).ToString("000")
    $Minor = ([int]$version_array[2]).ToString("000")
    $Fix = ([int]$version_array[3]).ToString("00")

    $base = $Major + $Feature + $Minor + $Fix + "000"

    $revisionsDir = Join-Path $repositoryRoot "data\revisions"
    $items = Get-ChildItem -Path $revisionsDir |  Where-Object {$_.Name -match "^\d+$"} | sort-object -descending -Property {[decimal]$_.Name} | Where-Object {[decimal]$_.Name -ge [decimal]$base} | Where-Object {$_.Name.Substring(0,8) -eq ($Major + $Feature + $Minor)}

    if($items.Length -gt 0)
    {
      $Rev = ([decimal]$items[0].Name.Substring(10)+ 1);
    }
    else
    {
      $Rev = ([decimal]"000");
    }

    $Folder = ($Major + $Feature + $Minor + $Fix + $Rev.ToString("000"))
    $FullFolder = Join-Path $repositoryRoot "data\revisions\$Folder"

    $dummy = New-Item $FullFolder -type directory
    return $FullFolder
  }
}

Function ShowMessage
{
  Param
  (
    [Parameter(Mandatory=$true)]
    [String]
    $message = ""
  )

  Process
  {
    $dummy = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($message)
  }
}

function StopScript()
{
    Exit
}

function RemoveFileSafe
{
  Param
  (
    [Parameter(Mandatory = $true)]
    [String]$filePath = ""
  )

  Process
  {
    If (Test-Path $filePath)
    {
      Remove-Item $filePath
    }
  }
}

function Count-AvailableRevisions
{
  param
  (
    [Parameter(Mandatory = $true)]
    [String]$rev = 0
  )

  Process
  {
    $count = (Get-ChildItem -Directory -Path $dbvDataRevPath\* | Where-Object { $_.Name -match "^\d+$" -and [decimal]$_.Name -gt $rev }).Count
    return $count
  }
}

function Load-MySqlDataLib
{
  [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
}

function Get-MySQLArgs
{
  param
  (
    [Parameter(Mandatory = $true)]
    [String]$dbhost = "127.0.0.1",
    [String]$dbport = "3306",
    [Parameter(Mandatory = $true)]
    [String]$dbuser = "",
    [Parameter(Mandatory = $true)]
    [String]$dbpass = "",
    [Parameter(Mandatory = $true)]
    [String]$dbname = "",
	[String]$dbnameForCheck = ""
  )

  process
  {
  
	  if ($dbnameForCheck.StartsWith("trunk","CurrentCultureIgnoreCase")) 
	  {
		$dbport = "3307"
	  }
	  elseif ($dbnameForCheck.StartsWith("v3_9_","CurrentCultureIgnoreCase")) 
	  {
		$dbport = "3308"
	  }

     $mysqlArgs = "--batch --line-numbers -h $dbhost -P $dbport -u $dbuser -p$dbpass -c --default-character-set=utf8 -C $dbname"
	 return $mysqlArgs
  }
}

function Get-ConnectionString
{
  param
  (
    [Parameter(Mandatory = $true)]
    [String]$dbhost = "127.0.0.1",
    [Parameter(Mandatory = $true)]
    [String]$dbuser = "",
    [Parameter(Mandatory = $true)]
    [String]$dbpass = "",
    [String]$dbname = "",
	[String]$dbnameForCheck = "",
    [String]$dbport = "3306"
  )

  process
  {
    if ($dbname -eq "")
    {
		if ($dbnameForCheck.StartsWith("trunk","CurrentCultureIgnoreCase")) 
		{
			$dbport = "3307"
		}
		elseif ($dbnameForCheck.StartsWith("v3_9_","CurrentCultureIgnoreCase")) 
		{
			$dbport = "3308"
		}
	
		$connString = "server=" + $dbhost + ";port=" + $dbport + ";uid=" + $dbuser + ";pwd=" + $dbpass + ";CharSet=utf8;Pooling=false;Connection Timeout=300;default command timeout=300;"
		
    }
    else
    {
      $connString = "server=" + $dbhost + ";port=" + $dbport + ";uid=" + $dbuser + ";pwd=" + $dbpass + ";database=" + $dbname + ";CharSet=utf8;Pooling=false"
    }
	
    return $connString
  }
}

# Define variable for DBV folder structure

if (!$currentPath)
{
  #$currentPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
  $currentPath = Get-ScriptPath
}

$dbvPath = Split-Path -Path $currentPath -Parent
$dbvDataPath = "$dbvPath\data"
$dbvDataRevPath = "$dbvDataPath\revisions"

# End- Define variable for DBV folder structure
