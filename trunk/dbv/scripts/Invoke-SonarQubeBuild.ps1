
########### Get Version Number #############
[cmdletBinding()]
param
(
    [string]$SolutionDir,
    [string]$RevisionNumber='',
	[string]$MSBuildExe = 'C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe',
	[string]$SonarUsername,
	[string]$SonarPassword
	
)

$dbvPath = (Resolve-Path ($SolutionDir + '\..\dbv'))
$currentVersionFile = "$dbvPath\compiled\current_version.txt"
if (!(Test-Path $currentVersionFile))
{
    throw [System.IO.FileNotFoundException] "$currentVersionFile not found."
}

$bit8Version = Get-Content $currentVersionFile -Encoding UTF8 -Raw

# Based on Major.Minor.Build.Revision, if Revision part is 0 MSBuild strip it off 0 when the right number differ from 0
if (($bit8Version -replace '((?:\d+\.){3})', '') -eq '0')
{
    $bit8Version = $bit8Version -replace '((?:\d+\.){3})(?:\d)', '$1'  #Strip off 0
}

$bit8Version += $RevisionNumber

############################################

$PathToSonar = "C:\sonarqube-6.1\bin\sonar-scanner-msbuild-2.2.0.24\"
$PathToMSBuildConfig = Join-Path $PathToSonar "MSBuild.SonarQube.Runner.exe"
$currentPath = $PSScriptRoot
$SonarPreProcess = "$PathToMSBuildConfig begin /k:'Bit8_Services' /n:'Bit8 Services' /v:'$bit8Version' /d:sonar.scm.enabled=true /d:sonar.scm.provider=svn /d:sonar.login=$SonarUsername /d:sonar.password=$SonarPassword"

try {
	Invoke-Expression $SonarPreProcess -ErrorVariable e
} catch {
	Write-Host "Sonar PreProcess for Bit8_Services failed with error = $_"
}


$projects = @(
  @{'ProjectPath'= 'bit8_backend_service'; 'ProjectName'='bit8_backend_service'},
  @{'ProjectPath'= 'bit8_bonus_system_service'; 'ProjectName'='bit8_bonus_system_service'},
  @{'ProjectPath'= 'bit8_common_wallet_integration'; 'ProjectName'='bit8_common_wallet_integration'},
  @{'ProjectPath'= 'bit8_generic_integrations_public'; 'ProjectName'='bit8_generic_integrations_public'},
  #@{'ProjectPath'= 'bit8_job_service'; 'ProjectName'='bit8_job_service'},
  @{'ProjectPath'= 'bit8_multibrand_router'; 'ProjectName'='bit8_multibrand_router'},
  @{'ProjectPath'= 'bit8_payment_integration'; 'ProjectName'='bit8_payment_integration'},
  @{'ProjectPath'= 'bit8_portal_service_v2.0'; 'ProjectName'='bit8_portal_service_v2.0'},
  @{'ProjectPath'= 'bit8_third_party_integration'; 'ProjectName'='bit8_third_party_integration'},
  @{'ProjectPath'= 'bit8_wcf_router'; 'ProjectName'='bit8_wcf_router'},
  #@{'ProjectPath'= 'obulus_job_service'; 'ProjectName'='obulus_job_service'},
  @{'ProjectPath'= 'PushIntegrations'; 'ProjectName'='PushIntegrations'}
)

 $msbuildLogsPath = (Join-Path $currentPath "msbuild_logs")
 if (!(Test-Path $msbuildLogsPath))
 {
     New-Item -ItemType Directory $msbuildLogsPath > $null
 }

foreach($project in $projects)
{
    [System.Console]::Write("  Invoke-MSBuildPrj_SonarQube for ProjectPath = '{0}', ProjectName = '{1}' ... ", $project.ProjectPath, $project.ProjectName)
    & (Join-Path $currentPath "Invoke-MSBuildPrj_SonarQube.ps1") -pp $project.ProjectPath -pn $project.ProjectName -SolutionDir $SolutionDir -MSBuildExe $MSBuildExe *> "$msbuildLogsPath\msbuild_$($project.ProjectName)_$(Get-Date -Format yyyyMMddHHmmss).log"
    Write-Host "done"
}
		

$SonarPostProcess = "$PathToSonar\MSBuild.SonarQube.Runner.exe end"

try {
	Invoke-Expression $SonarPostProcess -ErrorVariable e
} catch {
	Write-Host "Sonar PostProcess for Bit8_Services failed with error = $_"
}

########### Execute Sonar for Dependent Projects ##############
$PathToSonar = "C:\sonarqube-6.1\bin\sonar-scanner-msbuild-2.2.0.24\"
$PathToMSBuildConfig = Join-Path $PathToSonar "MSBuild.SonarQube.Runner.exe"
$SonarPreProcess = "$PathToMSBuildConfig begin /k:'Bit8_Core' /n:'Bit8 Core' /v:'$bit8Version' /d:sonar.scm.enabled=true /d:sonar.scm.provider=svn /d:sonar.login=$SonarUsername /d:sonar.password=$SonarPassword"

try {
	Invoke-Expression $SonarPreProcess -ErrorVariable e
} catch {
	Write-Host "Sonar PreProcess for Bit8_Core failed with error = $_"
}


$projects = @(
  @{'ProjectPath'= 'obulus_gaming_manager'; 'ProjectName'='bit8_integration_manager'}
)

foreach($project in $projects)
{
    [System.Console]::Write("  Invoke-MSBuildPrj_SonarQube for ProjectPath = '{0}', ProjectName = '{1}' ... ", $project.ProjectPath, $project.ProjectName)
    & (Join-Path $currentPath "Invoke-MSBuildPrj_SonarQube.ps1") -pp $project.ProjectPath -pn $project.ProjectName -SolutionDir $SolutionDir -MSBuildExe $MSBuildExe *> "$msbuildLogsPath\msbuild_$($project.ProjectName)_$(Get-Date -Format yyyyMMddHHmmss).log"
    Write-Host "done"
}

$SonarPostProcess = "$PathToSonar\MSBuild.SonarQube.Runner.exe end"

try {
	Invoke-Expression $SonarPostProcess -ErrorVariable e
} catch {
	Write-Host "Sonar PostProcess for Bit8_Core failed with error = $_"
}
