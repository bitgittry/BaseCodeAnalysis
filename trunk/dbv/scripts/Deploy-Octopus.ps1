<#
.SINOPSIS

This script allow to perform a deployment using Octopus Server


.DESCRIPTION

The Deploy-Octopus script allow to perform a deployment using an Octopus Server.
This script is based on https://gist.github.com/Dalmirog/05fb70903c0b3c0d9572


.SYNTAX

Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> -Create [[-ReleaseVersion] <Object>] [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> -Delete [-ReleaseVersion] <Object> [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> -Exists [-ReleaseVersion] <Object> [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> -Promote [-ReleaseVersion] <Object> [-EnvironmentName] <string> [[-Filter] <string[]>] [-FilterByURI] [[-SkipActions] <string[]>] [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> -Deploy [-ReleaseVersion] <Object> [-EnvironmentName] <string> [[-Filter] <string[]>] [-FilterByURI] [[-SkipActions] <string[]>] [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-ProjectName] <string> [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-DeploymentId] <string> -TryAgainDeploy [[-SkipActions] <string[]>] [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-DeploymentId] <string> -CancelDeployment [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-DeploymentId] <string> -DeleteDeployment [-Json] [<CommonParameters>]
Deploy-Octopus.ps1 [-ApiKey] <string> [-OctopusURL] <string> [-DeploymentId] <string> [-ManualResult] <string> [-Json] [<CommonParameters>]


.EXAMPLE

Get an overview of project

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda

.EXAMPLE

Create an new release for given project with default release version

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Release

.EXAMPLE

Create an new release for given project with specific release version

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Release -ReleaseVersion 3.9.11.40

.EXAMPLE

Deploy a specific release for given project on specific environment

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Deploy -ReleaseVersion 3.9.11.40 -EnvironmentName Staging

.EXAMPLE

Deploy a specific release for given project on specific environment and filtered machines

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Deploy -ReleaseVersion 3.9.11.40 -EnvironmentName Staging -Filter @("bit8-branda*")

.EXAMPLE

Deploy a specific release for given project on specific environment and filtered machines by uri

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Deploy -ReleaseVersion 3.9.11.40 -EnvironmentName Staging -Filter @(":10933") -FilterByURI

.EXAMPLE

Submit Proceed/Abort for manual step for specific deployment

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -DeploymentId Deployments-305 -ManualResult Proceed

.EXAMPLE

Get deployment status per specific id

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -DeploymentId Deployments-305

.EXAMPLE

Promote a release to specified environment

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Promote -ReleaseVersion 3.9.11.40 -EnvironmentName Production

.EXAMPLE

Promote a release to specified environment and filter machine

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Promote -ReleaseVersion 3.9.11.40 -EnvironmentName Production -Filter @("bit8-branda*")

.EXAMPLE

Promote a release to specified environment and filter machine by uri

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Promote -ReleaseVersion 3.9.11.40 -EnvironmentName Production -Filter @("*:10934") -FilterByURI

.EXAMPLE

Test if a specified release version exists for given project

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Exists -ReleaseVersion 3.9.11.40

.EXAMPLE

Delete a specified release version for given project

Deploy-Octopus.ps1 -ApiKey API-UNVCKYJG8HRJ5FTANORPMSOJM -OctopusURL http://10.166.166.100 -ProjectName bit8-branda -Delete -ReleaseVersion 3.9.11.40

#>
[cmdletbinding(DefaultParameterSetName="CreateRelease")]
param
(
    [parameter(Position=0, Mandatory=$true, HelpMessage="The Octopus api key eligible to perform the deployment")]
    [string]$ApiKey,
    [parameter(Position=1, Mandatory=$true, HelpMessage="The Octopus url to run the deployment")]
    [string]$OctopusURL,
    [parameter(Position=2, Mandatory=$true, ParameterSetName="Overview", HelpMessage="The project name wants to see an overview")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="CreateRelease", HelpMessage="The project name wants to create a new release")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="DeployRelease", HelpMessage="The project name wants to do a deploment")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="ExistsRelease", HelpMessage="The project name wants to check for existence of release")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="DeleteRelease", HelpMessage="The project name wants to which delete a release")]
    [string]$ProjectName,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="CreateRelease", HelpMessage="Ask to the script to create a new release")]
    [switch]$Create,
    [parameter(Position=4, Mandatory=$false, ParameterSetName="CreateRelease", HelpMessage="Override the default release version that should be created")]
    [parameter(Position=4, Mandatory=$true, ParameterSetName="DeployRelease", HelpMessage="Specify which release version should be deployed")]
    [parameter(Position=4, Mandatory=$true, ParameterSetName="ExistsRelease", HelpMessage="Specify which release version should be verify for existence")]
    [parameter(Position=4, Mandatory=$true, ParameterSetName="DeleteRelease", HelpMessage="Specify which release version should be deleted")]
    [object]$ReleaseVersion,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="DeployRelease", HelpMessage="Ask to the script to make a new deployment")]
    [switch]$Deploy,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="TryAgainDeployRelease", HelpMessage="Ask to the script to cancel a deployment")]
    [switch]$TryAgainDeploy,
    [parameter(Position=5, Mandatory=$true, ParameterSetName="DeployRelease", HelpMessage="The environment name target of the deployment")]
    [parameter(Position=4, Mandatory=$true, ParameterSetName="PromoteRelease", HelpMessage="The environment name target of the deployment")]
    [string]$EnvironmentName,
    [parameter(Position=6, Mandatory=$false, ParameterSetName="DeployRelease", HelpMessage="Pattern to filter machines. e.g. `"*:10934`",`"*db*`",`"http://Webserver1`"")]
    [parameter(Position=5, Mandatory=$false, ParameterSetName="PromoteRelease", HelpMessage="Pattern to filter machines. e.g. `"*:10934`",`"*db*`",`"http://Webserver1`"")]
    [string[]]$Filter="",
    [parameter(Position=7, Mandatory=$false, ParameterSetName="DeployRelease", HelpMessage="Apply filter per URI instead of name (default)")]
    [parameter(Position=6, Mandatory=$false, ParameterSetName="PromoteRelease", HelpMessage="Apply filter per URI instead of name (default)")]
    [switch]$FilterByURI,
    [parameter(Position=2, Mandatory=$true, ParameterSetName="PromoteRelease", HelpMessage="Specify the deployment id to promote")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="ManualSubmit", HelpMessage="Specify deployment id")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="DeleteDeployment", HelpMessage="Specify the deployment id to deleted the deployment")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="CancelDeployment", HelpMessage="Specify the deployment id to cancel the deployment")]
    [parameter(Position=2, Mandatory=$true, ParameterSetName="TryAgainDeployRelease", HelpMessage="Specify the deployment id to try again the deployment")]
    [string]$DeploymentId,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="ManualSubmit", HelpMessage="Specify the manual result (Proceed, Abort) to submit regarding manual step")]
    [ValidateSet("Proceed", "Abort")]
    [string]$ManualResult,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="PromoteRelease", HelpMessage="Ask to the script to make a promotion")]
    [switch]$Promote,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="ExistsRelease", HelpMessage="Ask to the script to check if exists a release version")]
    [switch]$Exists,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="DeleteRelease", HelpMessage="Ask to the script to delete a release version")]
    [switch]$Delete,
    [parameter(Position=8, Mandatory=$false, ParameterSetName="DeployRelease", HelpMessage="Let to define skip actions during the deployment")]
    [parameter(Position=4, Mandatory=$false, ParameterSetName="TryAgainDeployRelease", HelpMessage="Let to define skip actions during the deployment")]
    [parameter(Position=7, Mandatory=$false, ParameterSetName="PromoteRelease", HelpMessage="Let to define skip actions during the deployment")]
    [string[]]$SkipActions=@(),
    [parameter(Position=3, Mandatory=$true, ParameterSetName="DeleteDeployment", HelpMessage="Ask to the script to delete a deployment")]
    [switch]$DeleteDeployment,
    [parameter(Position=3, Mandatory=$true, ParameterSetName="CancelDeployment", HelpMessage="Ask to the script to cancel a deployment")]
    [switch]$CancelDeployment,
    [parameter(Mandatory=$false, HelpMessage="Return result in Json")]
    [switch]$Json
)

#$ErrorActionPreference = 'Stop'

function Invoke-RestSafe
{
<#
.SINOPSIS

The function Invoke-RestSafe call a rest method in safe manner

.DESCRIPTION

The function Invoke-RestSafe in case there is an exception, i.e. an HTTP status code not equals to 200, catch the response and return.
The function return an object with two properties: Response that contains the current response of request and StatusCode of request.

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$Uri,
        [parameter(Mandatory=$false)]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method='Get',
        [parameter(Mandatory=$false, HelpMessage="Body request in JSON format")]
        [object]$Body,
        [parameter(Mandatory=$false)]
        [string]$ContentType='application/json'
    )

    try {
        $result = Invoke-WebRequest -Uri $Uri -Body $Body -Headers $Script:header -Method $Method -ContentType $ContentType | ConvertFrom-Json
        return [PSCustomObject]@{
            Response = $result
            StatusCode = 200
        }
    }
    catch [System.Net.WebException] {
        #Write-Error ($_.Exception | Format-List -force | Out-String)
        #$_.Exception.Response | Get-Member -MemberType Properties

        if ($_.Exception.Status -eq 'ProtocolError') {
            $rs = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($rs)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();

            return [PSCustomObject]@{
                Response = ($responseBody | ConvertFrom-Json)
                StatusCode = $_.Exception.Response.StatusCode
            }
        }
        else {
            throw
        }
    }
    catch {
        throw
    }
}

function Output-Exception
{
    [cmdletbinding()]
    param (
        [object]$psException
    )

    $output = $psException.Exception | Format-List -Force | Out-String
    $result = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($result)
    $UsefulData = $reader.ReadToEnd();

    Write-Host "[*ERROR*] : `n$Output `n$Usefuldata "
}

function Output-Response
{
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [AllowNull()]
        [object]$responseResult,
        [parameter(Mandatory=$false)]
        [switch]$WriteError,
        [parameter(Mandatory=$false, HelpMessage="Return result in Json")]
        [switch]$Json
    )

    if ($responseResult -ne $null) {
        $out = $responseResult.Response
        if ($Json.IsPresent) {
            $out = ($out | ConvertTo-Json -Depth 10 | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }) # Escaping unicode characters
        }

        if ($WriteError.IsPresent) {
            Write-Error "`n$out"
        }
        else {
            Write-Host "`n[*Response*]:`n$out" -ForegroundColor DarkYellow
        }
    }
}

function Get-Project
{
<#
.SINOPSIS

The function Get-Project get project info

.DESCRIPTION

The function Get-Project get project info

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$projectIdOrSlug
    )

    Write-Host "Get project by '$projectIdOrSlug'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/projects/$projectIdOrSlug"

    Write-Verbose (@"
Project response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $Script:project = $result.Response
    }

    return $result
}

function Save-Release
{
<#
.SINOPSIS

The function Save-Release saves the release version per project

.DESCRIPTION

The function Save-Release saves the release version defined per project

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project,
        [parameter(Mandatory=$true)]
        [object]$release
    )

    Write-Host "Save release per project '$($project.Name)' by version '$($release.Version)'"

    $release.SelectedPackages = @()

    for ($i = 0; $i -lt $Script:packageSelections.Length; $i ++) {
        $selection = $Script:packageSelections[$i]
        $selectedVersion = ""

        if ("latest" -eq $selection.VersionType) {
            $selectedVersion = $selection.LatestVersion
        }
        elseif ("last" -eq $selection.VersionType) {
            $selectedVersion = $selection.LastReleaseVersion
        }
        elseif ("specific" -eq $selection.VersionType) {
            $selectedVersion = $selection.SpecificVersion
        }

        $release.SelectedPackages += @{
            StepName = $selection.StepName
            Version = $selectedVersion
        }
    }

    1 -eq $scope.channels.Items -and ($release.ChannelId = $Script:channels.Items[0].Id) > $null

    Write-Verbose (@"
Save release body request:
$($release | ConvertTo-Json -Depth 5)
"@)

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/releases?ignoreChannelRules=$($Script:options.ignoreChannelRules)" -Method Post -Body ($release | ConvertTo-Json -Depth 5)

    Write-Verbose (@"
Release response:
$($result | ConvertTo-Json -Depth 5)
"@)

    $Script:release = $result.Response
    return $result
}

function Test-Release
{
<#
.SINOPSIS

The function Test-Release try to retrieve a releave for given project

.DESCRIPTION

The function Test-Release try to retrieve a releave for given project

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project,
        [parameter(Mandatory=$true)]
        [string]$version
    )

    Write-Host "Test release per version '$version'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/projects/$($project.Id)/releases/$version"

    Write-Verbose (@"
Test release response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Delete-Release
{
<#
.SINOPSIS

The function Delete-Release deleted the release version per project

.DESCRIPTION

The function Delete-Release deleted the release version per project and any deployments associated

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$release
    )

    Write-Host "Delete release per Id = '$($release.Id)'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/releases/$($release.Id)" -Method Delete

    Write-Verbose (@"
Delete release '$($release.Id)' response:
$($result | ConvertTo-Json -Depth 5)
"@)
}

function Get-Deployment
{
<#
.SINOPSIS

The function Get-Deployment deletes a deployment

.DESCRIPTION

The function Get-Deployment deletes a deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$deploymentId
    )

    Write-Host "Get deployment per Id = '$deploymentId'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deployments/$deploymentId"

    Write-Verbose (@"
Get deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Set-DeploymentManualSubmit
{
<#
.SINOPSIS

The function Set-DeploymentManualSubmit set manual step

.DESCRIPTION

The function Set-DeploymentManualSubmit set manual step (Proceed, Abort) for required steps of given deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deployment,
        [parameter(Mandatory=$true)]
        [ValidateSet("Proceed", "Abort")]
        [string]$manualResult
    )

    Write-Host "Set manual approve per deployment Id = '$($deployment.Id)' ... "
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/interruptions?regarding=$($deployment.Id)"

    Write-Verbose (@"
Get interruption regarding response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $items = $result.Response.Items | ? { $_.IsPending }

        Write-Verbose (@"
Items pending:
$($items | ConvertTo-Json -Depth 5)
"@)

        $itemsResult = @{}

        if ($items) {
            $items | % {
                $item = $_
                $itemsResult.Add($item.Id, $null)

                Write-Verbose (@"
Interruption item:
$($item | ConvertTo-Json -Depth 5)
"@)

                Write-Host "  Get responsible ... "
                $itemResult = Invoke-RestSafe -Uri $($Script:OctopusURL + $item.Links.Responsible) -Method Put

                Write-Verbose (@"
Get responsible response:
$($itemResult | ConvertTo-Json -Depth 5)
"@)

                $itemsResult[$item.Id] = @{
                    StepAction = "Responsible"
                    Response = $itemResult
                }

                if ($result.StatusCode -eq 200) {
                    Write-Host "  Submit ... "
                    $approveBody = @{
                        Instructions = $null
                        Notes = "Automatic approve"
                        Result = $manualResult #"Proceed" or "Abort"
                    }

                    Write-Verbose (@"
Approve body request:
$($approveBody | ConvertTo-Json -Depth 5)
"@)

                    $itemResult = Invoke-RestSafe -Uri $($Script:OctopusURL + $item.Links.Submit) -Method Post -Body ($approveBody | ConvertTo-Json)

                    Write-Verbose (@"
Approve response:
$($itemResult | ConvertTo-Json -Depth 5)
"@)

                    $itemsResult[$item.Id] = @{
                        StepAction = "Submit"
                        Response = $itemResult
                    }
                }
            }

            return [PSCustomObject]@{
                Response = @{
                    OriginalResponse = $result.Response
                    Items = $itemsResult
                }
                StatusCode = $result.StatusCode
            }
        }
        else {
            Write-Host "No interruption items pending were found" -ForegroundColor Red
        }
    }

    return $result
}

function Get-Channels
{
<#
.SINOPSIS

The function Get-Channels get channel info per project

.DESCRIPTION

The function Get-Channels get channel info per project and a default one if it's a new release

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project
    )

    Write-Host "Get channels by '$($project.Name)'"
    $result = Invoke-RestSafe -Uri ($Script:OctopusURL + $project.Links.Channels)

    Write-Verbose (@"
Channels response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $channels = $result.Response
        $Script:channels = $channels

        if (("CreateRelease" -ne $Script:PSCmdlet.ParameterSetName) -and ($Script:ReleaseVersion -ne $null)) { # Edit release
            $releaseByVerionResult = $project | Get-ReleaseByVersion -version $Script:ReleaseVersion
            if ($releaseByVerionResult.StatusCode -eq 200) {
                return $Script:release.ProjectDeploymentProcessSnapshotId | Load-DeploymentProcess -release $Script:release
            }
            else {
                return $releaseByVerionResult
            }
        }
        else { # Create release
            $defaultChannel = $channels.Items | ? { $_.IsDefault }

            Write-Verbose (@"
Channel default:
$(if ($defaultChannel -ne $null) {
    $defaultChannel | ConvertTo-Json -Depth 5
    }
    else {
    "No default channel was found for project '$($project.Name)'"
    }
)
"@)

            $release = @{
                ProjectId = $project.Id
                ChannelId = $(if ($defaultChannel) { $defaultChannel.Id } else { $channels.Items[0].Id } )
            }

            Write-Verbose (@"
Release preparation:
$($release | ConvertTo-Json -Depth 5)
"@)

            $Script:release = $release

            $deploymentProcessResult = $project.DeploymentProcessId | Load-DeploymentProcess -release $Script:release
            return $deploymentProcessResult
        }
    }
    else {
        return $result
    }
}

function Get-ReleaseByVersion
{
<#
.SINOPSIS

The function Get-ReleaseByVersion get release info per project

.DESCRIPTION

The function Get-ReleaseByVersion get release info per project

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project,
        [parameter(Mandatory=$true)]
        [string]$version
    )

    Write-Host "Get release per project '$($project.Name)' by version '$version'"
    $result = Invoke-RestSafe -Uri "$($Script:octopusURL)/api/projects/$($project.Id)/releases/$version"

    Write-Verbose (@"
Release by Version response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $Script:release = $result.Response
        $Script:originalVersion = $result.Response.Version
        $Script:originalChannelId = $result.Response.ChannelId
    }

    return $result
}

function Load-DeploymentProcess
{
<#
.SINOPSIS

The function Load-DeploymentProcess load deployment process

.DESCRIPTION

The function Load-DeploymentProcess load deployment process and load releated template

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$processId,
        [parameter(Mandatory=$true)]
        [object]$release
    )

    Write-Host "Load deployment process by Id = '$processId'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deploymentprocesses/$processId"

    Write-Verbose (@"
Deployment process response:
$($result | ConvertTo-Json -Depth 8)
"@)

    if ($result.StatusCode -eq 200) {
        $templateResult = $result.Response | Load-Template -release $release
        return $templateResult
    }
    else {
        return $result
    }
}

function Load-Template
{
<#
.SINOPSIS

The function Load-Template load deployment template process

.DESCRIPTION

The function Load-Template load deployment template process

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deploymentProcess,
        [parameter(Mandatory=$true)]
        [object]$release
    )

    Write-Host "Load template ... "

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deploymentprocesses/$($deploymentprocess.Id)/template?channel=$($release.ChannelId)"

    Write-Verbose (@"
Deployment Template response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $template = $result.Response
        $Script:template = $template
        $release.Id -or $template.NextVersionIncrement -and ($release.Version = $template.NextVersionIncrement) > $null

        $existingSelections = @{}
        if ($release.SelectedPackages) {
            for ($k = 0; $k -lt $release.SelectedPackages.Length; $k++) {
                $existingSelections.Add($release.SelectedPackages[$k].StepName, $release.SelectedPackages[$k].Version)
            }
        }

        $selectionByFeed = @{}
        $Script:packageSelections = @();
        for($i = 0; $i -lt $template.Packages.Length; $i++) {
            $selection = @{
                StepName = $template.Packages[$i].StepName
                NuGetPackageId = $template.Packages[$i].NuGetPackageId
                NuGetFeedId = $template.Packages[$i].NuGetFeedId
                NuGetFeedName = $template.Packages[$i].NuGetFeedName
                LatestVersion = ""
                IsResolvable = $template.Packages[$i].IsResolvable
                LastReleaseVersion = $template.Packages[$i].VersionSelectedLastRelease
                isLastReleaseVersionValid = !1
            }
            $selection.Add("SpecificVersion", $(
                if ($existingSelections.ContainsKey($selection.StepName)) {
                    $existingSelections[$selection.StepName]
                }
                else {
                    ""
                } ))
            $selection.Add("VersionType", $(
                if ($selection.SpecificVersion) {
                    "specific"
                }
                elseif ($selection.IsResolvable) {
                    "latest"
                }
                elseif ($selection.LastReleaseVersion) {
                    "last"
                }
                else {
                    "specific"
                } ))
            $Script:packageSelections += $selection
            $selection.IsResolvable -and ($selectionByFeed.ContainsKey($selection.NuGetFeedId) -or ($selectionByFeed[$selection.NuGetFeedId] = @())) > $null
            $selectionByFeed[$selection.NuGetFeedId] += $selection
        }

        $Script:release = $release

        Write-Verbose (@"
Load template existing selections:
$($existingSelections | ConvertTo-Json -Depth 5)
"@)

        Write-Verbose (@"
Load template package selections:
$($Script:packageSelections | ConvertTo-Json -Depth 5)
"@)

        Write-Verbose (@"
Load template selection by Feed:
$($selectionByFeed | ConvertTo-Json -Depth 5)
"@)

        $versionsResult = $selectionByFeed | Load-Versions
        return $versionsResult
    }
    else {
        return $result
    }
}

function Load-Versions
{
<#
.SINOPSIS

The function Load-Versions load versions of packages to release

.DESCRIPTION

The function Load-Versions load versions of packages to release based on feed

#>
    [cmdletbinding()]
    param(
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$selectionsByFeed
    )

    Write-Host "Load versions ... "

    $Script:feedLoadingError = $null

    if ($selectionsByFeed) {
        $feedsResult = @{}

        $selectionsByFeed.Keys | % {
            $feed = $_
            $feedsResult.Add($feed, $null)

        Write-Verbose (@"
Feed item: $feed
"@)

            $feedResult = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/feeds/$feed"

        Write-Verbose (@"
Feed response:
$($feedResult | ConvertTo-Json -Depth 5)
"@)

            $feedsResult[$feed] = @{
                StepAction = "Feed search"
                Response = $feedResult
            }

            if ($feedResult.StatusCode -eq 200) {
                $selections = $selectionsByFeed[$feed]

                $selections | % {
                    $filters = Get-ChannelFilters $_.StepName

                    $selection = Check-ForRuleSatisfaction $_ $filters
                    $searchOptions = @()
                    $filters.GetEnumerator() | % { $searchOptions += "$($_.Key)=$($_.Value)" }
                    $searchOptions += ("packageId=$($selection.NuGetPackageId)")
                    $searchOptions += ("partialMatch=$(!1)")
                    $searchOptions += ("includeMultipleVersions=$(!1)")
                    $searchOptions += ("includePreRelease=$(!0)")
                    $searchOptions += ("includeNotes=$(!1)")
                    $searchOptions += ("take=1")

                    $searchOptionsQS = $searchOptions -join "&"

                    $searchResult = Invoke-RestSafe -Uri "$($Script:OctopusURL + $feedResult.Response.Links.Packages)?$searchOptionsQS"

            Write-Verbose (@"
Search feed response:
$($searchResult | ConvertTo-Json -Depth 5)
"@)

                    if ($searchResult.StatusCode -eq 200) {
                        if ($searchResult.Response -is [System.Array]) {
                            $pkg = $searchResult.Response[0]
                            $selection.LatestVersion = $pkg.Version
                            if ($Script:release.Id) {
                                Set-VersionSatisfaction $selection $selection.SpecificVersion
                            }
                            else {
                                packageVersionChanged $selection $pkg.Version
                            }
                        }
                        else {
                            $selection.IsResolvable = !1
                            $selection.VersionType = "specific"
                            $selection.ErrorLoadingLatest = ("Could not find the latest version of package " + $selection.NuGetPackageId + " in this feed.")
                            Set-VersionSatisfaction $selection $selection.SpecificVersion
                        }
                    }
                    else {
                        $Script:feedLoadingError -or ($Script:feedLoadingError = $searchResult.Response)
                    }
                }
            }
        }

        return [PSCustomObject]@{
            Response = @{
                OriginalResponse = $selectionsByFeed
                Items = $feedsResult
            }
            StatusCode = $result.StatusCode
        }
    }
    else {
        return [PSCustomObject]@{
            ErrorMessage = "None -selectionsByFeed available"
            StatusCode = 404
        }
    }
}

function Get-ChannelFilters
{
<#
.SINOPSIS

The function Get-ChannelFilters return channels filtered

.DESCRIPTION

The function Get-ChannelFilters return channels filtered per deployment action name

#>
    [cmdletbinding()]
    param (
        [string]$deploymentActionName
    )

    $filters = @{}
    if (!$Script:release.ChannelId) {
        return $filters
    }

    $applicableRules = $Script:channels.Items | ? {
        $_.Id -eq $Script:release.ChannelId
    }
    $applicableRules = $applicableRules[0].Rules | % {
        (0 -eq $_.Actions.Length) -or $_.Actions -contains $deploymentActionName
    }

    if ($applicableRules) {
        $applicableRules = $applicableRules[0]

        if ($applicableRules.VersionRange) {
            $filters.Add("versionRange", $applicableRules.VersionRange)
        }
        if ($applicableRules.Tag) {
            $filters.Add("preReleaseTag", $applicableRules.Tag)
        }
    }

    Write-Verbose (@"
Applicable rules for Channel '$($Script:release.ChannelId)' and action name '$deploymentActionName':
$($applicableRules | ConvertTo-Json -Depth 5)
"@)

    Write-Verbose (@"
Channel filters:
$($filters | ConvertTo-Json -Depth 5)
"@)

    return $filters
}

function Set-VersionSatisfaction
{
<#
.SINOPSIS

The function Set-VersionSatisfaction verify rules per package and version

.DESCRIPTION

The function Set-VersionSatisfaction verify rules per package and version

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [object]$pkg,
        [parameter(Mandatory=$true)]
        [object]$version
    )

    $filters = Get-ChannelFilters $pkg.StepName

    $ruleTestOptions = @()

    $ruleTestOptions += "version=$version"
    if ($filters.ContainsKey("versionRange")) {
        $ruleTestOptions += "versionRange=$($filters["versionRange"])"
    }
    if ($filters.ContainsKey("preReleaseTag")) {
        $ruleTestOptions+= "preReleaseTag=$($filters["preReleaseTag"])"
    }

    $ruleTestQS = $ruleTestOptions -join "&"

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/channels/rule-test?$ruleTestQS"

    Write-Verbose (@"
Set Version satisfaction rule for version '$version' response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $ruleTest = $result.Response
        $pkg.isSelectedVersionValid = -1 -ne [System.Array]::IndexOf($ruleTest.Errors, "Invalid Version Number") -or ($ruleTest.SatisfiesVersionRange -and $ruleTest.SatisfiesPreReleaseTag)
        $position = $Script:violatedPackages.indexOf($pkg.StepName)
        if ($pkg.isSelectedVersionValid -and -1 -ne $position) {
            $Script:violatedPackages.RemoveRange($position, 1)
        }
        else {
            $pkg.isSelectedVersionValid -or (-1 -ne $position) -or ($Script:violatedPackages += $pkg.StepName) > $null
        }

        Write-Verbose (@"
Violated packages:
$($Script:violatedPackages | ConvertTo-Json -Depth 5)
"@)
}
    else {
        Write-Error ($result.Response | ConvertTo-Json -Depth 5)
    }
}

function Check-ForRuleSatisfaction
{
<#
.SINOPSIS

The function Check-ForRuleSatisfaction is used by Load-Versions to enforce rules

.DESCRIPTION

The function Check-ForRuleSatisfaction is used by Load-Versions to enforce rules

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true)]
        [object]$selection,
        [parameter(Mandatory=$true)]
        [object]$filters
    )

    if ($selection.LastReleaseVersion) {
        $ruleTestOptions = @()

        $ruleTestOptions += "version=$($selection.LastReleaseVersion)"
        if ($filters.ContainsKey("versionRange")) {
            $ruleTestOptions += "versionRange=$($filters["versionRange"])"
        }
        if ($filters.ContainsKey("preReleaseTag")) {
            $ruleTestOptions+= "preReleaseTag=$($filters["preReleaseTag"])"
        }

        $ruleTestQS = $ruleTestOptions -join "&"

        $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/channels/rule-test?$ruleTestQS"

        Write-Verbose (@"
Check rule satisfaction for version '$($selection.LastReleaseVersion)':
$($result | ConvertTo-Json -Depth 5)
"@)

        if ($result.StatusCode -eq 200) {
            $ruleTest = $result.Response
            $selection.isLastReleaseVersionValid = $ruleTest.SatisfiesVersionRange -and $ruleTest.SatisfiesPreReleaseTag
        }
        else {
            Write-Error ($result.Response | ConvertTo-Json -Depth 5)
        }
    }
    else {
        $selection.isLastReleaseVersionValid = !1
    }

    return $selection
}

function packageVersionChanged
{
<#
.SINOPSIS

The function packageVersionChanged is used by Load-Versions

.DESCRIPTION

The function packageVersionChanged is used by Load-Versions

#>
    [cmdletbinding()]
    param (
        [object]$pkg,
        [object]$version
    )

    Write-Verbose ("Package '{0}' version changed " -f $pkg.NuGetPackageId)
    $Script:template.VersioningPackageStepName -and $Script:template.VersioningPackageStepName -eq $pkg.StepName -and ($Script:release.Version = $version) > $null
    Set-VersionSatisfaction $pkg $version
}

function Initialize-Release
{
<#
.SINOPSIS

The function Initialize-Release initialize release

.DESCRIPTION

The function Initialize-Release initialize release getting info about given project and related dependecies

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$projectId
    )

    $projectResult = $projectId | Get-Project
    $responseResult = $projectResult
    if ($projectResult.StatusCode -eq 200) {
        $channelsResult = $projectResult.Response | Get-Channels
        $responseResult = $channelsResult
    }

    return $responseResult
}

function Get-Environment
{
<#
.SINOPSIS

The function Get-Environment return the environment info

.DESCRIPTION

The function Get-Environment return the environment info given Environment name

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$environmentName
    )

    Write-Host "Get environment by '$environmentName'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/environments/all"

    Write-Verbose (@"
Enviroments response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        $environment = $result.Response | ? { $_.Name -eq $environmentName }

        if ($environment -eq $null) {
            Throw "No environment was found equals to '$environmentName'"
        }

        Write-Verbose (@"
Enviroment selected:
$($environment | ConvertTo-Json -Depth 5)
"@)

        $Script:environment = $environment

        return [PSCustomObject]@{
            StatusCode = 200
            Response = $environment
        }
    }
    else {
        return $result
    }
}

function Get-Machines
{
<#
.SINOPSIS

The function Get-Machines return the machine IDs per environment filtered

.DESCRIPTION

The function Get-Machines return the machine IDs per environment filtered by name or URI

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$environment,
        [parameter(Mandatory=$false)]
        [string[]]$filters="",
        [parameter(Mandatory=$false)]
        [switch]$filterByURI
    )

    Write-Host "Get machines by environment '$($environment.Name)'"
    $result = Invoke-RestSafe -Uri ($Script:OctopusURL + $environment.Links.Machines)

    Write-Verbose (@"
Machines response:
$($result | ConvertTo-Json -Depth 5)
"@)

    if ($result.StatusCode -eq 200) {
        ## Filtering machines for each filter declared on $filter
        ## If you want to filter by name or URI, comment one of the lines inside the foreach loop
        $machineIDs = @()

        if ($FilterByURI.IsPresent) {
            Write-Verbose "Apply filter by Machine URI"
        }

        $items = $result.Response.Items
        foreach($f in $filters) {
            if (!$filterByURI.IsPresent) {
                $ID = ($items | ? { $_.Name -like $f}).Id # Use to filter by machine name on Octopus
            }
            else {
                $ID = ($tems | ? { $_.Uri -like $f}).Id # Use to filter by URI
            }

            if ($ID -eq $null) {
                Write-Host "No machines was found with the pattern '$f' on onvironment '$($environment.Name)'" -ForegroundColor Red
            }
            else {
                $machineIDs += $ID
            }
        }

        if ($machineIDs -eq $null) {
            #If there are not IDs on $machineIDs and you just proceed, it'll deploy to all machines by default
            #to prevent this scenario, we are adding a Throw here to stop the entire script
            Throw "No machines where found with the pattern/s '$Filters' on '$($environment.name)'"
        }

        Write-Verbose (@"
MachineIDs selected:
$($machineIDs | ConvertTo-Json -Depth 5)
"@)

        $Script:machineIDs = $machineIDs

        return [PSCustomObject]@{
            StatusCode = 200
            Response = $machineIDs
        }
    }
    else {
        return $result
    }
}

function Deploy-Release
{
<#
.SINOPSIS

The function Deploy-Release trigger Octopus to deploy a release

.DESCRIPTION

The function Deploy-Release trigger Octopus to deploy a release to specified environment/machineIDs

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$release,
        [parameter(Mandatory=$true)]
        [object]$environment,
        [parameter(Mandatory=$true)]
        [string[]]$machineIDs,
        [parameter(Mandatory=$false)]
        [string[]]$skipActions
    )

    Write-Host "Deploy release per release Id = '$($release.Id)'"

    $deploymentBody = @{
        ReleaseId = $release.Id
        EnvironmentId = $environment.Id
        SpecificMachineIds = $machineIDs
        SkipActions = $skipActions
    }

    Write-Verbose (@"
Deployment body request into environment '$environmentName' on machines '$machineIDs':
$($deploymentBody | ConvertTo-Json -Depth 5)
"@)

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deployments" -Method Post -Body ($deploymentBody | ConvertTo-Json)

    Write-Verbose (@"
Deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function TryAgain-DeployRelease
{
<#
.SINOPSIS

The function TryAgain-DeployRelease trigger Octopus to try again to deploy a release

.DESCRIPTION

The function TryAgain-DeployRelease trigger Octopus to try again to deploy a release.

Note:
currently not copy all definitios from based deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deployment,
        [parameter(Mandatory=$false)]
        [string[]]$skipActions
    )

    Write-Host "Try again deploy release per deployment Id = '$($deployment.Id)'"

    $deploymentBody = @{
        ReleaseId = $deployment.ReleaseId
        EnvironmentId = $deployment.EnvironmentId
        SpecificMachineIds = $deployment.SpecificMachineIds
        SkipActions = if ($skipActions -and $skipActions.Length -gt 0) { $skipActions } else  { $deployment.skipActions }
    }

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deployments" -Method Post -Body ($deploymentBody | ConvertTo-Json)

    Write-Verbose (@"
Try again deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Promote-Release
{
<#
.SINOPSIS

The function Promote-Release trigger Octopus to promote a release

.DESCRIPTION

The function Promote-Release trigger Octopus to promote a release

Note:
currently not copy all definitios from based deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deployment,
        [parameter(Mandatory=$true)]
        [object]$environment,
        [parameter(Mandatory=$true)]
        [string[]]$machineIDs,
        [parameter(Mandatory=$false)]
        [string[]]$skipActions
    )

    Write-Host "Promote release per deployment Id = '$($deployment.Id)' into enviroment '$($environment.Name)'"

    $deploymentBody = @{
        ReleaseId = $deployment.ReleaseId
        EnvironmentId = $deployment.EnvironmentId
        SpecificMachineIds = $deployment.SpecificMachineIds
        SkipActions = if ($skipActions -and $skipActions.Length -gt 0) { $skipActions } else  { $deployment.skipActions }
    }

    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deployments" -Method Post -Body ($deploymentBody | ConvertTo-Json)

    Write-Verbose (@"
Promote deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Delete-Deployment
{
<#
.SINOPSIS

The function Delete-Deployment deletes a deployment

.DESCRIPTION

The function Delete-Deployment deletes a deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deployment
    )

    Write-Host "Delete deployment per Id = '$($deployment.Id)'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/deployments/$($deployment.Id)" -Method Delete

    Write-Verbose (@"
Delete deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Cancel-Deployment
{
<#
.SINOPSIS

The function Cancel-Deployment cancels a deployment

.DESCRIPTION

The function Cancel-Deployment cancels a deployment

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$deployment
    )

    Write-Host "Cancel deployment per Id = '$($deployment.Id)'"
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL + $deployment.Links.Task)/cancel" -Method Post

    Write-Verbose (@"
Cancel deployment response:
$($result | ConvertTo-Json -Depth 5)
"@)

    return $result
}

function Get-ProjectProgress
{
<#
.SINOPSIS

The function Get-ProjectProgress gets the project progress

.DESCRIPTION

The function Get-ProjectProgress gets the project progress

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project
    )

    Write-Host "Get project '$($project.Id)' progress ... "
    $result = Invoke-RestSafe -Uri ($Script:OctopusURL + $project.Links.Progression)

    Write-Verbose (@"
Get project progress response:
$($result | ConvertTo-Json -Depth 8)
"@)

    return $result
}

function Get-ProjectReleases
{
<#
.SINOPSIS

The function Get-ProjectReleases gets the project releases

.DESCRIPTION

The function Get-ProjectReleases gets the project releases
#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [object]$project
    )

    Write-Host "Get project '$($project.Id)' releases ... "
    $result = Invoke-RestSafe -Uri "$($Script:OctopusURL)/api/projects/$($project.Id)/releases"

    Write-Verbose (@"
Get project releases response:
$($result | ConvertTo-Json -Depth 8)
"@)

    return $result
}

$header = @{ "X-Octopus-ApiKey" = $ApiKey }
$projectId = $ProjectName
$project = $null

$environment = $null
$machineIDs = @()
$deploymentProcess = $null
$template = $null
$packageSelections = @()
$violatedPackages = @()
$options = @{
    ignoreChannelRules = !1
}
$channels = @()
$release = @{}
$originalVersion = $null
$originalChannelId = $null
$feedLoadingError = $null

Write-Verbose "ParameterSetName: $($PSCmdlet.ParameterSetName)"

switch ($PSCmdlet.ParameterSetName) {
    "CreateRelease" {
        Write-Host "Create release task ... "

        $initializeResult = $projectId | Initialize-Release
        $responseResult = $initializeResult

        if ($initializeResult.StatusCode -eq 200) {
            if ($ReleaseVersion -ne $null) {
                $release.Version = $ReleaseVersion
            }
            $saveRelaseResult =  $project | Save-Release -release $release
            $responseResult = $saveRelaseResult
        }
        break
    }

    "ExistsRelease" {
        Write-Host "Exists release task ... "

        $projectResult = $projectId | Get-Project
        $responseResult = $projectResult
        if ($projectResult.StatusCode -eq 200) {
            $responseResult = $projectResult.Response | Test-Release -version $ReleaseVersion
        }

        break
    }

    "DeleteRelease" {
        Write-Host "Delete release task ... "

        $projectResult = $projectId | Get-Project
        $responseResult = $projectResult
        if ($projectResult.StatusCode -eq 200) {
            $testReleaseResult = $projectResult.Response | Test-Release -version $ReleaseVersion
            $responseResult = $testReleaseResult
            if ($testReleaseResult.StatusCode -eq 200) {
                $responseResult = $testReleaseResult.Response | Delete-Release
            }
        }

        break;
    }

    "DeployRelease" {
        Write-Host "Deploy release task ... "

        $environmentResult = $EnvironmentName | Get-Environment
        $responseResult = $environmentResult
        if ($environmentResult.StatusCode -eq 200) {
            $machinesResult = $environmentResult.Response | Get-Machines -filters $Filter -filterByURI:$FilterByURI
            $responseResult = $machinesResult
            if ($machinesResult.StatusCode -eq 200) {
                $initializeResult = $projectId | Initialize-Release
                $responseResult = $initializeResult
                if ($initializeResult.StatusCode -eq 200) {
                    $responseResult = $release | Deploy-Release -environment $environment -machineIDs $machineIDs -skipActions $SkipActions
                }
            }
        }

        break
    }

    "TryAgainDeployRelease" {
        Write-Host "Try again deploy release task ... "

        $deploymentResult = $DeploymentId | Get-Deployment
        $responseResult = $deploymentResult
        if ($deploymentResult.StatusCode -eq 200) {
            $responseResult = $deploymentResult.Response | TryAgain-DeployRelease -skipActions $SkipActions
        }

        break
    }

    "PromoteRelease" {
        Write-Host "Promote release task ... "

        $EnvironmentName | Get-Environment
        $environment | Get-Machines -filters $Filter -filterByURI:$FilterByURI

        $environmentResult = $EnvironmentName | Get-Environment
        $responseResult = $environmentResult
        if ($environmentResult.StatusCode -eq 200) {
            $machinesResult = $environmentResult.Response | Get-Machines -filters $Filter -filterByURI:$FilterByURI
            $responseResult = $machinesResult
            if ($machinesResult.StatusCode -eq 200) {
                $deploymentResult = $DeploymentId | Get-Deployment
                $responseResult = $deploymentResult
                if ($deploymentResult.StatusCode -eq 200) {
                    $responseResult = $deploymentResult.Response | Promote-Release -environment $environment -machineIDs $machineIDs -skipActions $SkipActions
                }
            }
        }

        break
    }

    "ManualSubmit" {
        Write-Host "Manual submit task ... "
        $deploymentResult = $DeploymentId | Get-Deployment
        $responseResult = $deploymentResult
        if ($deploymentResult.StatusCode -eq 200) {
            $responseResult = $deploymentResult.Response | Set-DeploymentManualSubmit -manualResult $ManualResult
        }

        break
    }

    "DeleteDeployment" {
        Write-Host "Delete deployment task ... "

        $deploymentResult = $DeploymentId | Get-Deployment
        $responseResult = $deploymentResult
        if ($deploymentResult.StatusCode -eq 200) {
            $responseResult = $deploymentResult.Response | Delete-Deployment
        }

        break
    }

    "CancelDeployment" {
        Write-Host "Cancel deployment task ... "

        $deploymentResult = $DeploymentId | Get-Deployment
        $responseResult = $deploymentResult
        if ($deploymentResult.StatusCode -eq 200) {
            $responseResult = $deploymentResult.Response | Cancel-Deployment
        }

        break
    }
}

Output-Response -responseResult $responseResult -Json:$Json #-WriteError #-ErrorAction SilentlyContinue
