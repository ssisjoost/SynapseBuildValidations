# Naming Convention validation for Azure Synapse Workspaces
This Build Validation checks the naming conventions for your **Azure Synapse Workspace**. Naming conventions make your work more readable and understandable, but also makes the logging information way more comprehensible. In one glance you will immediately see which part of Synapse is affected by the error message. For example that the error is for a Linked Service pointing to parquet files in an Azure Storage Account. Above all it looks more professional and it shows you took the extra effort to make everything consistant.

There are multiple Naming Conventions, most of them are for Azure Data Factory like this one from [Erwin de Kreuk](https://erwindekreuk.com/2020/07/azure-data-factory-naming-conventions/). ADF and Synapse use almost the same items and are therefor interchangable. In a JSON config file you can specify your own naming conventions. Read this [blog post](https://microsoft-bitools.blogspot.com/2023/05/synapse-automatically-check-naming.html) on how to implement this validation in your Azure DevOps project.

## TODO
Suggestions for further improvements are below. Please suggest your own.
- [x] Add folder information for Data Flows, SQL Scripts and KQL Scripts
- [ ] Naming conventions within Data Flows (please share yours)
- [ ] Option to skip or ignore certain parts from Synapse if you for example don't have/want a naming convention within the Data Flows
- [ ] Option to change some of the errors into warnings for when you just want to test the basics
- [ ] Option to allow a certain percentage of errors before failing the validation
- [ ] Option to only show the mistakes and ignore everything that is correct
- [ ] Take Linked Service into consideration to determine Data Set names
- [x] Look for items ending on _copy1 or _copy2 on resource level
- [x] Look for items ending on _copy1 or _copy2 on activity level
- [ ] Look for bad defaults settings like the 7 day timeout
- [ ] Look empty descriptions
- [ ] Make it available for ADF
- [ ] Improve feedback and clarity in logs


## Versions
- 0.01 - Check Pipeline prefixes
- 0.02 - Check Activity prefixes
- 0.03 - Move naming conventions to JSON config
- 0.04 - Check Linked Service and Datasets prefixes
- 0.05 - Adding Parameters to script and adding TestScript.ps1 for testing
- 0.06 - Include types for naming conventions for Linked Service and Datasets prefixes
- 0.07 - Check Notebook, SQL Script and KQL Script prefixes
- 0.08 - Adding ValidateNamingConventions.yml file to create DevOps pipeline
- 0.09 - Adding _copy check on resource level
