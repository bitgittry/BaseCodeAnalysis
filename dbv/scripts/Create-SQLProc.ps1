<#
.SYNOPSIS
    This script creates the sql procedures file

.DESCRIPTION
    This script creates the sql procedures file

.EXAMPLE
    PS> .\Create-SQLProc.ps1
#>
param
(
    [string]$PlatformDir='',
    [string]$OutputDir='',
    [string]$InitFilename='initialize_v_3_9_0.sql'
)

function Merge-Proc
{
    param
    (
        [string]$ProcPath,
        [string]$OutputFile,
        [boolean]$Append = $false
    )

    if (!$Append)
    {
        New-Item $OutputFile -ItemType File -Force > $null
    }

    ForEach($item in Get-ChildItem $ProcPath)
    {
        $content = Get-Content $item.FullName

        $content = $content -replace '^DROP procedure', 'DROP PROCEDURE'
        $content = $content -replace '^DELIMITER\s\${2}', 'DELIMITER ;;'
        $content = $content -replace 'DEFINER[\s]*=[\s]*`[^`]+`@[\s]*`[^`]+`', 'DEFINER=`bit8_admin`@`127.0.0.1`'
        $content = $content -replace '^\s*END\s*\${2}', 'END ;;'
        $content = $content -replace '(?m)^\${2}', ';;'
        $content = $content -replace '^END\s*root\s*\${2}', 'END root ;;'
        $content = $content -replace '(?i)CALL\s+(\w+)\s*(.*)?\s*;', 'CALL `$1`$2;'

        Add-Content $OutputFile "-- -------------------------------------"
        Add-Content $OutputFile ("-- " + ($item.BaseName))
        Add-Content $OutputFile "-- -------------------------------------"
        Add-Content $OutputFile ""

        Add-Content $OutputFile $content
    }
}

function Split-Proc
{
    param
    (
        [string]$SplitFile,
        [string]$OutputDir,
        [string]$MasterProcDir
    )

    if (Test-Path $OutputDir)
    {
        Remove-Item $OutputDir -Recurse -Force
    }

    New-Item $OutputDir -ItemType Directory -Force > $null

    $foundProc = $false
    $procType = 'TYPE'
    $procName = 'PROC'
    $delimiterProc = ''
    $procContent = @()

    $r = [System.IO.File]::OpenText($SplitFile)
    While ($r.Peek() -gt -1)
    {
        $line = $r.ReadLine()
        if ($line -match '^DELIMITER\s(?:\$\$|;;)')
        {
            $delimiterProc = $line
        }

        if ($line -match '^CREATE.+(FUNCTION|PROCEDURE)\s+`(\w+)`')
        {
            $procType = $Matches[1]
            $procName = $Matches[2]
            $filename = (Join-Path $MasterProcDir "$procName.sql")
            $filenameAlt = (Join-Path $MasterProcDir "*$procName.sql")

            if (!((Test-Path $filename) -or (Test-Path $filenameAlt)))
            {
                $procContent += "DROP $procType IF EXISTS ``$procName``;"
                $procContent += ""
                $procContent += $delimiterProc
                $foundProc = $true
            }
        }

        if ($foundProc)
        {
            $procContent += $line
        }

        if ($foundProc -and $line -match '^DELIMITER\s;')
        {
            $procContent += ""
            $filename = (Join-Path $OutputDir "$procName.sql")

            $w = [System.IO.StreamWriter] $filename

            $procContent | % {
                $w.WriteLine($_)
            }

            $w.Close()
            $w.Dispose()

            $foundProc = $false
            $delimiterProc = ''
            $procContent = @()
        }
    }
    $r.Dispose()
}

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding

$currentPath = $PSScriptRoot
$platformPath = $PlatformDir

if ($platformPath -eq '')
{
    $platformPath = Split-Path -Path $currentPath -Parent
} 
else
{
    $platformPath = Resolve-Path $platformPath
}

$dbvPath = (Join-Path $platformPath 'dbv')
$initializeFile = (Join-Path $dbvPath "data\revisions\initialize\$InitFilename")
$procPath = (Join-Path $dbvPath 'stored_routines')

$splitTempDir = [System.Guid]::NewGuid().ToString()
$splitOutDir = (Join-Path $env:TEMP $splitTempDir)
Split-Proc $initializeFile $splitOutDir $procPath

$procFile = (Join-Path $dbvPath 'proc.sql')
# Merge procedure from SplitOutDir
Merge-Proc $splitOutDir $procFile
# Merge procedure from procPath
Merge-Proc $procPath $procFile $true

if ($OutputDir -eq '')
{
    $OutputDir = $dbvPath
}

if ((Split-Path $procFile -Parent) -ne $OutputDir)
{
    if (!(Test-Path $OutputDir))
    {
        New-Item -Type Directory -Path $OutputDir > $null
    }

    Move-Item $procFile -Destination $OutputDir -Force 
}

Remove-Item $splitOutDir -Recurse -Force
