<#
    .SYNOPSIS
    This script checks the naming conventions of a Synapse Workspace.
    You can adjust the settings and naming conventions in the JSON and
    pass the location of the JSON and the workspace as parameters to
    this script. No adjustments within this script are necessary.
    .PARAMETER SynapseDevWorkspaceName
    Name of the Synapse Workspace in development to ignore the default
    LinkedServices that cannot be adjusted or deleted.
    .PARAMETER ArtifactPath
    Path that points to the rootfolder of the Synapse artifact. It
    should have subfolders like linkedService and pipeline.
    .PARAMETER NamingConventionPath
    Path that points to the JSON file containing the naming conventions.
    .EXAMPLE
    SynapseNamingConventions.ps1 -SynapseDevWorkspaceName MySynapseDev `
                                 -ArtifactPath $(System.DefaultWorkingDirectory)\Synapse `
                                 -NamingConventionPath $(System.DefaultWorkingDirectory)\CICD\JSON\NamingConvention.json
#>
Param(
   [Parameter(Mandatory=$true,
   HelpMessage="Name of your development workspace to ignore the default Linked Services that cannot be renamed.")]
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

#####################################################
# Variables for counting errors with initual value 0
#####################################################
[int]$Script:pipelineErrorCount = 0
[int]$Script:pipelineSuccessCount = 0
[int]$Script:activityErrorCount = 0
[int]$Script:activitySuccessCount = 0
[int]$Script:linkedServiceErrorCount = 0
[int]$Script:linkedServiceSuccessCount = 0
[int]$Script:datasetErrorCount = 0
[int]$Script:datasetSuccessCount = 0
[int]$Script:notebookErrorCount = 0
[int]$Script:notebookSuccessCount = 0
[int]$Script:triggerErrorCount = 0
[int]$Script:triggerSuccessCount = 0
[int]$Script:dataflowErrorCount = 0
[int]$Script:dataflowSuccessCount = 0
[int]$Script:sqlScriptErrorCount = 0
[int]$Script:sqlScriptSuccessCount = 0
[int]$Script:kqlScriptErrorCount = 0
[int]$Script:kqlScriptSuccessCount = 0
[int]$Script:invalidPostfixErrorCount = 0
[int]$Script:invalidPostfixSuccessCount = 0

#####################################################
# Check parameters and stop on errors
#####################################################
$ErrorActionPreference = "Stop"

# Check if Synapse Artifact path exists
if (-not (Test-Path -Path $ArtifactPath))
{
    Write-Error "Supplied Artifact Path does not exist: $ArtifactPath"
}
# Check if there is at least a LinkedService subfolder
elseif (-not (Test-Path -Path (Join-Path -Path $ArtifactPath -ChildPath "linkedService")))
{
    Write-Error "Supplied Artifact Path exists, but does not contain a subfolder 'linkedService'. This indicates that the default Linked Services do not exist."
}

# Check Naming Convention path and load content into memory
[PSObject]$Script:namingConvention = $null
# Check if naming convention path exists
if (Test-Path $NamingConventionPath)
{
    # Check if naming convention file can be read as a JSON
    # PowerShell 5 does not yet have Test-Json and therefor
    # uses the the Try-Catch method. You can remove the
    # try-catch code and replace the two isValidJson lines
    # with the following code
    #$isValidJson = Get-Content $NamingConventionPath -Raw | Test-Json
    try {
        # Try to load read file as a JSON object
        $Script:namingConvention = Get-Content $NamingConventionPath | Out-String | ConvertFrom-Json
        # If succesful the the JSON is valid
        $isValidJson = $true;
    } catch {
        # If an error occured then the JSON is not valid
        $isValidJson = $false;
    }
    # Chech the value of the isValidJson and write an error
    if(-not $isValidJson)
    {
        Write-Error "Naming Convention Path doesn't contain valid JSON!"
    }
}
else
{
    # Test-Path failed, path doesn't contain that file
    Write-Error "Naming Convention Path doesn't exists! $($NamingConventionPath)"
}

# Errors below will not stop the script to make sure
# you will see all names that are not valid.
$ErrorActionPreference = "Continue"

#####################################################
# Functions
#####################################################
function HasProperty
{
    <#
        .SYNOPSIS
        Check if the JSON object contains a certain property
        .PARAMETER PropertyName
        Name of the property you want to check for existence
        .PARAMETER JsonObject
        A JSON object in which you want to check
        .EXAMPLE
        HasProperty -JsonObject $pipelineContent.properties -PropertyName "folder"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [PSObject]$JsonObject
    )

    # Check if the JSON object contains a property with the specific name
    return $JsonObject.PSObject.Properties.Name -contains $PropertyName
}


function LoopActivities
{
    <#
        .SYNOPSIS
        Self-referencing function that loops through all (sub)activities
        .PARAMETER LevelName
        Name of the level you are checking (hardcoded then name of the pipeline)
        .PARAMETER LevelNumber
        A self-raising level counter (hardcoded then 1)
        .PARAMETER Activities
        A JSON object containing activities
        .EXAMPLE
        LoopActivities -LevelName $pipeline.BaseName -LevelNumber 1 -Activities $pipelineContent.properties.activities
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LevelName,

        [Parameter(Mandatory = $true)]
        [int]$LevelNumber,

        [Parameter(Mandatory = $true)]
        [PSObject]$Activities
    )

    # Retrieve all checks from naming covention config and then filter on Postfixes to get its validate value
    [bool]$postfixCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "CopyPostfixes" }).validate

    # Check if you want to check for activities that end with _copy**
    if ($postfixCheck)
    {
        # Assign all resources to the resources variable while filtering on the _copy** postfixes
        $incorrectActivities = $Activities | Where-Object { $_.name -match '_copy([1-9][0-9]?)$'} | Select-Object -Property name, type

        # Count the errors by counting the error collection
        $Script:invalidPostfixErrorCount += ($incorrectActivities | Measure-Object).Count
        # Count total number of activities minus the errors
        $Script:invalidPostfixSuccessCount += ($Activities | Measure-Object).Count - ($incorrectActivities | Measure-Object).Count

        # Loop through all activities with an invalid _copy** postfix
        foreach ($incorrectActivity in $incorrectActivities)
        {
            # Write all 'errors' to screen
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Activity [$($incorrectActivity.name)] has a _copy postfix"
        }
    }

    # Loop through the activities
    foreach ($activity in $Activities)
    {
        # Check the prefix of the activity
        CheckActivityPrefix -ActivityName $activity.name `
                            -ActivityType $activity.type `
                            -LevelNumber $LevelNumber

        # Switch based on activities which possibly contain underlying activities
        # and then call this same function with the sub properties as a parameter
        switch ($activity.type)
        {
            # Foreach and Until have activities property with sub properties
            {"ForEach", "Until" -contains $_}
            {
                LoopActivities -LevelName ($LevelName + "\" + $activity.name) `
                                -LevelNumber ($LevelNumber + 1) `
                                -Activities $activity.typeProperties.activities
            }
            # Switch contains defaultActivities and one or more cases with sub properties
            "Switch"
            {
                LoopActivities -LevelName ($LevelName + "\" + $activity.name + "\Default") `
                                -LevelNumber ($LevelNumber + 1) `
                                -Activities $activity.typeProperties.defaultActivities
                # Loop through all cases within the Switch
                foreach ($case in $activity.cases) {
                    LoopActivities -LevelName ($LevelName + "\" + $activity.name + "\" + $case.value) `
                                    -LevelNumber ($LevelNumber + 1) `
                                    -Activities $case.activities
                }
            }
            # If has a true and false property with sub properties
            "IfCondition"
            {
                # True activities
                if (HasProperty -JsonObject $activity.typeProperties -PropertyName "ifTrueActivities") {
                    LoopActivities -LevelName ($LevelName + "\" + $activity.name + "\True") `
                                    -LevelNumber ($LevelNumber + 1) `
                                    -Activities $activity.typeProperties.ifTrueActivities
                }
                # False activities
                if (HasProperty -JsonObject $activity.typeProperties -PropertyName "ifFalseActivities") {
                    LoopActivities -LevelName ($LevelName + "\" + $activity.name + "\False") `
                                    -LevelNumber ($LevelNumber + 1) `
                                    -Activities $activity.typeProperties.ifFalseActivities
                }
            }
        }
    }
}


function CheckActivityPrefix
{
    <#
        .SYNOPSIS
        Function that checks the prefix and writes and counts the result
        .PARAMETER ActivityName
        Name of the activity you want to check
        .PARAMETER ActivityType
        The activity type to determine the prefix
        .PARAMETER LevelNumber
        The level number of the activity
        .EXAMPLE
        CheckActivityPrefix -ActivityName $Activity.name -ActivityType $Activity.type -LevelNumber 2
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ActivityName,

        [Parameter(Mandatory = $true)]
        [string]$ActivityType,

        [Parameter(Mandatory = $true)]
        [int]$LevelNumber
    )

    # Determine the indentation level based on the LevelNumber parameter
    # First level has no indentation and each successive level has 2 spaces
    [string]$spaces= '  ' * ($LevelNumber - 1)

    # Retrieve specific activity prefix from naming convention object
    $activityConvention = $Script:namingConvention.Activities | Where-Object { $_.Type -eq $ActivityType }

    # Check if there is a prefix available
    if (!$activityConvention)
    {
        # No prefix found, so unknown activity type that is not yet in the JSON
        Write-Error "##vso[task.LogIssue type=error;]$($spaces)$([char]10007) Activity [$($ActivityName)] has an unknown activity type [$($ActivityType)]"
        $Script:activityErrorCount++
    }
    # Check if the used prefix is correct
    elseif ($ActivityName.StartsWith($activityConvention.prefix + $Script:namingSeparator))
    {
        # Activity has the correct prefix
        Write-Output "$($spaces)$([char]10003) Activity [$($ActivityName)] has the correct prefix [$($activityConvention.prefix)$($Script:namingSeparator)] for a [$($ActivityType)]"
        $Script:activitySuccessCount++
    }
    else
    {
        # Activity has an incorrect prefix
        Write-Error "##vso[task.LogIssue type=error;]$($spaces)$([char]10007) Activity [$($ActivityName)] has an incorrect prefix [$($activityConvention.prefix)$($Script:namingSeparator)] for a [$($ActivityType)]"
        $Script:activityErrorCount++
    }
}


function CheckLinkedServicePrefix
{
    <#
    .SYNOPSIS
    Function that checks the prefix of a Linked Service and writes and counts the result
    .PARAMETER LinkedServiceName
    Name of the Linked Service you want to check
    .PARAMETER LinkedServiceType
    The type of Linked Service to determine the prefix
    .PARAMETER LinkedServicePrefix
    The expected prefix for the Linked Service
    .EXAMPLE
    CheckLinkedServicePrefix -LinkedServiceName $LinkedService.name -LinkedServiceType $LinkedService.type -LinkedServicePrefix $LinkedService.Prefix
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$LinkedServiceName,

        [Parameter(Mandatory = $true)]
        [string]$LinkedServiceType,

        [Parameter(Mandatory = $true)]
        [string]$LinkedServicePrefix
    )

    # Retrieve specific Linked Service prefix from naming convention object
    $linkedServiceConvention = $Script:namingConvention.LinkedServices | Where-Object { $_.Type -eq $LinkedServiceType }

    # Check if there is a prefix available
    if (!$linkedServiceConvention)
    {
        # If the Linked Service type is unknown, log an error and increment the error count
        Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Linked Service [$LinkedServiceName] has an unknown Linked Service type [$LinkedServiceType]"
        $Script:linkedServiceErrorCount++
    }
    elseif ($LinkedServiceName.StartsWith($LinkedServicePrefix + $Script:namingSeparator + $linkedServiceConvention.Prefix + $Script:namingSeparator))
    {
        # If the Linked Service has the correct prefix, write a success message and increment the success count
        Write-Output "$([char]10003) Linked Services [$($LinkedServiceName)] has the correct prefix [$($LinkedServicePrefix)$($Script:namingSeparator)$($linkedServiceConvention.Prefix)$($Script:namingSeparator)] for a [$($LinkedServiceType)] Linked Service"
        $Script:linkedServiceSuccessCount++
    }
    else
    {
        # If the Linked Service has an incorrect prefix, log an error and increment the error count
        Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Linked Services [$($LinkedServiceName)] has the incorrect prefix [$($LinkedServicePrefix)$($Script:namingSeparator)$($linkedServiceConvention.Prefix)$($Script:namingSeparator)] for a [$($LinkedServiceType)] Linked Service"
        $Script:linkedServiceErrorCount++
    }
}


function CheckDatasetServicePrefix
{
    <#
    .SYNOPSIS
    Function that checks the prefix of a dataset and writes and counts the result
    .PARAMETER DatasetName
    Name of the dataset you want to check
    .PARAMETER DatasetType
    The dataset type to determine the prefix
    .PARAMETER DatasetPrefix
    The prefix to be checked against the dataset name
    .EXAMPLE
    CheckDatasetServicePrefix -DatasetName $Dataset.name -DatasetType $Dataset.type -DatasetPrefix $Dataset.Prefix
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DatasetName,

        [Parameter(Mandatory = $true)]
        [string]$DatasetType,

        [Parameter(Mandatory = $true)]
        [string]$DatasetPrefix
    )

    # Retrieve specific Dataset prefix from naming convention object
    $datasetConvention = $Script:namingConvention.Datasets | Where-Object { $_.Type -eq $DatasetType }

    # Check if there is a prefix available
    if (!$datasetConvention)
    {
        # If the dataset type is unknown, log an error and increment the error count
        Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Dataset [$($DatasetName)] has an unknown dataset type [$($DatasetType)]"
        $Script:datasetErrorCount++
    }
    elseif (($DatasetName.StartsWith($DatasetPrefix + $Script:namingSeparator + $datasetConvention.Prefix + $Script:namingSeparator)) -or
            ($DatasetName -eq ($DatasetPrefix + $Script:namingSeparator + $datasetConvention.Prefix)))
    {
        # If the dataset name has the correct prefix, log a success message and increment the success count
        Write-Output "$([char]10003) Dataset [$($DatasetName)] has the correct prefix [$($DatasetPrefix)$($Script:namingSeparator)$($datasetConvention.Prefix)$($Script:namingSeparator)] for a [$($DatasetType)] Dataset"
        $Script:datasetSuccessCount++
    }
    else
    {
        # If the dataset name has an incorrect prefix, log an error and increment the error count
        Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Dataset [$($DatasetName)] has an incorrect prefix [$($DatasetPrefix)$($Script:namingSeparator)$($datasetConvention.Prefix)$($Script:namingSeparator)] for a [$($DatasetType)] Dataset"
        $Script:datasetErrorCount++
    }
}


function LogSummary {
    <#
    .SYNOPSIS
    Displays a summary of validation results
    .PARAMETER ValidationEnabled
    Specifies whether validation is disabled
    .PARAMETER NumberOfErrors
    The number of validations that failed
    .PARAMETER NumberOfSucceeds
    The number of validations that passed
    .PARAMETER ValidationName
    The name of the resource being validated
    .EXAMPLE
    LogSummary -ValidationEnabled $false -NumberOfErrors 10 -NumberOfSucceeds 13 -ValidationName "Pipelines"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [bool]$ValidationEnabled,

        [Parameter(Mandatory = $true)]
        [int]$NumberOfErrors,

        [Parameter(Mandatory = $true)]
        [int]$NumberOfSucceeds,

        [Parameter(Mandatory = $true)]
        [string]$ValidationName
    )

    # Number of positions before the colon. Used for aligning the summary rows.
    [int]$lengthText = 18

    # Create the first part of the summary row until the colon
    # Get the validation name and add spaces until the max lengthText is reached
    [string]$messageText = $ValidationName + (' ' * ($lengthText - $ValidationName.Length)) + ": "

    # Add the second part of the summary text after the colon
    # Check if validation was enabled
    if (!$ValidationEnabled)
    {
        # Validation disabled, so not showing any numbers
        $messageText += "validation disabled"
    }
    # Check if there where any of these objects at all
    elseif (($NumberOfErrors + $NumberOfSucceeds) -eq 0)
    {
        # No resources found of this type
        $messageText += "no $($ValidationName.ToLower()) found"
    }
    else
    {
        # Showing the error number and error percentage
        $errorPercentage = 100 - [Math]::Round(($NumberOfErrors / ($NumberOfErrors + $NumberOfSucceeds) * 100), 2)
        $messageText += "$NumberOfErrors errors out of $($NumberOfErrors + $NumberOfSucceeds) - ($errorPercentage% succeeded)"
    }

    # Writing summary log to the console
    Write-Host $messageText
}

#####################################################
# END Functions
#####################################################

# Retrieve naming separator from naming convention object
[string]$Script:namingSeparator = $Script:namingConvention.NamingSeparator

#####################################################
# PIPELINES & ACTIVITIES
#####################################################
# Retrieve all checks from naming convention config and filter on Pipeline/Activity to get its validate value
[bool]$pipelineCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Pipeline" }).validate
[bool]$activityCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Activity" }).validate

# Define variable for pipeline directory
$pipelineDirectory = Join-Path $ArtifactPath "pipeline"

# Check if there are any pipelines and if pipelines or activities need to be validated
if ((Test-Path $pipelineDirectory) -and ($pipelineCheck -or $activityCheck))
{
    # Retrieve pipeline prefix
    $pipelineConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "Pipeline" }

    # Retrieve all pipeline files
    $artifactPipelines = Get-ChildItem -Path $pipelineDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each pipeline file
    foreach ($pipeline in $artifactPipelines)
    {
        # Read file content to retrieve pipeline JSON
        $pipelineContent = Get-Content $pipeline.FullName | Out-String | ConvertFrom-Json

        # Determine pipeline path within the Synapse Workspace for (showing only)
        $pipelinePath = "\"
        if (HasProperty -JsonObject $pipelineContent.properties -PropertyName "folder")
        {
            # Build up path and replace forward slash with back slash
            $pipelinePath = $pipelinePath + $pipelineContent.properties.folder.name.replace("/","\") + "\"
        }

        # Pipeline header logging
        Write-Output "",
            "==============================================================================================",
            "Checking $(if(!$pipelineCheck -and $activityCheck) {"activities of "})Pipeline [$($pipelinePath)$($pipeline.BaseName)]",
            "=============================================================================================="

        # Check if the pipelines need to be validated
        if ($pipelineCheck)
        {
            # Check Pipeline name prefix
            if(!$pipeline.BaseName.StartsWith($pipelineConvention.prefix + $Script:namingSeparator))
            {
                # Show error message
                Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Pipeline prefix is not equals [$($pipelineConvention.prefix)$($Script:namingSeparator)] for [$($pipeline.BaseName)]"
                $Script:pipelineErrorCount++
            }
            else
            {
                # Show correct message
                Write-Output "$([char]10003) Pipeline prefix is correct"
                $Script:pipelineSuccessCount++
            }
        }
        else
        {
            Write-Output "Pipeline check disabled"
        }
        #####################################################
        # ACTIVITIES
        #####################################################
        # Check if the activities need to be validated
        if ($activityCheck)
        {
            LoopActivities  -LevelName $pipeline.BaseName `
                            -LevelNumber 1 `
                            -Activities $pipelineContent.properties.activities
        }
        else
        {
            Write-Output "Activity check disabled"
        }
    }
}
else
{
    Write-Output "",
        "=============================================================================================="
    if (!$pipelineCheck -and !$activityCheck)
    {
        Write-Output "Pipeline and activity check disabled"
    }
    elseif (-not (Test-Path $pipelineDirectory))
    {
        Write-Output "No Pipelines found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# NOTEBOOKS
#####################################################
# Retrieve all checks from naming convention config and filter on Notebook to get its validate value
[bool]$notebookCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Notebook" }).validate

# Define variable for notebook directory
$notebookDirectory = Join-Path $ArtifactPath "notebook"

# Check if there are any notebooks and whether the need to be validated
if ((Test-Path $notebookDirectory) -and ($notebookCheck))
{
    # Retrieve notebook prefix
    $notebookConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "Notebook" }

    # Retrieve all notebook files
    $artifactNotebooks = Get-ChildItem -Path $notebookDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each notebook file
    foreach ($notebook in $artifactNotebooks)
    {
        # Read file content to retrieve notebook JSON
        $notebookContent = Get-Content $notebook.FullName | Out-String | ConvertFrom-Json

        # Determine notebook path within the Synapse Workspace
        $notebookPath = "\"

        # If notebook is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $notebookContent.properties -PropertyName "folder")
        {
            # Build up path and replace forward slash with back slash
            $notebookPath = $notebookPath + $notebookContent.properties.folder.name.replace("/","\") + "\"
        }

        # Notebook logging
        Write-Output "",
            "==============================================================================================",
            "Checking Notebook [$($notebookPath)$($notebook.BaseName)]",
            "=============================================================================================="

        # Check Notebook name prefix
        if(!$notebook.BaseName.StartsWith($notebookConvention.prefix + $Script:namingSeparator))
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Notebook prefix is not equals [$($notebookConvention.prefix)$($Script:namingSeparator)] for [$($notebook.BaseName)]"
            $Script:notebookErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) Notebook prefix is correct"
            $Script:notebookSuccessCount++
        }
    }
}
else
{
    Write-Output "",
        "=============================================================================================="

    if (!$notebookCheck)
    {
        Write-Output "Notebook check disabled"
    }
    elseif (-not (Test-Path $notebookDirectory))
    {
        Write-Output "No Notebooks found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# LINKED SERVICES
#####################################################
# Retrieve all checks from naming convention config and then filter on LinkedService to get its validate value
[bool]$linkedServiceCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "LinkedService" }).validate

# Define variable for linked service directory
$linkedServiceDirectory = Join-Path $ArtifactPath "linkedService"

# Check if there are any linked services and whether the need to be validated
if ((Test-Path $linkedServiceDirectory) -and ($linkedServiceCheck))
{
    # Retrieve linked service prefix
    $linkedServiceConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "LinkedService" }

    # Retrieve all Linked Service files
    $artifactLinkedServices = Get-ChildItem -Path $linkedServiceDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each linked service file
    foreach ($linkedService in $artifactLinkedServices)
    {
        # Read file content to retrieve linked service JSON
        $linkedServiceContent = Get-Content $linkedService.FullName | Out-String | ConvertFrom-Json

        # Get type of linked service
        $linkedServiceType = $linkedServiceContent.properties.Type

        # Linked service logging
        Write-Output "",
            "==============================================================================================",
            "Checking Linked Service [$($linkedService.BaseName)] of type $($linkedServiceType)",
            "=============================================================================================="

        # Defining and filtering out default linked services
        $defaultLinkedServiceNames = @(($SynapseDevWorkspaceName + "-WorkspaceDefaultSqlServer"), ($SynapseDevWorkspaceName + "-WorkspaceDefaultStorage"))

        # Exclude the unchangable default Linked Services
        if ($defaultLinkedServiceNames -contains $linkedService.BaseName)
        {
            Write-Output "$([char]10003) Ignoring default Linked Services that cannot be renamed"
            $Script:linkedServiceSuccessCount++
        }
        else
        {
            # Check Pipeline name prefix
            CheckLinkedServicePrefix -LinkedServiceName $linkedService.BaseName `
                                     -LinkedServiceType $linkedServiceType `
                                     -LinkedServicePrefix $linkedServiceConvention.prefix
        }
    }
}
else
{
    Write-Output "",
        "=============================================================================================="
    if (!$linkedServiceCheck)
    {
        Write-Output "Linked Service check disabled"
    }
    elseif (-not (Test-Path $linkedServiceDirectory))
    {
        Write-Output "No Linked Services found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# DATASETS
#####################################################
# Retrieve all checks from naming convention config and then filter on Datasets to get its validate value
[bool]$datasetCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Dataset" }).validate

# Define variable for dataset directory
$datasetDirectory = Join-Path $ArtifactPath "dataset"

# Check if there are any datasets and whether the need to be validated
if ((Test-Path $datasetDirectory) -and ($datasetCheck))
{
    # Retrieve dataset prefix
    $datasetConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "Dataset" }

    # Retrieve dataset files
    $artifactDatasets = Get-ChildItem -Path $datasetDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each dataset file
    foreach ($dataset in $artifactDatasets)
    {
        # Read file content to retrieve pipeline JSON
        $datasetContent = Get-Content $dataset.FullName | Out-String | ConvertFrom-Json

        # Get type of dataset
        $datasetType = $datasetContent.properties.Type
        $linkedService = $datasetContent.properties.linkedServiceName.referenceName

        # Dataset logging
        Write-Output "",
            "==============================================================================================",
            "Checking Dataset [$($dataset.BaseName)] of type [$($datasetType)] connected to [$($linkedService)]",
            "=============================================================================================="

        # Check dataset name prefix
        CheckDatasetServicePrefix   -DatasetName $dataset.BaseName `
                                    -DatasetType $datasetType `
                                    -DatasetPrefix $datasetConvention.prefix
    }
}
else
{
    Write-Output "",
        "=============================================================================================="

    if (!$datasetCheck)
    {
        Write-Output "Dataset check disabled"
    }
    elseif (-not (Test-Path $datasetDirectory))
    {
        Write-Output "No Datasets found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# TRIGGERS
#####################################################
# Retrieve all checks from naming convention config and then filter on Trigger to get its validate value
[bool]$triggerCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Trigger" }).validate

# Define variable for trigger directory
$triggerDirectory = Join-Path $ArtifactPath "trigger"

# Check if there are any triggers and whether the need to be validated
if ((Test-Path $triggerDirectory) -and ($triggerCheck))
{
    # Retrieve trigger prefix
    $triggerConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "trigger" }

    # Retrieve allowed trigger postfixes and add separator in front of it
    [String[]]$allowPostFixes = $Script:namingConvention.TriggerPostfixes | ForEach-Object {$Script:namingSeparator + $_}

    # Retrieve all trigger files
    $artifactTriggers = Get-ChildItem -Path $triggerDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each trigger file
    foreach ($trigger in $artifactTriggers)
    {
        # Initialize count for each trigger error
        $triggerSubCount = 0

        # Trigger logging
        Write-Output "",
            "==============================================================================================",
            "Checking Trigger [$($trigger.BaseName)]",
            "=============================================================================================="

        # Check trigger name prefix
        if (!$trigger.BaseName.StartsWith($triggerConvention.prefix + $Script:namingSeparator))
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Trigger prefix is not equals [$($triggerConvention.prefix)$($Script:namingSeparator)] for [$($trigger.BaseName)]"
            $triggerSubCount++
        }
        else
        {
            Write-Output "$([char]10003) Trigger prefix is correct"
        }

        # Get trigger postfix
        $triggerPostfix = $trigger.BaseName.Substring($trigger.BaseName.LastIndexOf($Script:namingSeparator))

        # Check trigger name postfix
        if ($allowPostFixes -NotContains $triggerPostfix)
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Trigger postfix $triggerPostfix is incorrect, expected one of the following for [$($trigger.BaseName)]: $($allowPostFixes -join ", ")"
            $triggerSubCount++
        }
        else
        {
            Write-Output "$([char]10003) Trigger postfix $triggerPostfix is correct"
        }

        # Raise error count once for either prefix or postfix, not for both errors
        if ($triggerSubCount -gt 0)
        {
            $Script:triggerErrorCount++
        }
        else
        {
            $Script:triggerSuccessCount++
        }
    }
}
else
{
    Write-Output "",
        "=============================================================================================="

    if (!$triggerCheck)
    {
        Write-Output "Trigger check disabled"
    }
    elseif (-not (Test-Path $triggerDirectory))
    {
        Write-Output "No Triggers found in artifact"
    }

    Write-Output "=============================================================================================="
}

#####################################################
# DATAFLOWS
#####################################################
# Retrieve all checks from naming convention config and then filter on Dataflow to get its validate value
[bool]$dataflowCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "Dataflow" }).validate

#Define variable for dataflow directory
$dataflowDirectory = Join-Path $ArtifactPath "dataflow"

# Check if there are any dataflows and whether the need to be validated
if ((Test-Path $dataflowDirectory) -and ($dataflowCheck))
{
    # Retrieve dataflow prefix
    $dataflowConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "Dataflow" }

    # Retrieve all dataflow files
    $artifactDataflows = Get-ChildItem -Path $dataflowDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each dataflow file
    foreach ($dataflow in $artifactDataflows)
    {
        # Read file content to retrieve dataflow JSON
        $dataflowContent = Get-Content $dataflow.FullName -Raw | ConvertFrom-Json

        # Determine dataflow path within the Synapse Workspace for (showing only)
        $dataflowPath = "\"
        # If dataflow is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $dataflowContent.properties -PropertyName "folder")
        {
            $dataflowPath += $dataflowContent.properties.folder.name.replace("/","\") + "\"
        }

        # Dataflow logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking Dataflow [$($dataflowPath)$($dataflow.BaseName)]"
        Write-Output "=============================================================================================="

        # Check dataflow name prefix
        if (!$dataflow.BaseName.StartsWith($dataflowConvention.prefix + $Script:namingSeparator))
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) Dataflow prefix is not equals [$($dataflowConvention.prefix)$($Script:namingSeparator)] for [$($dataflow.BaseName)]"
            $Script:dataflowErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) Dataflow prefix is correct"
            $Script:dataflowSuccessCount++
        }
    }
}
else
{
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$dataflowCheck)
    {
        Write-Output "Dataflow check disabled"
    }
    elseif (-not (Test-Path $dataflowDirectory))
    {
        Write-Output "No dataflows found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# SQL SCRIPTS
#####################################################
# Retrieve all checks from naming convention config and then filter on sqlscript to get its validate value
[bool]$sqlScriptCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "SqlScript" }).validate

# Define variable for sqlscript directory
$sqlScriptDirectory = Join-Path $ArtifactPath "sqlscript"

# Check if there are any sql scripts and whether the need to be validated
if ((Test-Path $sqlScriptDirectory) -and ($sqlScriptCheck))
{
    # Retrieve sqlscript prefix
    $sqlScriptConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "SqlScript" }

    # Retrieve all sqlscript files
    $artifactSqlScripts = Get-ChildItem -Path $sqlScriptDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each sqlscript file
    foreach ($sqlScript in $artifactSqlScripts)
    {
        # Read file content to retrieve sqlscript JSON
        $sqlScriptContent = Get-Content $sqlScript.FullName -Raw | ConvertFrom-Json

        # Determine sqlscript path within the Synapse Workspace for (showing only)
        $sqlScriptPath = "\"
        # If sqlscript is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $sqlScriptContent.properties -PropertyName "folder")
        {
            $sqlScriptPath += $sqlScriptContent.properties.folder.name.replace("/","\") + "\"
        }

        # Sqlscript logging
        Write-Output "",
            "==============================================================================================",
            "Checking SQL-Script [$($sqlScriptPath)$($sqlScript.BaseName)]",
            "=============================================================================================="

        # Check sqlscript name prefix
        if (!$sqlScript.BaseName.StartsWith($sqlScriptConvention.prefix + $Script:namingSeparator))
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) SQL script prefix is not equals [$($sqlScriptConvention.prefix)$($Script:namingSeparator)] for [$($sqlScript.BaseName)]"
            $Script:sqlScriptErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) SQL script prefix is correct"
            $Script:sqlScriptSuccessCount++
        }
    }
}
else
{
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$sqlScriptCheck)
    {
        Write-Output "SQL Script check disabled"
    }
    elseif (-not (Test-Path $sqlScriptDirectory))
    {
        Write-Output "No SQL Script found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# KQL SCRIPTS
#####################################################
# Retrieve all checks from naming convention config and then filter on KqlScript to get its validate value
[bool]$kqlScriptCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "KqlScript" }).validate

# Define variable for kqlscript directory
$kqlScriptDirectory = Join-Path $ArtifactPath "kqlscript"

# Check if there are any kql scripts and whether the need to be validated
if ((Test-Path $kqlScriptDirectory) -and ($kqlScriptCheck))
{
    # Retrieve kqlscript prefix
    $kqlScriptConvention = $Script:namingConvention.Prefixes | Where-Object { $_.Type -eq "KqlScript" }

    # Retrieve all kqlscript files
    $artifactKqlScripts = Get-ChildItem -Path $kqlScriptDirectory -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each kqlscript file
    foreach ($kqlScript in $artifactKqlScripts)
    {
        # Read file content to retrieve kqlscript JSON
        $kqlScriptContent = Get-Content $kqlScript.FullName -Raw | ConvertFrom-Json

        # Determine kqlscript path within the Synapse Workspace for (showing only)
        $kqlScriptPath = "\"
        # If kqlscript is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $kqlScriptContent.properties -PropertyName "folder")
        {
            $kqlScriptPath += $kqlScriptContent.properties.folder.name.replace("/","\") + "\"
        }

        # Kqlscript logging
        Write-Output "",
            "==============================================================================================",
            "Checking KQL-Script [$($kqlScriptPath)$($kqlScript.BaseName)]",
            "=============================================================================================="

        # Check kqlscript name prefix
        if (!$kqlScript.BaseName.StartsWith($kqlScriptConvention.prefix + $Script:namingSeparator))
        {
            Write-Error "##vso[task.LogIssue type=error;]$([char]10007) KQL script prefix is not equals [$($kqlScriptConvention.prefix)$($Script:namingSeparator)] for [$($kqlScript.BaseName)]"
            $Script:kqlScriptErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) KQL script prefix is correct"
            $Script:kqlScriptSuccessCount++
        }
    }
}
else
{
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$kqlScriptCheck)
    {
        Write-Output "KQL Script check disabled"
    }
    elseif (-not (Test-Path $kqlScriptDirectory))
    {
        Write-Output "No KQL Script found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# CHECK ALL RESOURCE POSTFIXES
#####################################################
# Retrieve all checks from naming convention config and then filter on Postfixes to get its validate value
[bool]$postfixCheck = ($Script:namingConvention.Checks | Where-Object { $_.Type -eq "CopyPostfixes" }).validate

# Check if _copy postfixes need to be valided
if ($postfixCheck)
{
    # Get all resources checking on the _copy** postfix
    $allResources = Get-ChildItem -Path $ArtifactPath -Recurse -Filter *.json | Select-Object -Property FullName, BaseName

    # Filter the resources which have incorrect postfix
    $incorrectResources = $allResources | Where-Object { $_.BaseName -match '_copy([1-9][0-9]?)$'}

    # Count total and incorrect resources
    $totalResourcesCount = ($allResources | Measure-Object).Count
    $incorrectResourcesCount = ($incorrectResources | Measure-Object).Count

    # Calculate successful resources count
    [int]$Script:invalidPostfixErrorCount += $incorrectResourcesCount
    [int]$Script:invalidPostfixSuccessCount += $totalResourcesCount - $incorrectResourcesCount

    Write-Output ""
    Write-Output "=============================================================================================="
    Write-Output "Invalid postfixes $incorrectResourcesCount"
    Write-Output "=============================================================================================="

    # Loop through all resources with an invalid _copy* postfix
    foreach ($resource in $incorrectResources)
    {
        # Write all 'errors' to screen
        Write-Error "##vso[task.LogIssue type=error;]$([char]10007) $((Get-Item $resource.FullName).Directory.Name) resource [$($resource.BaseName)] has a _copy postfix"
    }
}


#####################################################
# SUMMARY
#####################################################
Write-Output ""
Write-Output "=============================================================================================="
Write-Output "Summary"
Write-Output "=============================================================================================="
LogSummary  -ValidationEnabled $pipelineCheck `
            -NumberOfErrors $Script:pipelineErrorCount `
            -NumberOfSucceeds $Script:pipelineSuccessCount `
            -ValidationName "Pipelines"
LogSummary  -ValidationEnabled $activityCheck `
            -NumberOfErrors $Script:activityErrorCount `
            -NumberOfSucceeds $Script:activitySuccessCount `
            -ValidationName "Activities"
LogSummary  -ValidationEnabled $notebookCheck `
            -NumberOfErrors $Script:notebookErrorCount `
            -NumberOfSucceeds $Script:notebookSuccessCount `
            -ValidationName "Notebooks"
LogSummary  -ValidationEnabled $linkedServiceCheck `
            -NumberOfErrors $Script:linkedServiceErrorCount `
            -NumberOfSucceeds $Script:linkedServiceSuccessCount `
            -ValidationName "Linked Services"
LogSummary  -ValidationEnabled $datasetCheck `
            -NumberOfErrors $Script:datasetErrorCount `
            -NumberOfSucceeds $Script:datasetSuccessCount `
            -ValidationName "Datasets"
LogSummary  -ValidationEnabled $triggerCheck `
            -NumberOfErrors $Script:triggerErrorCount `
            -NumberOfSucceeds $Script:triggerSuccessCount `
            -ValidationName "Triggers"
LogSummary  -ValidationEnabled $dataflowCheck `
            -NumberOfErrors $Script:dataflowErrorCount `
            -NumberOfSucceeds $Script:dataflowSuccessCount `
            -ValidationName "Dataflows"
LogSummary  -ValidationEnabled $sqlScriptCheck `
            -NumberOfErrors $Script:sqlScriptErrorCount `
            -NumberOfSucceeds $Script:sqlScriptSuccessCount `
            -ValidationName "SQL Scripts"
LogSummary  -ValidationEnabled $kqlscriptCheck `
            -NumberOfErrors $Script:kqlScriptErrorCount `
            -NumberOfSucceeds $Script:kqlScriptSuccessCount `
            -ValidationName "KQL Scripts"
LogSummary  -ValidationEnabled $postfixCheck `
            -NumberOfErrors $Script:invalidPostfixErrorCount `
            -NumberOfSucceeds $Script:invalidPostfixSuccessCount `
            -ValidationName "Invalid Postfixes"
Write-Output "=============================================================================================="

# Calculate total errors
$totalErrors = $pipelineErrorCount + $activityErrorCount + $notebookErrorCount + $linkedServiceErrorCount + $datasetErrorCount + $triggerErrorCount + $dataflowErrorCount + $sqlscriptErrorCount + $kqlscriptErrorCount + $invalidPostfixErrorCount

# Only show error count if there are errors
if ($totalErrors -gt 0) {
    Write-Output "Total number of errors found: $totalErrors"
    Write-Output "=============================================================================================="

    # Make sure DevOps knows the script failed
    exit 1
}