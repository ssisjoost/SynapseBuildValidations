# Branch validation for Pull Requests
Validating source and target branches to avoid accidentily skipping branches because you messed up when creating the pull request. A four-eyes principle is always the first step, but a script that automatically checks the branches when creating the pull request is even better. Read this [blog post](https://microsoft-bitools.blogspot.com/2023/04/devops-build-validation-to-check.html) on how to implement this validation in your Azure DevOps project.

## TODO
Suggestions for further improvements are below. Please suggest your own.
- [ ] Naming convention check for Feature branches
- [ ] Implement support for release strategies that use a branch for each release, for example: release/v1.0, release/v1.1...)

## Versions
- 0.01 - Intial version
- 0.02 - Replace hardcoded branch names with array of branches to reduce the if statements and to easily change the branch names
