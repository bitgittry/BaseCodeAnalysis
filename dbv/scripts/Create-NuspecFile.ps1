<#
.SYNOPSIS
    This script generated the Nuget spec file as task inside MSBuild process

.DESCRIPTION
    This script generated the Nuget spec file as task inside MSBuild process

.EXAMPLE
    PS> .\Add-NuspecTask.ps1 -ProjectDir 'bit8_backend_service' -OutputDir 'bin' 
#>
param
(
    [string]$ProjectName,
    [string]$ProjectDir,
    [string]$OutputDir,
    [string]$WrittenFiles,
    [string]$ContentFiles,
    [string]$ConfigFiles,
    [string]$MetadataVersion,
    [string]$Configuration='Release',
    [string]$OutputType,
    [string]$Summary=''
)

function Get-PathRelativeTo
{
    param
    (
        [string]$fullPath, 
        [string]$relativeTo
    )

    process
    {
        try
        {
            # http://stackoverflow.com/questions/703281/getting-path-relative-to-the-current-working-directory
            $file = New-Object Uri($fullPath);
            $folder = New-Object Uri(($relativeTo + {if ($relativeTo.EndsWith("\\")) { '' } else { "\\" } }));
            $relativePath = [System.Uri]::UnescapeDataString(
                ($folder.MakeRelativeUri($file).ToString() -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            )
            return Remove-PathTraversal($relativePath)
        }
        catch
        {
            # Provide some context for the error. This is not very helpful for example: UriFormatException: Invalid URI: The format of the URI could not be determined.
            throw "`nFailed to build the path for '{0}' relative to '{1}':`n{2}." -f $fullPath, $relativeTo, $_.Exception.Message
        }
    }
}

function Remove-PathTraversal
{
    param
    (
        [string]$path
    )

    process
    {
        $pathTraversalChars = (".." + [System.IO.Path]::DirectorySeparatorChar)
        if ($path.StartsWith($pathTraversalChars))
        {
            $path = $path.Replace($pathTraversalChars, [System.String]::Empty);
            return Remove-PathTraversal($path);
        }
        return $path;
    }
}

function Get-FullPath
{
    param
    (
        [string]$relativeOrAbsoluteFilePath
    )
    process
    {
        try
        {
            if (![System.IO.Path]::IsPathRooted($relativeOrAbsoluteFilePath))
            {
                $relativeOrAbsoluteFilePath = [System.IO.Path]::Combine([System.Environment]::CurrentDirectory, $relativeOrAbsoluteFilePath)
            }

            $relativeOrAbsoluteFilePath = [System.IO.Path]::GetFullPath($relativeOrAbsoluteFilePath);
            return $relativeOrAbsoluteFilePath;
        }
        catch
        {
            throw "`nFailed to get the full path for the relative path '{0}':`n{1}." -f $relativeOrAbsoluteFilePath, $_.Exception.Message
        }
    }
}

function Add-Files 
{
    param
    (
        [xml]$nuspec,
        [string[]]$sourceFiles,
        [string]$sourceBaseDirectory,
        [string]$relativeTo = '',
        [string]$targetDirectory = ''
    )

    process
    {
        [string]$destinationPath = ''
        $fileNode = @($nuspec.package.files.file)[0]

        if ([System.IO.Path]::IsPathRooted($relativeTo))
        {
            $relativeTo = (Get-PathRelativeTo -fullPath $relativeTo -relativeTo $sourceBaseDirectory)
        }

        ForEach($sourceFile in $sourceFiles)
        {
            if (![System.IO.Path]::IsPathRooted($sourceFile))
            {
                $sourceFilePath = Join-Path $sourceBaseDirectory $sourceFile
            }

            $sourceFilePath = Get-FullPath $sourceFilePath

            if (!(Test-Path $sourceFilePath))
            {
                Write-Output "The source file '$sourceFilePath' does not exist, so it will not be included in the package"
                continue;
            }

            if ([System.IO.Path]::IsPathRooted($sourceFilePath))
            {
                $sourceFilePath = (Get-PathRelativeTo -fullPath $sourceFilePath -relativeTo $sourceBaseDirectory)
            }

            if ($seenBefore.Contains($sourceFilePath))
            {
                continue;
            }

            [void]$seenBefore.Add($sourceFilePath, $sourceFilePath);

            $destinationPath = $sourceFile

            if (![System.IO.Path]::IsPathRooted($destinationPath))
            {
                $destinationPath = Get-FullPath (Join-Path $sourceBaseDirectory $destinationPath)
            }

            if ([System.IO.Path]::IsPathRooted($destinationPath))
            {
                $destinationPath = Get-PathRelativeTo $destinationPath $sourceBaseDirectory
            }

            if (![System.String]::IsNullOrWhiteSpace($relativeTo))
            {
                if ($destinationPath.ToLower().StartsWith($relativeTo.ToLower()))
                {
                    $destinationPath = $destinationPath.Substring($relativeTo.Length);
                }
            }

            $destinationPath = [System.IO.Path]::Combine($targetDirectory, $destinationPath)

            $newfile = $fileNode.Clone()
            $newfile.src = $sourceFilePath
            $newfile.target = "$destinationPath"
            $nuspec.package.files.AppendChild($newfile) > $null            
        }
    }
}

function Add-FilesByFile 
{
    param
    (
        [xml]$nuspec,
        [string]$sourceFiles,
        [string]$sourceBaseDirectory,
        [string]$relativeTo = '',
        [string]$targetDirectory = ''
    )

    process
    {
        $contents = @()
        if (Test-Path $sourceFiles)
        {
            $contents = (Get-Content $sourceFiles)
        }
        Add-Files -nuspec $nuspec -sourceFiles $contents -sourceBaseDirectory $sourceBaseDirectory -relativeTo $relativeTo -targetDirectory $targetDirectory
    }
}

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

$seenBefore = @{}

$nuspecTemplate = @'
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$id$</id>
    <version>$version$</version>
    <authors>Bit8 Ltd.</authors>
    <owners>Bit8 Ltd.</owners>
    <description>$description$</description>
    <summary>$summary$</summary>
    <projectUrl>https://www.bit8.com</projectUrl> 
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <copyright>Copyright 2016</copyright>
  </metadata>
  <files>
    <file src="" target="" />
  </files>
</package>
'@

Write-Verbose "Input paramters:"
Write-Verbose "ProjectName = '$ProjectName'"
Write-Verbose "ProjectDir = '$ProjectDir'"
Write-Verbose "OutputDir = '$OutputDir'"
Write-Verbose "WrittenFiles = '$WrittenFiles'"
Write-Verbose "ContentFiles = '$ContentFiles'"
Write-Verbose "ConfigFiles = '$ConfigFiles'"
Write-Verbose "MetadataVersion = '$MetadataVersion'"
Write-Verbose "Configuration = '$Configuration'"
Write-Verbose "OutputType = '$OutputType'"
Write-Verbose "Summary = '$Summary'"

$OutputDir = (Resolve-Path $OutputDir)

$nuspecDoc = [xml]$nuspecTemplate
$nuspecDoc.package.metadata.id = $ProjectName
$nuspecDoc.package.metadata.version = $MetadataVersion
$nuspecDoc.package.metadata.description = ("The $ProjectName deployment package")
$nuspecDoc.package.metadata.summary = $Summary
$nuspecDoc.package.metadata.copyright = ("Copyright " + (Get-Date).year)

# Add written files
$targetDirectory = 'bin'
if ($OutputType -eq 'Exe')
{
    $targetDirectory = ''
}
Add-FilesByFile -nuspec $nuspecDoc -sourceFiles $WrittenFiles -sourceBaseDirectory $ProjectDir -relativeTo $OutputDir -targetDirectory $targetDirectory
# Add content files
Add-FilesByFile -nuspec $nuspecDoc -sourceFiles $ContentFiles -sourceBaseDirectory $ProjectDir -relativeTo $OutputDir -targetDirectory ''
# Add app config files
Add-FilesByFile -nuspec $nuspecDoc -sourceFiles $ConfigFiles -sourceBaseDirectory $ProjectDir -relativeTo $OutputDir -targetDirectory ''

# Clean up
$nuspecDoc.package.files.file | ? { $_.src -eq "" } | % { $nuspecDoc.package.files.RemoveChild($_) > $null }

$nodes = $nuspecDoc.SelectNodes("//*[count(@*) = 0 and count(child::*) = 0 and not(string-length(text())) > 0]")

$nodes | %{
    $_.ParentNode.RemoveChild($_)
}

# Save nuspec file
$nuspecFile = Join-Path -Path $ProjectDir -ChildPath ($ProjectName + '.nuspec')
$nuspecDoc.Save($nuspecFile)
