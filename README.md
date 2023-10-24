# SynapseBuildValidations
Various build validation for when working with Azure Synapse Workspaces in DevOps. Adding automatic validations will improve the quality of your work and reduce human errors, although some co-workers might find it quite annoying. Feel free to suggest improvements for existing validation or for new validations.

## Naming Convention validation for Azure Synapse Workspaces
This Build Validation checks the naming conventions for your **Azure Synapse Workspace**. Naming conventions make your work more readable and understandable, but also makes the logging information way more comprehensible. In one glance you will immediately see which part of Synapse is affected by the error message. For example that the error is for a Linked Service pointing to parquet files in an Azure Storage Account. Above all it looks more professional. [More Details](/Naming%20Convention%20validation%20for%20Synapse)

## Branch validation for Pull Requests
Validating source and target branches to avoid accidentily skipping branches because you messed up when creating the pull request. A four-eyes principle is always the first step, but a script that automatically checks the branches when creating the pull request is even better. [More Details](/Branch%20validation%20for%20Pull%20Requests)

## Code review through a GPT model for Pull Requests
Use a GPT model to review changed synapse notebooks and provide suggestions for improvement. The GPT model is instructed to respond as a senior engineer and provide textual feedback of what can be improved. Addtionally the model provides code suggestions. [More Details](/GPT%20code%20review%20for%20Pull%20Request)
