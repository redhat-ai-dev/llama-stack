#
#
# Copyright Red Hat
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import difflib
import sys
import requests
import re
import argparse
from ruamel.yaml import YAML

URL = "https://raw.githubusercontent.com/redhat-developer/rhdh-plugins/refs/heads/main/workspaces/lightspeed/plugins/lightspeed-backend/src/prompts/rhdh-profile.py"
RUN_PATH = "../../run.yaml"

def fetch_and_load(url: str) -> dict[str, str]:
    """
    Fetches the contents from the upstream URL and returns a dictionary with the
    desired prompt templates.
    """
    response = requests.get(url)
    response.raise_for_status()
    content = response.text
    validator_pattern = r"QUESTION_VALIDATOR_PROMPT_TEMPLATE\s*=\s*f?(['\"]{3})(.*?)\1"
    rejection_pattern = r"INVALID_QUERY_RESP\s*=\s*(['\"]{3})(.*?)\1"
    validator_match = re.search(validator_pattern, content, re.DOTALL)
    rejection_match = re.search(rejection_pattern, content, re.DOTALL)
    if not validator_match:
        raise ValueError("QUESTION_VALIDATOR_PROMPT_TEMPLATE not found")
    if not rejection_match:
        raise ValueError("INVALID_QUERY_RESP not found")

    resp_dict = {}
    resp_dict["validator_prompt"] = validator_match.group(2)
    resp_dict["invalid_resp"] = rejection_match.group(2)
    return resp_dict

def replace_values(prompt: str) -> str:
    """
    Replaces templated values to ones used with the safety shield.
    """
    VALUES_TO_REPLACE = {
        "{SUBJECT_REJECTED}": "${rejected}",
        "{SUBJECT_ALLOWED}": "${allowed}",
        "{{query}}": "${message}",
    }
    new_prompt = prompt
    for replacee, replacement in VALUES_TO_REPLACE.items():
        new_prompt = new_prompt.replace(replacee, replacement)
    return new_prompt

def is_valid(incoming_prompt: dict[str,str], current_prompt: dict[str,str]) -> bool:
    """
    Validates if the contents of the run.yaml file are equivalent to
    the upstream.
    """
    validator_check = incoming_prompt.get("validator_prompt").strip("\n") == current_prompt.get("validator_prompt").strip("\n")
    invalid_resp_check = incoming_prompt.get("invalid_resp").strip("\n") == current_prompt.get("invalid_resp").strip("\n")
    return validator_check and invalid_resp_check

def fetch_current_prompts() -> dict[str,str]:
    """
    Grabs the question validation prompt templates for both validation and
    rejected response from the local run.yaml file.
    """
    yaml = YAML()
    yaml.preserve_quotes = True
    resp_dict = {}
    with open(RUN_PATH, "r", encoding="utf-8") as f:
        data = yaml.load(f)
    safety_providers = data.get("providers").get("safety")
    for provider in safety_providers:
        if provider.get("provider_id") == "lightspeed_question_validity":
            resp_dict["validator_prompt"] = provider.get("config").get("model_prompt")
            resp_dict["invalid_resp"] = provider.get("config").get("invalid_question_response")
            return resp_dict

def update_yaml_file(incoming_prompts: dict[str,str], file_path: str) -> None:
    """
    Updates the local run.yaml file with the upstream prompt templates.
    """
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    with open(file_path, "r", encoding="utf-8") as f:
        data = yaml.load(f)

    safety_providers = data.get("providers").get("safety")
    for provider in safety_providers:
        if provider.get("provider_id") == "lightspeed_question_validity":
            provider["config"]["model_prompt"] = incoming_prompts.get("validator_prompt").strip("\n")
            provider["config"]["invalid_question_response"] = incoming_prompts.get("invalid_resp").strip("\n")
            break

    with open(file_path, "w", encoding="utf-8") as f:
        yaml.dump(data, f)

def output_diff(incoming_prompts: dict[str, str], current_prompts: dict[str, str]) -> None:
    """
    Outputs the difference between the upstream prompt templates and the
    local run.yaml.
    """
    print("Validation Prompt")
    print("-----")
    diff_validator = difflib.unified_diff(
        current_prompts["validator_prompt"].splitlines(),
        incoming_prompts["validator_prompt"].splitlines(),
        fromfile="run.yaml",
        tofile="upstream",
        lineterm=""
    )
    print("\n".join(diff_validator))

    print("Invalid Response Prompt")
    print("-----")
    diff_invalid = difflib.unified_diff(
        current_prompts["invalid_resp"].splitlines(),
        incoming_prompts["invalid_resp"].splitlines(),
        fromfile="run.yaml",
        tofile="upstream",
        lineterm=""
    )
    print("\n".join(diff_invalid))

def main(args: argparse.Namespace):
    """
    Entrypoint to the program.
    """
    incoming_prompts = fetch_and_load(URL)
    replaced_prompt = replace_values(incoming_prompts.get("validator_prompt"))
    incoming_prompts["validator_prompt"] = replaced_prompt
    current_prompts = fetch_current_prompts()

    if args.type == "validate":
        if is_valid(incoming_prompts, current_prompts):
            print("Contents are valid.")
            sys.exit(0)
        print("Contents invalid.")
        output_diff(incoming_prompts, current_prompts)
        sys.exit(1)
    elif args.type == "update":
        update_yaml_file(incoming_prompts, RUN_PATH)
        print("Contents updated.")
    else:
        print("Type incorrect.")
        return

if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(
        description="Tool for validating and/or updating the question validation portions of the Llama Stack config."
    )

    parser.add_argument(
        "-t", "--type", help="Type of action you want to perform. Can be 'validate' or 'update' to either validate or update the contents of run.yaml with the upstream."
    )
    args = parser.parse_args()

    main(args)
