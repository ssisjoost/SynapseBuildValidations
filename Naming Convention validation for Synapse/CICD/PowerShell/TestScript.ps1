# Test script for local testing in PowerShell, PowerShell ISE or Visual Studio Code
# Download your Synapse files from your repository and test the script localy to save time.
Clear-Host

$MyParameters = @{
    "-SynapseDevWorkspaceName" = "SynapseWorkspaceName"
    "-ArtifactPath"    = "C:\Users\XYZ\Documents\Synapse"
    "-NamingConventionPath"      = "C:\Users\XYZ\Documents\GitHub\SynapseBuildValidations\Naming Convention validation for Synapse\CICD\JSON\NamingConvention.json"
}

& "$PSScriptRoot\SynapseNamingConventions.ps1" @MyParameters