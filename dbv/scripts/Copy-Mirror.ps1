<#
.SYNOPSIS
    This script copy (mirror) file structure from base path to target path

.DESCRIPTION
    This script copy (mirror) file structure from base path to target path safely when there are nested folder path

.EXAMPLE
    PS> .\Copy-Mirror.ps1
#>

[cmdletBinding()]
param
(
    [parameter(Mandatory=$True)]
    [string]$BasePath,
    [parameter(Mandatory=$True)]
    [string]$TargetPath,
    [parameter(Mandatory=$True)]
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

Write-Verbose "BasePath is '$BasePath'"
Write-Verbose "TargetPath is '$TargetPath'"
if ($BasePath -eq $TargetPath)
{
    Write-Error "BasePath and TargetPath cannot be the same"
}

$Files | % {
    $parts = $_.Split('\')
    if ($parts.Count -gt 1)
    {
        $dir = '.'
        $parts = $parts[0..($parts.Count - 2)]
        $parts | % {
            $dir = (Join-Path $dir $_)
            $newDir = (Join-Path $TargetPath $dir)
            if (!(Test-Path $newDir))
            {
                Write-Verbose "Create new directory $newDir"
                New-Item -Type Directory -Path $newDir > $null
            }
        }
    }

    $sourceFile = (Join-Path $BasePath $_)
    $targetFile = (Join-Path $TargetPath $_)
    Write-Verbose "Copy $sourceFile to $targetFile"
    Copy-Item -Path $sourceFile -Destination $targetFile
}
