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
#####################################################
# Variables for counting errors
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
[int]$Script:sqlscriptErrorCount = 0
[int]$Script:sqlscriptSuccessCount = 0
[int]$Script:kqlscriptErrorCount = 0
[int]$Script:kqlscriptSuccessCount = 0
[int]$Script:invalidPostfixErrorCount = 0
[int]$Script:invalidPostfixSuccessCount = 0

#####################################################
# Check parameters
#####################################################
# Check Synapse Artifact path
if (Test-Path $ArtifactPath)
{
    # Folder exists, but is it the root of Synapse?
    if (-not (Test-Path (Join-Path $ArtifactPath "linkedService")))
    {
        Write-Error "Supplied Artifact Path exists, but does not contain a subfolder linkedService."
    }
}
else
{
    # Folder does not exist
    Write-Error "Supplied Artifact Path doesn't exists! $ArtifactPath"
}

# Check Naming Convention path and load content into memory
[PSObject]$namingConvention = $null
if (Test-Path $NamingConventionPath)
{
    #$isValidJson = Get-Content $NamingConventionPath -Raw | Test-Json # Powershell Core only to remove entire try-catch
    try {
        $namingConvention = Get-Content $NamingConventionPath | Out-String | ConvertFrom-Json

        $isValidJson = $true;
    } catch {
        $isValidJson = $false;
    }
    if(-not $isValidJson)
    {
        Write-Error "Naming Convention Path doesn't contain valid JSON!"
    }
}
else
{
    Write-Error "Naming Convention Path doesn't exists! $($NamingConventionPath)"
}


#####################################################
# Functions
#####################################################
function HasProperty
{
    <#
        .SYNOPSIS
        Check if the JSON object contains a certain property
        .PARAMETER PropertyName
        Name of the property you want to check for existance
        .PARAMETER JsonObject
        A JSON object in which you want to check
        .EXAMPLE
        HasProperty -JsonObject $pipelineContent.properties -PropertyName "folder"
    #>
    param (
        [string]$PropertyName,
        [PSObject]$JsonObject
    )
    # Check if the JSON object contains a property with a specific name
    return $JsonObject.PSobject.Properties.Name -contains $PropertyName
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
    param (
        [string]$LevelName,
        [int]$LevelNumber,
        [PSObject]$Activities
    )

#    # Retrieve all checks from naming covention config and then filter on Postfixes to get its validate value
#    [bool]$postfixCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Postfixes" }).validate
#
#    if ($postfixCheck)
#    {
#        # Assign all resources to the resources variable while checking on the _copy** postfixe
#        $incorrectActivities = $Activities | Where-Object { $_.name -match '_copy([1-9][0-9]?)$'} | Select-Object -Property name, type
#
#        # Count errors and succeeds
#        [int]$Script:invalidPostfixErrorCount += ($incorrectActivities | Measure-Object).Count
#        [int]$Script:invalidPostfixSuccessCount += ($Activities | Measure-Object).Count - ($incorrectResources | Measure-Object).Count
#
#        # Loop through all activities with an invalid _copy* postfix
#        foreach ($incorrectActivity in $incorrectActivities)
#        {
#            # Write all 'errors' to screen
#            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Activity [$($incorrectActivity.name)] has the incorrect postfix _copy"
#        }
#    }

    # Loop through the activities
    foreach ($activity in $Activities)
    {

        # Check the prefix of the activity
        CheckActivityPrefix -ActivityName $Activity.name `
                            -ActivityType $Activity.type `
                            -Separator "_" `
                            -LevelNumber $LevelNumber


        # Loop through child activities in Foreach and Until
        if ($activity.type -eq "ForEach" -or $activity.type -eq "Until")
        {
            LoopActivities  -LevelName ($LevelName + "\" + $activity.name) `
                            -LevelNumber ($LevelNumber + 1) `
                            -Activities $activity.typeProperties.activities
        }

        # Loop through child activities in Switch
        if ($activity.type -eq "Switch")
        {
            # Loop through default Activities
            LoopActivities  -LevelName ($LevelName + "\" + $activity.name + "\Default") `
                            -LevelNumber ($LevelNumber + 1) `
                            -Activities $activity.typeProperties.defaultActivities

            # Loop through cases
            Foreach ($case in $activity.cases)
            {
                LoopActivities  -LevelName ($LevelName + "\" + $activity.name + "\" + $case.value) `
                                -LevelNumber ($LevelNumber + 1) `
                                -Activities $case.activities
            }
        }

        # Loop through child activities in IfCondition
        if ($Activity.type -eq "IfCondition")
        {
            # Loop through true activities
            if (HasProperty -JsonObject $activity.typeProperties -PropertyName "ifTrueActivities")
            {
                LoopActivities  -LevelName ($LevelName + "\" + $activity.name + "\True") `
                                -LevelNumber ($LevelNumber + 1) `
                                -Activities $activity.typeProperties.ifTrueActivities
            }
            # Loop through false activities
            if (HasProperty -JsonObject $activity.typeProperties -PropertyName "ifFalseActivities")
            {
                LoopActivities  -LevelName ($LevelName + "\" + $activity.name + "\False") `
                                -LevelNumber ($LevelNumber + 1) `
                                -Activities $activity.typeProperties.ifFalseActivities
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
        The activity type to determing the prefix
        .EXAMPLE
        CheckActivityPrefix -ActivityName $Activity.name -ActivityType $Activity.type
    #>
    param (
        [string]$ActivityName,
        [string]$ActivityType,
        [int]$LevelNumber
    )
    $spaces = ""
    if ($LevelNumber -eq 2)
    {
        $spaces = "  "
    } elseif ($LevelNumber -eq 3)
    {
        $spaces = "    "
    }

    # Retrieve prefix from naming convention
    $activityConvention = $namingConvention.Activities | Where-Object { $_.Type -eq $ActivityType }

    # Check if there is a prefix available
    if (!$activityConvention)
    {
        Write-Host "##vso[task.LogIssue type=error;]$($spaces)$([char]10007) Activity [$($ActivityName)] has unknown activity type [$($ActivityType)]"
        $Script:activityErrorCount++
    }
    # Check if the used prefix is correct
    elseif ($ActivityName.StartsWith($activityConvention.prefix + $namingSeparator))
    {
        Write-Output "$($spaces)$([char]10003) Activity [$($ActivityName)] has the correct prefix [$($activityConvention.prefix)$($namingSeparator)] for a [$($ActivityType)]"
        $Script:activitySuccessCount++
    }
    else
    {
        Write-Host "##vso[task.LogIssue type=error;]$($spaces)$([char]10007) Activity [$($ActivityName)] has an incorrect prefix [$($activityConvention.prefix)$($namingSeparator)] for a [$($ActivityType)]"
        $Script:activityErrorCount++
    }
}


function CheckLinkedServicePrefix
{
    <#
        .SYNOPSIS
        Function that checks the prefix and writes and counts the result
        .PARAMETER LinkedServiceName
        Name of the Linked Service you want to check
        .PARAMETER LinkedServiceType
        The Linked Service type to determing the prefix
        .PARAMETER LinkedServicePrefix
        The Linked Service type to determing the prefix
        .EXAMPLE
        CheckLinkedServicePrefix -LinkedServiceName $LinkedService.name -LinkedServiceType $LinkedService.type -LinkedServicePrefix $LinkedService.Prefix
    #>
    param (
        [string]$LinkedServiceName,
        [string]$LinkedServiceType,
        [string]$LinkedServicePrefix
    )
    # Get naming conventions from JSON file
    $linkedServiceConvention = $namingConvention.LinkedServices | Where-Object { $_.Type -eq $LinkedServiceType }

    if (!$linkedServiceConvention)
    {
        Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Linked Services [$($LinkedServiceName)] has unknown Linked Services type [$($LinkedServiceType)] "
        $Script:linkedServiceErrorCount++
    }
    elseif ($LinkedServiceName.StartsWith($LinkedServicePrefix + $namingSeparator + $linkedServiceConvention.Prefix + $namingSeparator))
    {
        Write-Output "$([char]10003) Linked Services [$($LinkedServiceName)] has the correct prefix [$($LinkedServicePrefix)$($namingSeparator)$($linkedServiceConvention.Prefix)$($namingSeparator)] for a [$($LinkedServiceType)]"
        $Script:linkedServiceSuccessCount++
    }
    else
    {
        Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Linked Services [$($LinkedServiceName)] has the incorrect prefix [$($LinkedServicePrefix)$($namingSeparator)$($linkedServiceConvention.Prefix)$($namingSeparator)] for a [$($LinkedServiceType)]"
        $Script:linkedServiceErrorCount++
    }
}


function CheckDatasetServicePrefix
{
    <#
        .SYNOPSIS
        Function that checks the prefix and writes and counts the result
        .PARAMETER DatasetName
        Name of the Linked Service you want to check
        .PARAMETER DatasetType
        The Linked Service type to determing the prefix
        .PARAMETER DatasetPrefix
        The Linked Service type to determing the prefix
        .EXAMPLE
        CheckDatasetServicePrefix -DatasetName $Dataset.name -DatasetType $Dataset.type -DatasetPrefix $Dataset.Prefix
    #>
    param (
        [string]$DatasetName,
        [string]$DatasetType,
        [string]$DatasetPrefix
    )

    $datasetConvention = $namingConvention.Datasets | Where-Object { $_.Type -eq $DatasetType }


    if (!$datasetConvention)
    {
        Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Dataset [$($DatasetName)] has unknown dataset type [$($DatasetType)]"
        $Script:datasetErrorCount++
    }
    elseif (
                ($DatasetName.StartsWith($DatasetPrefix + $namingSeparator + $datasetConvention.Prefix + $namingSeparator)) -or
                ($DatasetName -eq ($DatasetPrefix + $namingSeparator + $datasetConvention.Prefix))
            )
    {
        Write-Output "$([char]10003) Dataset [$($DatasetName)] has the correct prefix [$($DatasetPrefix)$($namingSeparator)$($datasetConvention.Prefix)$($namingSeparator)] for a [$($DatasetType)]"
        $Script:datasetSuccessCount++
    }
    else
    {
        Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Dataset [$($DatasetName)] has the incorrect prefix [$($DatasetPrefix)$($namingSeparator)$($datasetConvention.Prefix)$($namingSeparator)] for a [$($DatasetType)]"
        $Script:datasetErrorCount++
    }
}


function LogSummary
{
    <#
        .SYNOPSIS
        ***********************
        .PARAMETER ValidationDisabled
        Boolean indicating you are skipping the validation
        .PARAMETER NumberOfErrors
        Number of validations that failed
        .PARAMETER NumberOfSucceeds
        Number of validations that passed
        .PARAMETER ValidationName
        Name of the resource you checked
        .EXAMPLE
        LogSummary -ValidationDisabled $false -NumberOfErrors 10 -NumberOfSucceeds 13 -ValidationName "Pipelines"
    #>
    param (
        [bool]$ValidationDisabled,
        [int]$NumberOfErrors,
        [int]$NumberOfSucceeds,
        [string]$ValidationName
    )
    # Number of positions before the colon. Used for aligning the summary rows
    [int]$lengthText = 18

    # Create the first part of the summary row until the colon
    [string]$messageText = $ValidationName + (' ' * ($lengthText - $ValidationName.Length)) + ": "

    # Create the second part of the summary row after the colon
    if (!$ValidationDisabled)
    {
        # Validation disabled, so not showing any numbers
        $messageText += "validation disabled"
    }
    elseif (($NumberOfErrors + $NumberOfSucceeds) -eq 0)
    {
        # No resources found of this type
        $messageText += "no $($ValidationName.ToLower()) found"
    }
    else
    {
        # Showing the error number and error percentage
        $messageText += "$($NumberOfErrors) errors out of $($NumberOfErrors + $NumberOfSucceeds) - $([Math]::Round(($NumberOfErrors / ($NumberOfErrors + $NumberOfSucceeds) * 100), 2))%"
    }
    # Writing summary log to screen
    Write-Host $messageText
}
#####################################################
# END Functions
#####################################################

# Retrieve naming separator from naming convention config
[string]$namingSeparator = $namingConvention.NamingSeparator

#####################################################
# PIPELINES & ACTIVITIES
#####################################################
# Retrieve all checks from naming covention config and then filter on Pipeline/Activity to get its validate value
[bool]$pipelineCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Pipeline" }).validate
[bool]$activityCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Activity" }).validate

# Check if there are pipelines and check if pipelines or activities need to be validated
if ((Test-Path (Join-Path $ArtifactPath "pipeline")) -and (($pipelineCheck) -or ($activityCheck)))
{
    # Retrieve pipeline prefix
    $pipelineConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "Pipeline" }

    # Retrieve all pipeline files
    $artifactPipelines = Get-ChildItem -Path (Join-Path $ArtifactPath "pipeline") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each pipeline file
    foreach ($pipeline in $artifactPipelines)
    {
        # Read file content to retrieve pipeline JSON
        $pipelineContent = Get-Content $pipeline.FullName | Out-String | ConvertFrom-Json

        # Determine pipeline path within the Synapse Workspace for (showing only)
        $pipelinePath = "\"
        # If pipeline is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $pipelineContent.properties -PropertyName "folder")
        {
            $pipelinePath = $pipelinePath + $pipelineContent.properties.folder.name.replace("/","\") + "\"
        }

        # Pipeline loggin
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking pipeline [$($pipelinePath)$($pipeline.BaseName)]"
        Write-Output "=============================================================================================="
        # Check if the pipelines need to validated
        if ($pipelineCheck)
        {
            # Check Pipeline name prefix
            if(!$pipeline.BaseName.StartsWith($pipelineConvention.prefix + $namingSeparator))
            {
                Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Pipeline prefix is not equals [$($pipelineConvention.prefix)$($namingSeparator)] for [$($pipeline.BaseName)]"
                $Script:pipelineErrorCount++
            }
            else
            {
                Write-Output "$([char]10003) Pipeline prefix is correct"
                $Script:pipelineSuccessCount++
            }
        }
        #####################################################
        # ACTIVITIES
        #####################################################
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
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$pipelineCheck)
    {
        Write-Output "Pipeline check disabled"
    }
    elseif (-not (Test-Path (Join-Path $ArtifactPath "pipeline")))
    {
        Write-Output "No pipelines found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# NOTEBOOKS
#####################################################
# Retrieve all checks from naming covention config and then filter on Notebook to get its validate value
[bool]$notebookCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Notebook" }).validate

if ((Test-Path (Join-Path $ArtifactPath "notebook")) -and ($notebookCheck))
{
    # Retrieve notebook prefix
    $notebookConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "Notebook" }

    # Retrieve all notebook files
    $artifactNotebooks = Get-ChildItem -Path (Join-Path $ArtifactPath "notebook") -Filter *.json | Select-Object -Property FullName, BaseName

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
            $notebookPath = $notebookPath + $notebookContent.properties.folder.name.replace("/","\") + "\"
        }

        # Notebook logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking Notebook [$($notebookPath)$($notebook.BaseName)]"
        Write-Output "=============================================================================================="
        # Check Notebook name prefix
        if(!$notebook.BaseName.StartsWith($notebookConvention.prefix + $namingSeparator))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Notebook prefix is not equals [$($notebookConvention.prefix)$($namingSeparator)] for [$($notebook.BaseName)]"
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
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$notebookCheck)
    {
        Write-Output "Notebook check disabled"
    }
    elseif (-not (Test-Path (Join-Path $ArtifactPath "notebook")))
    {
        Write-Output "No notebooks found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# LINKED SERVICES
#####################################################
# Retrieve all checks from naming covention config and then filter on LinkedService to get its validate value
[bool]$linkedServiceCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "LinkedService" }).validate

if ((Test-Path (Join-Path $ArtifactPath "linkedService")) -and ($linkedServiceCheck))
{
    # Retrieve linked service prefix
    $linkedServiceConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "LinkedService" }

    # Retrieve all Linkes Service files
    $artifactLinkedServices = Get-ChildItem -Path (Join-Path $ArtifactPath "linkedService") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each linked service file
    foreach ($linkedService in $artifactLinkedServices)
    {
        # Read file content to retrieve pipeline JSON
        $linkedServiceContent = Get-Content $linkedService.FullName | Out-String | ConvertFrom-Json

        # Get type of Linked Service
        $linkedServiceType = $linkedServiceContent.properties.Type

        # Linked Service logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking Linked Service [$($linkedService.BaseName)] of type $($linkedServiceType)"
        Write-Output "=============================================================================================="


        if ($linkedService.BaseName -eq ($SynapseDevWorkspaceName + "-WorkspaceDefaultSqlServer") -or
            $linkedService.BaseName -eq ($SynapseDevWorkspaceName + "-WorkspaceDefaultStorage"))
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
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$linkedServiceCheck)
    {
        Write-Output "Linked services check disabled"
    }
    elseif (-not (Test-Path (Join-Path $ArtifactPath "linkedService")))
    {
        Write-Output "No linked services found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# DATASETS
#####################################################
# Retrieve all checks from naming covention config and then filter on Datasets to get its validate value
[bool]$datasetCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Dataset" }).validate

if ((Test-Path (Join-Path $ArtifactPath "dataset")) -and ($datasetCheck))
{
    # Retrieve dataset prefix
    $datasetConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "Dataset" }

    # Retrieve dataset files
    $artifactDatasets = Get-ChildItem -Path (Join-Path $ArtifactPath "dataset") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each dataset file
    foreach ($dataset in $artifactDatasets)
    {
        # Read file content to retrieve pipeline JSON
        $datasetContent = Get-Content $dataset.FullName | Out-String | ConvertFrom-Json

        # Get type of dataset
        $datasetType = $datasetContent.properties.Type
        $linkedService = $datasetContent.properties.linkedServiceName.referenceName

        # Dataset logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking Dataset [$($dataset.BaseName)] of type [$($datasetType)] connected to [$($linkedService)]"
        Write-Output "=============================================================================================="

        # Check dataset name prefix
        CheckDatasetServicePrefix   -DatasetName $dataset.BaseName `
                                    -DatasetType $datasetType `
                                    -DatasetPrefix $datasetConvention.prefix
    }
}
else
{
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$datasetCheck)
    {
        Write-Output "Dataset check disabled"
    }
    elseif (-not (Test-Path (Join-Path $ArtifactPath "dataset")))
    {
        Write-Output "No datasets found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# TRIGGERS
#####################################################
# Retrieve all checks from naming covention config and then filter on Trigger to get its validate value
[bool]$triggerCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Trigger" }).validate

if ((Test-Path (Join-Path $ArtifactPath "trigger")) -and ($triggerCheck))
{
    # Retrieve trigger prefix
    $triggerConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "trigger" }

    # Retrieve allowed trigger postfixes and add separator in front of it
    [String[]]$allowPostFixes = $namingConvention.TriggerPostfixes
    $allowPostFixes = $allowPostFixes | ForEach-Object {$namingSeparator + $_}

    # Retrieve all Linkes Service files
    $artifactTriggers = Get-ChildItem -Path (Join-Path $ArtifactPath "trigger") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each Triggers file
    foreach ($trigger in $artifactTriggers)
    {
        # Pipeline loggin
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking trigger [$($trigger.BaseName)]"
        Write-Output "=============================================================================================="

        $triggerSubCount = 0

        # Check trigger name prefix
        if (!$trigger.BaseName.StartsWith($triggerConvention.prefix + $namingSeparator))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Trigger prefix is not equals [$($triggerConvention.prefix)$($namingSeparator)] for [$($trigger.BaseName)]"
            $triggerSubCount++
        }
        else
        {
            Write-Output "$([char]10003) Trigger prefix is correct"
        }

        # Check trigger name postfix
        if ($allowPostFixes -NotContains $trigger.BaseName.Substring($trigger.BaseName.Length - 4, 4))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Trigger postfix $($trigger.BaseName.Substring($trigger.BaseName.Length - 4, 4)) is incorrect, expected $($allowPostFixes -join " or ") for [$($trigger.BaseName)]"
            $triggerSubCount++
        }
        else
        {
            Write-Output "$([char]10003) Trigger postfix $($trigger.BaseName.Substring($trigger.BaseName.Length - 4, 4)) is correct"
        }

        # Raise error count once for either pre of postfix, not for both errors
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
    Write-Output ""
    Write-Output "=============================================================================================="
    if (!$triggerCheck)
    {
        Write-Output "Trigger check disabled"
    }
    elseif (-not (Test-Path (Join-Path $ArtifactPath "trigger")))
    {
        Write-Output "No triggers found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# DATAFLOWS
#####################################################
# Retrieve all checks from naming covention config and then filter on Dataflow to get its validate value
[bool]$dataflowCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Dataflow" }).validate

if ((Test-Path (Join-Path $ArtifactPath "dataflow")) -and ($dataflowCheck))
{
    # Retrieve dataflow prefix
    $dataflowConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "Dataflow" }

    # Retrieve all dataflow files
    $artifactDataflows = Get-ChildItem -Path (Join-Path $ArtifactPath "dataflow") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each dataflow file
    foreach ($dataflow in $artifactDataflows)
    {
        # Read file content to retrieve dataflow JSON
        $dataflowContent = Get-Content $dataflow.FullName | Out-String | ConvertFrom-Json

        # Determine dataflow path within the Synapse Workspace for (showing only)
        $dataflowPath = "\"
        # If dataflow is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $dataflowContent.properties -PropertyName "folder")
        {
            $dataflowPath = $dataflowPath + $dataflowContent.properties.folder.name.replace("/","\") + "\"
        }

        # Dataflow logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking dataflow [$($dataflowPath)$($dataflow.BaseName)]"
        Write-Output "=============================================================================================="

        # Check dataflow name prefix
        if (!$dataflow.BaseName.StartsWith($dataflowConvention.prefix + $namingSeparator))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Dataflow prefix is not equals [$($dataflowConvention.prefix)$($namingSeparator)] for [$($dataflow.BaseName)]"
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
    elseif (-not (Test-Path (Join-Path $ArtifactPath "dataflow")))
    {
        Write-Output "No dataflows found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# SQL SCRIPTS
#####################################################
# Retrieve all checks from naming covention config and then filter on SqlScript to get its validate value
[bool]$sqlScriptCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "SqlScript" }).validate

if ((Test-Path (Join-Path $ArtifactPath "sqlscript")) -and ($sqlScriptCheck))
{
    # Retrieve sqlscript prefix
    $sqlscriptConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "SqlScript" }

    # Retrieve all sqlscript files
    $artifactSqlScripts = Get-ChildItem -Path (Join-Path $ArtifactPath "sqlscript") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each sqlscript file
    foreach ($sqlscript in $artifactSqlScripts)
    {
        # Read file content to retrieve sqlscript JSON
        $sqlscriptContent = Get-Content $sqlscript.FullName | Out-String | ConvertFrom-Json

        # Determine sqlscript path within the Synapse Workspace for (showing only)
        $sqlscriptPath = "\"
        # If sqlscript is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $sqlscriptContent.properties -PropertyName "folder")
        {
            $sqlscriptPath = $sqlscriptPath + $sqlscriptContent.properties.folder.name.replace("/","\") + "\"
        }

        # Sql Script logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking dataflow [$($sqlscriptPath)$($sqlscript.BaseName)]"
        Write-Output "=============================================================================================="

        # Check sqlscript name prefix
        if (!$sqlscript.BaseName.StartsWith($sqlscriptConvention.prefix + $namingSeparator))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) SQL script prefix is not equals [$($sqlscriptConvention.prefix)$($namingSeparator)] for [$($sqlscript.BaseName)]"
            $Script:sqlscriptErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) SQL script prefix is correct"
            $Script:sqlscriptSuccessCount++
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
    elseif (-not (Test-Path (Join-Path $ArtifactPath "sqlscript")))
    {
        Write-Output "SQL Script found in artifact"
    }
    Write-Output "=============================================================================================="
}


#####################################################
# KQL SCRIPTS
#####################################################
# Retrieve all checks from naming covention config and then filter on KqlScript to get its validate value
[bool]$kqlScriptCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "KqlScript" }).validate

if ((Test-Path (Join-Path $ArtifactPath "kqlscript")) -and ($kqlScriptCheck))
{
    # Retrieve kqlscript prefix
    $kqlscriptConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "KqlScript" }

    # Retrieve all kqlscript files
    $artifactKqlScripts = Get-ChildItem -Path (Join-Path $ArtifactPath "kqlscript") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each kqlscript file
    foreach ($kqlscript in $artifactKqlScripts)
    {
        # Read file content to retrieve kqlscript JSON
        $kqlscriptContent = Get-Content $kqlscript.FullName | Out-String | ConvertFrom-Json

        # Determine kqlscript path within the Synapse Workspace for (showing only)
        $kqlscriptPath = "\"
        # If kqlscript is not in the root retrieve folder from JSON
        if (HasProperty -JsonObject $kqlscriptContent.properties -PropertyName "folder")
        {
            $kqlscriptPath = $kqlscriptPath + $kqlscriptContent.properties.folder.name.replace("/","\") + "\"
        }

        # kqlscript logging
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking KQL script [$($kqlscriptPath)$($kqlscript.BaseName)]"
        Write-Output "=============================================================================================="

        # Check kqlscript name prefix
        if (!$kqlscript.BaseName.StartsWith($kqlscriptConvention.prefix + $namingSeparator))
        {
            Write-Host "##vso[task.LogIssue type=error;]$([char]10007) KQL script prefix is not equals [$($kqlscriptConvention.prefix)$($namingSeparator)] for [$($kqlscript.BaseName)]"
            $Script:kqlscriptErrorCount++
        }
        else
        {
            Write-Output "$([char]10003) KQL script prefix is correct"
            $Script:kqlscriptSuccessCount++
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
    elseif (-not (Test-Path (Join-Path $ArtifactPath "kqlscript")))
    {
        Write-Output "No KQL Scripts found in artifact"
    }
    Write-Output "=============================================================================================="
}

#####################################################
# CHECK ALL RESOURCE POSTFIXES
#####################################################
# Retrieve all checks from naming covention config and then filter on Postfixes to get its validate value
[bool]$postfixCheck = ($namingConvention.Checks | Where-Object { $_.Type -eq "Postfixes" }).validate

if ($postfixCheck)
{
    # Assign all resources to the resources variable while checking on the _copy** postfixe
    $incorrectResources = Get-ChildItem -Path $ArtifactPath -Recurse -Filter *.json | Where-Object { $_.BaseName -match '_copy([1-9][0-9]?)$'} | Select-Object -Property FullName, BaseName

    # Count errors and succeeds
    [int]$Script:invalidPostfixErrorCount += ($incorrectResources | Measure-Object).Count
    [int]$Script:invalidPostfixSuccessCount += (Get-ChildItem -Path $ArtifactPath -Recurse -Filter *.json | Measure-Object).Count - ($incorrectResources | Measure-Object).Count

    Write-Output ""
    Write-Output "=============================================================================================="
    Write-Output "Invalid postfixes $(($incorrectResources | Measure-Object).Count)"
    Write-Output "=============================================================================================="
    # Loop through all resources with an invalid _copy* postfix
    foreach ($resource in $incorrectResources)
    {
        # Write all 'errors' to screen
        Write-Host "##vso[task.LogIssue type=error;]$([char]10007) Found $((Get-Item $resource.FullName).Directory.Name) resource [$($resource.BaseName)] with the _copy postfix"
    }
}

#####################################################
# SUMMARY
#####################################################
Write-Output ""
Write-Output "=============================================================================================="
Write-Output "Summary"
Write-Output "=============================================================================================="
LogSummary  -ValidationDisabled $pipelineCheck `
            -NumberOfErrors $Script:pipelineErrorCount `
            -NumberOfSucceeds $Script:pipelineSuccessCount `
            -ValidationName "Pipelines"
LogSummary  -ValidationDisabled $activityCheck `
            -NumberOfErrors $Script:activityErrorCount `
            -NumberOfSucceeds $Script:activitySuccessCount `
            -ValidationName "Activities"
LogSummary  -ValidationDisabled $notebookCheck `
            -NumberOfErrors $Script:notebookErrorCount `
            -NumberOfSucceeds $Script:notebookSuccessCount `
            -ValidationName "Notebooks"
LogSummary  -ValidationDisabled $linkedserviceCheck `
            -NumberOfErrors $Script:linkedserviceErrorCount `
            -NumberOfSucceeds $Script:linkedserviceSuccessCount `
            -ValidationName "Linked Services"
LogSummary  -ValidationDisabled $datasetCheck `
            -NumberOfErrors $Script:datasetErrorCount `
            -NumberOfSucceeds $Script:datasetSuccessCount `
            -ValidationName "Datasets"
LogSummary  -ValidationDisabled $triggerCheck `
            -NumberOfErrors $Script:triggerErrorCount `
            -NumberOfSucceeds $Script:triggerSuccessCount `
            -ValidationName "Triggers"
LogSummary  -ValidationDisabled $dataflowCheck `
            -NumberOfErrors $Script:dataflowErrorCount `
            -NumberOfSucceeds $Script:dataflowSuccessCount `
            -ValidationName "Dataflows"
LogSummary  -ValidationDisabled $sqlscriptCheck `
            -NumberOfErrors $Script:sqlscriptErrorCount `
            -NumberOfSucceeds $Script:sqlscriptSuccessCount `
            -ValidationName "SQL Scripts"
LogSummary  -ValidationDisabled $kqlscriptCheck `
            -NumberOfErrors $Script:kqlscriptErrorCount `
            -NumberOfSucceeds $Script:kqlscriptSuccessCount `
            -ValidationName "KQL Scripts"
LogSummary  -ValidationDisabled $postfixCheck `
            -NumberOfErrors $Script:invalidPostfixErrorCount `
            -NumberOfSucceeds $Script:invalidPostfixSuccessCount `
            -ValidationName "Invalid Postfixes"
Write-Output "=============================================================================================="
# Only show error count if there are errors
if (($pipelineErrorCount + $activityErrorCount + $notebookErrorCount + $linkedServiceErrorCount + $datasetErrorCount + $triggerErrorCount + $dataflowErrorCount + $sqlscriptErrorCount + $kqlscriptErrorCount + $invalidPostfixErrorCount) -gt 0)
{
    Write-Output "Number of errors found $($pipelineErrorCount + $activityErrorCount + $notebookErrorCount + $linkedServiceErrorCount + $datasetErrorCount + $triggerErrorCount + $dataflowErrorCount + $sqlscriptErrorCount + $kqlscriptErrorCount + $invalidPostfixErrorCount)"
    Write-Output "=============================================================================================="

    # Make sure DevOps knows the script failed
    exit 1
}
