<#
.SYNOPSIS
    This script run MSBuild per project

.DESCRIPTION
    This script run MSBuild per project

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName>

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -Configuration Debug

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -BuildNumber 20

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -BuildPackageSummary "Obfuscated package. Bamboo build [20]"

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -OverwriteConfig

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -MSBuildVerbosity

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -PreProcess

.EXAMPLE
    PS> .\Invoke-MSBuildProj.ps1 -ProjectPath <ProjectPath> -ProjectName <ProjectName> -pp
#>

[cmdletBinding()]
param
(
  [parameter(Mandatory=$True)]
  [alias("pp")]
  [string]$ProjectPath,
  [parameter(Mandatory=$True)]
  [alias("pn")]
  [string]$ProjectName,
  [string]$Configuration="Release",
  [alias("pbk")]
  [string]$ParentBuildKey='',
  [alias("bn")]
  [string]$BuildNumber='',
  [alias("bps")]
  [string]$BuildPackageSummary='',
  [parameter(Mandatory=$False, HelpMessage="Delete any bin or obj folder before to run MSBuild.exe")]
  [switch]$Clean,
  [parameter(Mandatory=$False, HelpMessage="Overwrite the current App.config or Web.config file with the default one")]
  [alias("oc")]
  [switch]$OverwriteConfig,
  [parameter(Mandatory=$False, HelpMessage="Tell to MSBuild.exe to active verbosity at minimal level")]
  [switch]$MSBuildVerbosity,
  [parameter(Mandatory=$False, HelpMessage="Tell to MSBuild.exe to preprocess to check build project and not run")]
  [alias("pre")]
  [switch]$PreProcess,
  [parameter(Mandatory=$False, HelpMessage="Tell to MSBuild.exe to package applications")]
  [alias("pkg")]
  [switch]$Package,
  [switch]$PackageExe,
  [bool]$DisableNuGetPackage=$False,
  [string]$SolutionDir,
  [string]$MSBuildExe = 'C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe'
)

function ExitWithCode
{
    param
    (
        $exitCode
    )

    $host.SetShouldExit($exitCode)
    exit
}

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding
$currentPath = $PSScriptRoot

#$MSBuildExe = 'C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe'

if (Get-Command $MSBuildExe -ErrorAction SilentlyContinue)
{
    $platformPath = Split-Path $currentPath -Parent
    $appConfigsPath = Join-Path $platformPath 'AppConfigs'
    $bit8GamingSolutionPath = Join-Path $platformPath 'bit8_gaming_solution'
    $projectFile = (Join-Path $bit8GamingSolutionPath $ProjectPath | Join-Path -ChildPath ($ProjectName + '.csproj'))
    $webConfigFile = (Join-Path $bit8GamingSolutionPath $ProjectPath | Join-Path -ChildPath 'Web.config')
    #$packageBasePath = Join-Path $platformPath 'Packages'

    $MSBuildArgs = @()
    $MSBuildArgs += ($projectFile + ' ')
    $MSBuildArgs += "/p:Configuration=$Configuration"
    $MSBuildArgs += "/p:VisualStudioVersion=14.0 /nr:False" # Bamboo MSBuildParams
	$MSBuildArgs += " /t:Rebuild"

    if ($ParentBuildKey -ne '')
    {
        $MSBuildArgs += "/p:ParentBuildKey=$ParentBuildKey"
    }
    if ($BuildNumber -ne '')
    {
        $MSBuildArgs += "/p:BuildNumber=$BuildNumber"
    }
    if ($BuildPackageSummary -ne '')
    {
        $MSBuildArgs += "/p:BuildPackageSummary=$BuildPackageSummary"
    }
    if ($PreProcess.IsPresent)
    {
        $MSBuildArgs += "/pp"
    }
    if ($MSBuildVerbosity.IsPresent)
    {
        $MSBuildArgs += "/nologo /noconsolelogger /fl /flp:Encoding=UTF-8 /verbosity:minimal"
    }
    if ((Test-Path($webConfigFile)) -and $Package.IsPresent)
    {
        $MSBuildArgs += "/t:Package"
        #$MSBuildArgs += "/p:PackageLocation=$($packageBasePath)\$($ProjectName).zip"
        #$MSBuildArgs += "/p:Platform=AnyCPU"
        $MSBuildArgs += "/p:DeleteExistingFiles=False"
        $MSBuildArgs += "/p:SkipExtraFilesOnServer=True"
        $MSBuildArgs += "/p:ReplaceMatchingFiles=True"
    }
    if ($PackageExe.IsPresent)
    {
        $MSBuildArgs += "/p:PackageExe=True"
    }
    $MSBuildArgs += "/p:DisableNuGetPackage=True"

    # Clean
    if ($Clean.IsPresent)
    {
        $CleanCmd = Join-Path $currentPath 'Clean-SolutionPlatform.ps1'

        if (Test-Path $CleanCmd)
        {
            [System.Console]::Write("  Clean up folder ... ")
            & $CleanCmd
            Write-Host "done"
        }
        else
        {
            Write-Warning ("The '{0}' script is not present" -f $CleanCmd)
        }
    }

    # Overwrite AppConfigs
    if ($OverwriteConfig.IsPresent)
    {
        [System.Console]::Write("  Overwriting the config files ... ")
        xcopy (Join-Path $appConfigsPath $ProjectPath) (Join-Path $bit8GamingSolutionPath $ProjectPath) /s /i /Y
        Write-Host "done"
    }
	
	

    Write-Verbose "`n`nRun MSBuild.exe with arguments '$MSBuildArgs'"

<#
    # Setup the Process startup info
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $MSBuildExe
    $pinfo.Arguments = $MSBuildArgs
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    # Create a process object using the startup info
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    $process.Start()
    $process.WaitForExit()
    # get output from stdout and stderr
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

    $stdout
    $stderr

    ExitWithCode $process.ExitCode
#>

    $stdOutFile = $null
    $stdErrFile = $null

    try
    {
        $stdOutFile = [System.IO.Path]::GetTempFileName()
        $stdErrFile = [System.IO.Path]::GetTempFileName()

        #$p = Start-Process $MSBuildExe -ArgumentList $MSBuildArgs -NoNewWindow -Wait -PassThru `
        #        -RedirectStandardOutput $stdOutFile `
        #        -RedirectStandardError $stdErrFile
		
		$p = Start-Process $MSBuildExe -ArgumentList $MSBuildArgs -NoNewWindow -Wait -PassThru

        Write-Host (Get-Content $stdOutFile | Out-String)

        if ($p.ExitCode -ne 0)
        {
            $stdErrContent = (Get-Content $stdErrFile | Out-String)
            $stdErrContent = "`nExit code $($p.ExitCode)`n" + $stdErrContent
            throw $stdErrContent
        }
    }
    finally
    {
        if ($stdOutFile) { Remove-Item $stdOutFile }
        if ($stdErrFile) { Remove-Item $stdErrFile }
    }
}
else
{
    Write-Error ("MSBuild.exe is not available in your system ('{0}')" -f $MSBuildExe)
}
