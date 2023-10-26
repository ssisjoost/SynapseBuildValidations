"""
This script retrieves a list of changed files from the latest Git commit,
filters for changed Jupyter notebooks, and then uses GPT-3 to review the code
within those notebooks. Feedback and suggested changes are printed to the console.
"""
import os
import subprocess
import pandas as pd
import sys
import openai
import json
import requests
from pathlib import Path

#Uncomment these lines if using a .env file for environment variables
#from dotenv import load_dotenv
#load_dotenv()

# Define the list of required environment variables
required_env_vars = ['synapse_root_folder', 'openai_api_type', 'openai_api_base', 'openai_api_version', 'openai_api_key',
                     'system_collectionuri', 'system_pullrequest_pullrequestid', 'system_teamproject', 'build_repository_id', 
                     'system_pullrequest_TargetBranch', 'system_pullrequest_sourcebranch', 'system_accesstoken']

# Check for missing environment variables and exit if any are missing
missing_vars = [var for var in required_env_vars if not os.getenv(var)]
if missing_vars:
    print(f"The following required environment variables are missing: {', '.join(missing_vars)}")
    sys.exit(1)

# set required environment variables for git branch compare
target_branch = os.getenv('system_pullrequest_TargetBranch').replace("refs/heads/", "origin/")
source_branch = os.getenv('system_pullrequest_sourcebranch').replace("refs/heads/", "origin/")

# Set required environment variables
synapse_root_folder = os.getenv('synapse_root_folder')
# Set required environment variables for chatgpt api call
openai.api_type = os.getenv('openai_api_type')
openai.api_base = os.getenv('openai_api_base')
openai.api_version = os.getenv('openai_api_version')
openai.api_key = os.getenv('openai_api_key')
# Set required environment variables for pull request api call
system_collectionuri = os.getenv('system_collectionuri')
system_pullrequest_pullrequestid = os.getenv('system_pullrequest_pullrequestid')
system_teamproject = os.getenv('system_teamproject')
build_repository_id = os.getenv('build_repository_id')
system_accesstoken = os.getenv('system_accesstoken')

##############################################################
# GIT changes of latest commit to dataframe
##############################################################

def get_changed_files(): 
    """
    Get a list of all changes in the latest Git commit.
    The function assumes that Git is available in the environment path.
    """
    git_command =  ["git", "diff", f"{target_branch}..{source_branch}","--name-only", "--diff-filter=AM"]
    git_command_result  = subprocess.run(git_command, capture_output=True, text=True)
    # Check if command executed successfully
    if git_command_result.returncode != 0:
        raise Exception(f"Git command failed with error code {git_command_result.returncode}. Error message: {git_command_result.stderr}")
    # Convert response to dataframe
    # Convertion assumes the following folder structure:
    #  ../{synapse_dir_path}/notebook/{folders/files}
    git_output_rows = git_command_result.stdout.split("\n")

    return git_output_rows

# Try to fetch the list of changed files
try:
    changed_files_list = get_changed_files()
except Exception as e:
    print(f"An error occurred: {e}")
    sys.exit(1)

# define path to folder with notebooks
notebook_path = f"{synapse_root_folder}/notebook" 
# Filter for changed notebooks
filtered_changed_files_list = [item for item in changed_files_list if item.startswith(notebook_path)]
#Extract filenames to a list
filtered_changed_files_list = [Path(item).name for item in filtered_changed_files_list]

##############################################################
# Extract code from notebook files for changed notebook files
##############################################################

# Initialize an empty list to hold notebook information
notebook_json_extract = []

# Loop through each changed file based on DataFrame
for file in filtered_changed_files_list:
    # Construct the full path of the file
    file_path = os.path.join(os.getcwd(), synapse_root_folder, "notebook", file)

    # Check if the file is a JSON file
    if file.endswith('.json'):
        # Open the JSON file for reading
        with open(file_path, 'r') as json_file:
            # Load JSON content into a Python dictionary
            json_content = json.load(json_file)
            
            # Get the notebook name
            notebook_name = json_content.get("name")
            
            # Get the folder name if it exists, otherwise set to None
            if "folder" in json_content.get("properties"):
                notebook_folder = json_content.get("properties").get("folder").get("name")
            else:
                notebook_folder = None
            
            # Initialize an empty string to store notebook code
            notebook_code = ""

            # Loop through each cell in the notebook
            for cell in json_content.get("properties").get("cells"):
                
                # Get the source and cell type of the current cell
                source = cell.get("source")
                cell_type = cell.get("cell_type")
                
                # Convert source list to string while handling escape characters
                source = [line.replace('"', '').replace('\r\n', '\n') for line in source]
                
                # If the cell is a markdown cell, prefix each line with a '#'
                if cell_type == "markdown":
                    source = '#'.join(source)
                    source = '#' + source
                else:
                    source = ''.join(source)
                
                # Append source code to notebook_code
                notebook_code += source + " \n" 
    
            # Append notebook details to the list
            notebook_json_extract.append([notebook_name, notebook_folder, notebook_code])

# Create a DataFrame to store notebook details
notebook_df = pd.DataFrame(notebook_json_extract, columns=["notebook_name", "notebook_folder", "notebook_code"])

# Add empty columns for feedback
notebook_df['feedback_status'] = None
notebook_df['feedback_message'] = None
notebook_df['feedback_code'] = None

##############################################################
# Pass notebookcells to gpt to check for feedback
##############################################################

def get_gpt_response(row):
    """
    Send notebook code to GPT-3 model for review.
    Updates the DataFrame row with feedback information.
    """
    
    # Define the system's role string for GPT-3
    content_system_string = """You are a senior programmer tasked with reviewing code in Synapse notebooks.
                        The code should be in SQL or Python. Your goal is to assess the code and only provide a feedback_message when the code can be improved.
                        This includes suggestions for how the code can be improved. 
                        """
    
    # Define the assistant's role string for GPT-3
    content_assistant_string = """Your response is given in a structured JSON format followed with the text: #STOP# 
                        - Feedback_status: 
                        - Set to 0 if the code is perfect and needs no changes. 
                        - Set to 1 if the code requires improvements. 
                        - Feedback_message: 
                        - Populate ONLY if Feedback_code is 1, with a description of what can be improved. 
                        - Make None if Feedback_code is 0. 
                        - Feedback_code: 
                        - Populate ONLY if Feedback_code is 1, with code examples for how the code can be improved. 
                        - Make None if Feedback_code is 0. 
                        For example: 
                        {\"Feedback_status\":0,\"Feedback_message\": null,\"Feedback_code\": null} #STOP# 
                        {\"Feedback_status\":1,\"Feedback_message\": \"This is where the improvement message is placed\",\"Feedback_code\": \"<Code block with the improvements applied to the code>\"}} #STOP# 
                        """
    
    # Format the user's role string with the code to be reviewed
    content_user_string = f"""
                        Assess the following code and respond with a structured json and no additional text 
                        ###Start code lines###    
                        {row['notebook_code']} 
                        ###End code lines###"""
    
    try:
        # Send the prompt to the GPT-3 API and collect the response
        response = openai.ChatCompletion.create(
            engine="GPT35",  # Specify the GPT-3.5 model
            messages = [
                {"role": "system", "content": f"{content_system_string}"},
                {"role": "assistant", "content": f"{content_assistant_string}"},
                {"role": "user", "content": f"{content_user_string}"}
            ],
            temperature=0,
            max_tokens=6000,
            top_p=0.99,
            frequency_penalty=0,
            presence_penalty=0,
            stop=["#STOP#"]
        )
        
        # Parse the JSON response to extract the message content
        response_text = json.loads(response['choices'][0]['message']['content'])
        
    except Exception as e:
        # Print error message and return the original row if an error occurs
        print(f"An error occurred: {e}")
        return row
    
    # Update the DataFrame row with feedback information
    row['feedback_status'] = response_text.get("Feedback_status")
    row['feedback_message'] = response_text.get("Feedback_message")
    row['feedback_code'] = response_text.get("Feedback_code")
    
    return row  # Return the updated row

# Apply the get_gpt_response function to each row in the notebook_json_extract dataframe    
notebook_df = notebook_df.apply(lambda x : get_gpt_response(x), axis=1)

##############################################################
# Communicate feedback
##############################################################

def add_comment_to_azure_pull_request(comment: str) -> bool:
    """
    Adds a comment to an Azure DevOps Pull Request.
    """
    
    # Construct the URL for Azure DevOps Pull Request threads
    url = f"{system_collectionuri}{system_teamproject}/_apis/git/repositories/" \
          f"{build_repository_id}/pullRequests/{system_pullrequest_pullrequestid}" \
          "/threads?api-version=6.0"
    
    # Prepare the headers for the HTTP request, including authorization
    headers = {
        "content-type": "application/json",
        "Authorization": f"BEARER {system_accesstoken}"
    }
    
    try:
        # Prepare data payload for POST request
        data = {
            "comments": [
                {
                    "parentCommentId": 0,
                    "content": comment,
                    "commentType": 1
                }
            ],
            "status": 1
        }
        
        # Execute POST request
        r = requests.post(url=url, json=data, headers=headers)
        r.raise_for_status()  # Raise HTTPError for bad responses
        return True
    except requests.HTTPError as http_err:
        # Print HTTP error and server response for debugging
        print(f"HTTP error occurred: {http_err}")
        print(r.json())
        return False
    except Exception as err:
        # Print other types of errors
        print(f"An error occurred: {err}")
        return False

# Loop through notebook DataFrame where feedback_status is 1 (indicating code improvements)
for index, row in notebook_df.loc[notebook_df['feedback_status'] == 1].iterrows():
    
    # Print initial separator to console (only once)
    if index == 0:
        print("----------------------------------------------------")
    
    # Print notebook details and GPT feedback to console
    print(f'Notebook script: "{row["notebook_folder"]}/{row["notebook_name"]}"')
    print("----------------------------------------------------")
    print(">> GPT Feedback:")
    print('\n'.join(["\t" + line for line in row["feedback_message"].split('\n')]))
    print(">> Suggested code:")
    print('\n'.join(["\t" + line for line in row["feedback_code"].split('\n')]))
    print("----------------------------------------------------")

    # Prepare Pull Request comment string
    pr_comment = ""
    pr_comment += f'# Notebook script: "{row["notebook_folder"]}/{row["notebook_name"]}"' + " \n\n"
    pr_comment += "**>> GPT Feedback:" + "** \n"
    pr_comment += "\n".join([line for line in row["feedback_message"].split('\n')]) + "\n"
    pr_comment += "**>> Suggested code:" + "** \n"
    pr_comment += "``` \n"
    pr_comment += "\n".join([line for line in row["feedback_code"].split('\n')]) + "\n"
    pr_comment += "```"
    
    # Call function to add comment to Azure Pull Request
    add_comment_to_azure_pull_request(pr_comment)
