<#
.SYNOPSIS
    This script updates the SharedAssemblyInfo file

.DESCRIPTION
    This script updates the SharedAssemblyInfo file version attributes with the value present in current_version.txt under dbv\compiled folder

.EXAMPLE
    PS> .\Update-SharedAssemblyInfo.ps1
#>
param
(
    [string]$SolutionDir,
    [string]$BuildNumber=''
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

$sharedAssemblyInfoFile = Join-Path $SolutionDir 'SharedAssemblyInfo.cs'
$dbvPath = (Resolve-Path ($SolutionDir + '..\dbv'))
$currentVersionFile = "$dbvPath\compiled\current_version.txt"

if (!(Test-Path $sharedAssemblyInfoFile))
{
    throw [System.IO.FileNotFoundException] "$sharedAssemblyInfoFile not found."
}

if (!(Test-Path $currentVersionFile))
{
    throw [System.IO.FileNotFoundException] "$currentVersionFile not found."
}

$bit8Version = Get-Content $currentVersionFile -Encoding UTF8 -Raw
Write-Host $bit8Version
# Based on Major.Minor.Build.Revision, if Revision part is 0 MSBuild strip it off 0 when the right number differ from 0
if ($BuildNumber -ne '' -and ($bit8Version -replace '((?:\d+\.){3})', '') -eq '0')
{
    $bit8Version = $bit8Version -replace '((?:\d+\.){3})(?:\d)', '$1'
}

$bit8Version += $BuildNumber
$sharedAssemblyInfoContent = Get-Content $sharedAssemblyInfoFile -Encoding UTF8 -Raw

if ($sharedAssemblyInfoContent -notmatch 'AssemblyVersion\("' + $bit8Version + '"')
{
    $sharedAssemblyInfoContent = $sharedAssemblyInfoContent -replace '(?s)\s(\$year\$|\d{4})', (Get-Date).year
    $sharedAssemblyInfoContent = $sharedAssemblyInfoContent -replace '(?s)"((\d+\.?){4})"', "`"$bit8Version`""
    $sharedAssemblyInfoContent = $sharedAssemblyInfoContent.Trim()

    Set-Content $sharedAssemblyInfoFile $sharedAssemblyInfoContent -Encoding UTF8
}
