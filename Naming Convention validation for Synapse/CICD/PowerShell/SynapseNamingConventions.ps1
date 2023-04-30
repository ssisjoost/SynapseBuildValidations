# Code coming soon
Param(
   [Parameter(Mandatory=$true,
   HelpMessage="Name of your workspace to ignore the default Linked Services that cannot be renamed.")]
   [ValidateNotNullOrEmpty()]
   [Alias("SynapseWorkspaceName","WorkspaceName")]
   [string]
   $SynapseDevWorkspaceName,

   [Parameter(Mandatory=$true,
   HelpMessage="Path that points to the rootfolder of the Synapse artifact. It should have subfolders like linkedService and pipeline.")]
   [ValidateNotNullOrEmpty()]
   [Alias("ArtifactFolder","ArtifactDirectory")]
   [string]
   $ArtifactPath,

   [Parameter(Mandatory=$true,
   HelpMessage="Path that points to the JSON file containing the naming conventions.")]
   [ValidateNotNullOrEmpty()]
   [Alias("NamingConventionFilePath","NamingConventionJsonFilePath")]
   [string]
   $NamingConventionPath
)

$ErrorActionPreference = "Stop"

exit 1
