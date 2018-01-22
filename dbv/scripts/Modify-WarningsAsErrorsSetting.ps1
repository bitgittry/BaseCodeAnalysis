$FileExtension = ".csproj"
$TreatWarningsAsErrors = "false"
	
# Determine if path is real
function TestPath($FolderPath)  
{ 
    $FileExists = Test-Path $FolderPath 
    If ($FileExists -eq $True)  
    { 
        Return $true 
    } 
    Else  
    { 
        Return $false 
    } 
}

# Change the TreatWarningsAsErrors Setting in csproj to true/false as requested
function ChangeTreatWarningsAsErrorsSettingTo
{
	param (
		[string]$XmlFilePath,
		[string]$IsError
	)
	
	process {
	
		$xml=New-Object System.Xml.XmlDocument
		
		Write-Host $XmlFilePath
		$xml.load($XmlFilePath)

		$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
		$ns.AddNamespace("ns", $xml.DocumentElement.NamespaceURI)

		$nodes = $xml.SelectNodes('//ns:TreatWarningsAsErrors', $ns)

		foreach($node in $nodes) 
		{
			$node.InnerText = $IsError
		}

		$xml.Save($XmlFilePath)
	}
}

$FolderPath = Join-Path $PSScriptRoot '..\bit8_gaming_solution'

$Result = (TestPath($FolderPath)); 
	
If ($Result) 
{ 
    $Dir = get-childitem $FolderPath -recurse 
    $List = $Dir | where {$_.extension -eq $FileExtension} 
} 
else 
{ 
    "Folder path is incorrect." 
} 

foreach($element in $List) {

	$XMLPath = Join-Path $element.Directory $element.Name
	ChangeTreatWarningsAsErrorsSettingTo -XmlFilePath $XMLPath -IsError $TreatWarningsAsErrors
}




	

