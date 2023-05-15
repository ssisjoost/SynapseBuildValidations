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
    #$isValidJson = Get-Content $NamingConventionPath -Raw | Test-Json
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
#####################################################
# END Functions
#####################################################

# Retrieve naming separator from naming convention config
[string]$namingSeparator = $namingConvention.NamingSeparator

#####################################################
# PIPELINES & ACTIVITIES
#####################################################
if (Test-Path (Join-Path $ArtifactPath "pipeline"))
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

        #####################################################
        # ACTIVITIES
        #####################################################
        LoopActivities  -LevelName $pipeline.BaseName `
                        -LevelNumber 1 `
                        -Activities $pipelineContent.properties.activities
    }
}
else
{
    Write-Output ""
    Write-Output "=============================================================================================="
    Write-Output "No pipelines found in artifact"
    Write-Output "=============================================================================================="
}



#####################################################
# NOTEBOOKS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "notebook"))
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
    Write-Output "No notebooks found in artifact"
    Write-Output "=============================================================================================="
}



#####################################################
# LINKED SERVICES
#####################################################
if (Test-Path (Join-Path $ArtifactPath "linkedService"))
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
    Write-Output "No linked services found in artifact"
    Write-Output "=============================================================================================="
}





#####################################################
# DATASETS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "dataset"))
{
    # Retrieve linked service prefix
    $datasetConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "dataset" }

    # Retrieve all Linkes Service files
    $artifactDatasets = Get-ChildItem -Path (Join-Path $ArtifactPath "dataset") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each linked service file
    foreach ($dataset in $artifactDatasets)
    {
        # Read file content to retrieve pipeline JSON
        $datasetContent = Get-Content $dataset.FullName | Out-String | ConvertFrom-Json

        # Get type of Linked Service
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
    Write-Output "No datasets found in artifact"
    Write-Output "=============================================================================================="
}




#####################################################
# TRIGGERS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "trigger"))
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
    Write-Output "No triggers found in artifact"
    Write-Output "=============================================================================================="
}

#####################################################
# DATAFLOWS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "dataflow"))
{
    # Retrieve dataflow prefix
    $dataflowConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "Dataflow" }

    # Retrieve all Linkes Service files
    $artifactDataflows = Get-ChildItem -Path (Join-Path $ArtifactPath "dataflow") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each Triggers file
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

        # Dataflow loggin
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking dataflow [$($dataflowPath)$($dataflow.BaseName)]"
        Write-Output "=============================================================================================="

        # Check trigger name prefix
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
    Write-Output "No dataflows found in artifact"
    Write-Output "=============================================================================================="
}

#####################################################
# SQL SCRIPTS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "sqlscript"))
{
    # Retrieve dataflow prefix
    $sqlscriptConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "SqlScript" }

    # Retrieve all Linkes Service files
    $artifactSqlScripts = Get-ChildItem -Path (Join-Path $ArtifactPath "sqlscript") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each Triggers file
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

        # Sql Script loggin
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking dataflow [$($sqlscriptPath)$($sqlscript.BaseName)]"
        Write-Output "=============================================================================================="

        # Check sql script name prefix
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
    Write-Output "No sql scripts found in artifact"
    Write-Output "=============================================================================================="
}


#####################################################
# KQL SCRIPTS
#####################################################
if (Test-Path (Join-Path $ArtifactPath "kqlscript"))
{
    # Retrieve dataflow prefix
    $kqlscriptConvention = $namingConvention.Prefixes | Where-Object { $_.Type -eq "KqlScript" }

    # Retrieve all Linkes Service files
    $artifactKqlScripts = Get-ChildItem -Path (Join-Path $ArtifactPath "kqlscript") -Filter *.json | Select-Object -Property FullName, BaseName

    # Loop through each Triggers file
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

        # Kql Script loggin
        Write-Output ""
        Write-Output "=============================================================================================="
        Write-Output "Checking KQL script [$($kqlscriptPath)$($kqlscript.BaseName)]"
        Write-Output "=============================================================================================="

        # Check kql script name prefix
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
    Write-Output "No kql scripts found in artifact"
    Write-Output "=============================================================================================="
}


#####################################################
# CHECK ALL RESOURCE POSTFIXES
#####################################################
# Assign all resources to the resources variable while checking on the _copy** postfixe
$incorrectResources = Get-ChildItem -Path $ArtifactPath -Recurse -Filter *.json | Where-Object { $_.BaseName -match '_copy([1-9][0-9]?)$'} | Select-Object -Property FullName, BaseName

# Count errors and succeeds
[int]$Script:invalidPostfixErrorCount = ($incorrectResources | Measure-Object).Count
[int]$Script:invalidPostfixSuccessCount = (Get-ChildItem -Path $ArtifactPath -Recurse -Filter *.json | Measure-Object).Count - ($incorrectResources | Measure-Object).Count

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

#####################################################
# SUMMARY
#####################################################
Write-Output ""
Write-Output "=============================================================================================="
Write-Output "Summary"
Write-Output "=============================================================================================="

if (($pipelineErrorCount + $pipelineSuccessCount) -eq 0)
{
    Write-Output "Pipelines       : no pipelines found"
}
else
{
    Write-Output "Pipelines       : $($Script:pipelineErrorCount) errors out of $($Script:pipelineErrorCount + $Script:pipelineSuccessCount) - $([Math]::Round(($Script:pipelineErrorCount / ($Script:pipelineErrorCount + $Script:pipelineSuccessCount) * 100), 2))%"
}
if (($activityErrorCount + $activitySuccessCount) -eq 0)
{
    Write-Output "Activities      : no activities found"
}
else
{
    Write-Output "Activities      : $($Script:activityErrorCount) errors out of $($Script:activityErrorCount + $Script:activitySuccessCount) - $([Math]::Round(($Script:activityErrorCount / ($Script:activityErrorCount + $Script:activitySuccessCount) * 100), 2))%"
}
if (($notebookErrorCount + $notebookSuccessCount) -eq 0)
{
    Write-Output "Notebooks       : no notebooks found"
}
else
{
    Write-Output "Notebooks       : $($Script:notebookErrorCount) errors out of $($Script:notebookErrorCount + $Script:notebookSuccessCount) - $([Math]::Round(($Script:notebookErrorCount / ($Script:notebookErrorCount + $Script:notebookSuccessCount) * 100), 2))%"
}
if (($linkedServiceErrorCount + $linkedServiceSuccessCount) -eq 0)
{
    Write-Output "LinkedServices  : no linked services found" # should not occur since there are two by default that cannot be deleted
}
else
{
    Write-Output "LinkedServices  : $($Script:linkedServiceErrorCount) errors out of $($Script:linkedServiceErrorCount + $Script:linkedServiceSuccessCount) - $([Math]::Round(($Script:linkedServiceErrorCount / ($Script:linkedServiceErrorCount + $Script:linkedServiceSuccessCount) * 100), 2))%"
}
if (($datasetErrorCount + $datasetSuccessCount) -eq 0)
{
    Write-Output "Datasets        : no datasets found"
}
else
{
    Write-Output "Datasets        : $($Script:datasetErrorCount) errors out of $($Script:datasetErrorCount + $Script:datasetSuccessCount) - $([Math]::Round(($Script:datasetErrorCount / ($Script:datasetErrorCount + $Script:datasetSuccessCount) * 100), 2))%"
}
if (($triggerErrorCount + $triggerSuccessCount) -eq 0)
{
    Write-Output "Triggers        : no triggers found"
}
else
{
    Write-Output "Triggers        : $($Script:triggerErrorCount) errors out of $($Script:triggerErrorCount + $Script:triggerSuccessCount) - $([Math]::Round(($Script:triggerErrorCount / ($Script:triggerErrorCount + $Script:triggerSuccessCount) * 100), 2))%"
}
if (($dataflowErrorCount + $dataflowSuccessCount) -eq 0)
{
    Write-Output "Dataflows       : no dataflows found"
}
else
{
    Write-Output "Dataflows       : $($Script:dataflowErrorCount) errors out of $($Script:dataflowErrorCount + $Script:dataflowSuccessCount) - $([Math]::Round(($Script:dataflowErrorCount / ($Script:dataflowErrorCount + $Script:dataflowSuccessCount) * 100), 2))%"
}
if (($sqlscriptErrorCount + $sqlscriptSuccessCount) -eq 0)
{
    Write-Output "SQLScripts      : no sql scripts found"
}
else
{
    Write-Output "SQLScripts      : $($Script:sqlscriptErrorCount) errors out of $($Script:sqlscriptErrorCount + $Script:sqlscriptSuccessCount) - $([Math]::Round(($Script:sqlscriptErrorCount / ($Script:sqlscriptErrorCount + $Script:sqlscriptSuccessCount) * 100), 2))%"
}
if (($kqlscriptErrorCount + $kqlscriptSuccessCount) -eq 0)
{
    Write-Output "KQLScripts      : no kql scripts found"
}
else
{
    Write-Output "KQLScripts      : $($Script:kqlscriptErrorCount) errors out of $($Script:kqlscriptErrorCount + $Script:kqlscriptSuccessCount) - $([Math]::Round(($Script:kqlscriptErrorCount / ($Script:kqlscriptErrorCount + $Script:kqlscriptSuccessCount) * 100), 2))%"
}
if ($invalidPostfixErrorCount -eq 0)
{
    Write-Output "Invalid Postfix : no incorrect postfixes found"
}
else
{
    Write-Output "Invalid Postfix : $($Script:invalidPostfixErrorCount) errors out of $($Script:invalidPostfixErrorCount + $Script:invalidPostfixSuccessCount) - $([Math]::Round(($Script:invalidPostfixErrorCount / ($Script:invalidPostfixErrorCount + $Script:invalidPostfixSuccessCount) * 100), 2))%"
}

Write-Output "=============================================================================================="
if (($pipelineErrorCount + $activityErrorCount + $notebookErrorCount + $linkedServiceErrorCount + $datasetErrorCount + $triggerErrorCount + $dataflowErrorCount + $sqlscriptErrorCount + $kqlscriptErrorCount + $invalidPostfixErrorCount) -gt 0)
{
    Write-Output "Number of errors found $($pipelineErrorCount + $activityErrorCount + $notebookErrorCount + $linkedServiceErrorCount + $datasetErrorCount + $triggerErrorCount + $dataflowErrorCount + $sqlscriptErrorCount + $kqlscriptErrorCount + $invalidPostfixErrorCount)"
    Write-Output "=============================================================================================="

    # Make sure DevOps knows the script failed
    exit 1
}
