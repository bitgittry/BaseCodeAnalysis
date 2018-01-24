<#
.SYNOPSIS
    This script creates the bit8bamboo.conf file used to inject variables

.DESCRIPTION
    This script creates the bit8bamboo.conf file used to inject variables

.EXAMPLE
    PS> .\Create-Bit8BambooConf.ps1
#>
param
(
    [string]$OutputDir,
    [string]$BuildNumber=''
)

$OutputEncoding = [Console]::OutputEncoding

$currentPath = $PSScriptRoot
$platformPath = Split-Path -Path $currentPath -Parent
$dbvPath = (Join-Path $platformPath 'dbv')

$OutputDir = Resolve-Path $OutputDir

$bit8BambooConfFile = 'bit8bamboo.conf'

$bit8Version = Get-Content (Join-Path $dbvPath 'compiled\current_version.txt')

# Based on Major.Minor.Build.Revision, if Revision part is 0 MSBuild strip it off 0 when the right number differ from 0
if ($BuildNumber -ne '' -and ($bit8Version -replace '((?:\d+\.){3})', '') -eq '0')
{
    $bit8Version = $bit8Version -replace '((?:\d+\.){3})(?:\d)', '$1'
}

$tempConfFile = ([System.Guid]::NewGuid().ToString() + ".tmp")
$tempConfFile = (Join-Path $env:TEMP $tempConfFile)

$conf = @{}
$conf.Add("buildNumber", "${bit8Version}${BuildNumber}")

$conf.GetEnumerator() | % {
    $_.Name + "=" + $_.Value | Out-File $tempConfFile -Append -Encoding ascii
}

if (!(Test-Path $OutputDir))
{
    New-Item -Type Directory -Path $OutputDir
}

Move-Item -Path $tempConfFile -Destination (Join-Path $OutputDir $bit8BambooConfFile) -Force
