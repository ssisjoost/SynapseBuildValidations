# Code review through a GPT model for Pull Requests
Use a GPT model to review changed synapse notebooks and provide suggestions for improvement. The GPT model is instructed to respond as a senior engineer and provide textual feedback of what can be improved. Addtionally the model provides code suggestions. Read this [blog post]([https://microsoft-bitools.blogspot.com/2023/10/review-synapse-notebooks-with-your-own.html](https://microsoft-bitools.blogspot.com/2023/10/review-synapse-notebooks-with-your-gpt.html)) on how to implement this validation in your Azure DevOps project.

## debugging
The .env file (in CICD/Python/.env) serves as a way to set the environment variables when you want to test the get_GPT_feedback.py script.
Change the values in the .en file to your specifications to make the get_GPT_feedback.py file run locally

## TODO
Suggestions for further improvements are below. Please suggest your own.
- [ ] Improve the prompt so the stop command is no longer needed to cut of the prompt response
- [ ] Generaly improve the prompt for better and more specific feedback (I'd love to learn from your experiences) 
- [ ] Better handling of multipe languages. E.g. provide the language setting to the GPT model to get a better response.
- [ ] Move the prompt string from the get_GPT_feedback.py script to seperate files to make them more maintainable.

## Versions
- 1.0 - Intial version
