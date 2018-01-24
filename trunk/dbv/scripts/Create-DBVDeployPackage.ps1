<#
.SYNOPSIS
    This script creates the bit8_dbv.zip package

.DESCRIPTION
    This script creates the bit8_dbv.zip package

.EXAMPLE
    PS> .\Create-DBVDeployPackage.ps1
#>
param
(
    [string]$PlatformDir='',
    [string]$OutputDir=".\..\Packages",
    [string]$MetadataVersion="1.0.0"
)

function Set-EnsureDirectoryExists
{
    [cmdletbinding()]
    param (
        [string]$path
    )

    if (Test-Path $path -PathType Container) {
        [System.IO.Directory]::CreateDirectory($path) > $null
    }
}

function Set-CrossPlatformDirectorySeparator
{
    [cmdletbinding()]
    param (
        [string]$path
    )

    if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
        return $path.Replace('\', '/');
    }

    return $path;
}

function New-ZipPackage
{
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$basePath,
        [parameter(Mandatory=$true)]
        [string[]]$includes,
        [parameter(Mandatory=$true)]
        [PSCustomObject]$zipFileName,
        [parameter(Mandatory=$true)]
        [string]$outFolder,
        [parameter(Mandatory=$false)]
        [boolean]$overwrite=$false
    )

    Add-Type -Assembly System.IO.Compression

    $filename = $zipFileName;

    $output = [System.IO.Path]::GetFullPath((Join-Path $outFolder $filename));

    if ((Test-Path($output)) -and !$overwrite) {
        throw "The package file already exists and -overwrite was not specified"
    }

    Write-Output ("Saving {0} to {1}..." -f $filename, $outFolder)

    Set-EnsureDirectoryExists $outFolder

    $basePathLength = [System.IO.Path]::GetFullPath($basePath).Length;

    $stream = $null
    $archive = $null

    try {
        $stream = New-Object System.IO.FileStream($output, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $archive = New-Object System.IO.Compression.ZipArchive($stream, 'Create')

            foreach ($pattern in $includes)
            {
                Write-Output ("Adding files from '{0}' matching pattern '{1}'" -f $basePath, $pattern)

                $seenBefore = @{}

                foreach ($file in Get-ChildItem -Path $basePath -Include $pattern -Recurse) {
                    $fullFilePath = [System.IO.Path]::GetFullPath($file);

                    if ($fullFilePath -ieq $output) {
                        continue;
                    }

                    $relativePath = Set-CrossPlatformDirectorySeparator $fullFilePath.Substring($basePathLength).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

                    if ((Test-Path $fullFilePath -PathType Leaf)) {
                        Write-Output ("Adding file: " + $relativePath);                        
                        $entry = $archive.CreateEntry("$relativePath".Replace([System.IO.Path]::DirectorySeparatorChar, '/'), 'Optimal');
                        $entry.LastWriteTime = New-Object DateTimeOffset($file.LastWriteTimeUtc);

                        $entryStream = $null
                        $sourceStream = $null

                        try {
                            $entryStream = $entry.Open()
                            try {
                                $sourceStream = [System.IO.File]::OpenRead($file)
                                $sourceStream.CopyTo($entryStream)
                            }
                            finally {
                                if ($sourceStream -ne $null) {
                                    $sourceStream.Dispose()
                                }
                            }
                        }
                        finally {
                            if ($entryStream -ne $null) {
                                $entryStream.Dispose()
                            }
                        }                        
                    }
                    elseif ((Get-ChildItem "$file\*" | Select-Object -First 1 | Measure-Object).Count -eq 0) {
                        Write-Output ("Adding folder: " + $file)
                        $entry = $archive.CreateEntry("$relativePath/", 'Optimal');
                        $entry.LastWriteTime = New-Object DateTimeOffset($file.LastWriteTimeUtc);
                    }
                }
            }
        }
        finally {
            if ($archive -ne $null) {
                $archive.Dispose()
            }
        }
    }
    finally {
        if ($stream -ne $null) {
            $stream.Dispose()
        }
    }
}

function Copy-Deps
{
    param
    (
        [string]$baseSource,
        [string]$baseTarget,
        $deps
    )

    $deps | % {
        $parts = $_.Split('\')
        if ($parts.Count -gt 1)
        {
            $dir = '.'
            $parts = $parts[0..($parts.Count - 2)]
            $parts | % {
                $dir = (Join-Path $dir $_)
                if (!(Test-Path (Join-Path $baseTarget $dir)))
                {
                    New-Item -Type Directory -Path (Join-Path $baseTarget $dir) > $null
                }
            }
        }

        Copy-Item -Path (Join-Path $baseSource $_) -Destination (Join-Path $baseTarget $_)
    }
}

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

$platformPath = $PlatformDir
$zipFilename = "bit8_dbv.$MetadataVersion.zip"

if ($platformPath -eq '')
{
    $platformPath = Split-Path -Path $currentPath -Parent
} 
else
{
    $platformPath = Resolve-Path $platformPath
}

$toolsPath = Join-Path $platformPath 'tools'

Write-Host "Create DBV deploy package"

# Create temporary folder
$dbvPath = (Join-Path $platformPath 'dbv')
$workingDir = ('dbv-deploy_' + [System.Guid]::NewGuid().ToString())
$workingPath = Join-Path $env:TEMP $workingDir
$tempDbvPath = Join-Path $workingPath 'dbv'
$tempDbvCompiledPath = (Join-Path $tempDbvPath 'compiled')

[System.Console]::Write("  Create temporary working folder '{0}' ... ", $workingDir)
New-Item -Type Directory -Path $workingPath > $null
New-Item -Type Directory -Path $tempDbvPath > $null
Write-Host "done"

# Copy resources from compiled folder
$compiledDeps = @(
    'compiled\dbv_common.ps1',
    'compiled\drop_initialize_fast.ps1',
    'compiled\extract_versions.ps1',
    'compiled\extract_versions_bamboo.ps1'
)

[System.Console]::Write("  Copy dependencies under 'compiled' folder ... ")
Copy-Deps $dbvPath $tempDbvPath $compiledDeps
Write-Host "done"

# Copy resources from deploy folder
$deployDeps = @(
    'deploy\config.json.template',
    'deploy\dbv.ps1',
    'deploy\dbv.py',
    'deploy\dbv_deploy.ps1',
    'deploy\dbv_deploy.py',
    'deploy\dbv_deploy_py.ps1',
    'deploy\dbv_deploy_py.sh',
    'deploy\dbv_lib.ps1',
    'deploy\dbv_lib.py',
    'deploy\libs\MySql.Data.dll'
)

[System.Console]::Write("  Copy dependencies under 'deploy' folder ... ")
Copy-Deps $dbvPath $tempDbvPath $deployDeps
Write-Host "done"

[System.Console]::Write("  Copy resources under 'data' folder ... ")
Copy-Item -Destination (Join-Path $tempDbvPath 'data') -Path (Join-Path $dbvPath 'data') -Recurse
Write-Host "done"

# Copy proc.sql if is available
if (Test-Path (Join-Path $dbvPath 'proc.sql'))
{
    [System.Console]::Write("  Copy 'proc.sql' file ... ")
    Copy-Item -Destination $tempDbvPath -Path (Join-Path $dbvPath 'proc.sql')
    Write-Host "done"

    [System.Console]::Write("  Delete 'storedProcedures.sql' file ... ")
    Get-ChildItem (Join-Path $tempDbvPath 'data\revisions\*\storedProcedures.sql') -File | % { Remove-Item $_.FullName }
    Write-Host "done"
}

[System.Console]::Write("  Delete empty files from 'data\revisions\*' ... ")
Get-ChildItem (Join-Path $tempDbvPath 'data\revisions\*') -File | ? { $_.Length -eq 0 } | % { Remove-Item $_.FullName }
Write-Host "done"

[System.Console]::Write("  Delete empty folders from 'data\revisions\*' ... ")
Get-ChildItem (Join-Path $tempDbvPath 'data\revisions') -Directory | ? { $_.GetFileSystemInfos().Count -eq 0 } | % { Remove-Item $_.FullName }
Write-Host "done"

[System.Console]::Write("  Get last revision in current 'data\revisions' ... ")
$lastRevision = (Get-ChildItem -Directory (Join-Path $dbvPath 'data\revisions' ) | ? { $_.Name -match "^\d+$" } | Select-Object -Property Name, @{Name="Revision"; Expression={[decimal]$_.Name}} | Sort-Object -Property Revision -Descending | Select-Object -First 1)
Write-Host ("done. Last revision is '{0}'" -f $lastRevision.Name)

if (!(Test-Path(Join-Path $tempDbvPath 'data\revisions' | Join-Path -ChildPath $lastRevision.Name)))
{
    New-Item -Type Directory -Path (Join-Path $tempDbvPath 'data\revisions' | Join-Path -ChildPath $lastRevision.Name) > $null
}

[System.Console]::Write("  Create zip file '{0}' ... ", $zipFilename)
New-ZipPackage -basePath $workingPath -includes @("**") -zipFileName $zipFilename -outFolder $workingPath
Write-Host "done"

if (!(Test-Path $OutputDir))
{
    New-Item -Type Directory -Path $OutputDir > $null
}

[System.Console]::Write("  Move zip file '{0}' to '{1}' ... ", $zipFilename, $OutputDir)
Move-Item -Path (Join-Path $workingPath $zipFilename) -Destination $OutputDir -Force
Write-Host "done"

[System.Console]::Write("  Remove temporary working folder '{0}' ... ", $workingDir)
Remove-Item $workingPath -Recurse -Force
Write-Host "done"
