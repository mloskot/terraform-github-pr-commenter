#!/bin/bash
# Collect outputs of Terraform command run for the (ordered) known layers
# and generate content of PR comment in Markdown,
# and return it via environment variable.
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <terraform command> <path to terraform command output files>"
    exit 1
fi
if [[ -z "$1" ]]; then
    echo "Missing terraform command"
    exit 1
fi
if [[ ! -d "$2" ]]; then
    echo "Missing path to terraform command output files"
    exit 1
fi

command="${1}"
logs_path="${2}"
logs_collected=0

echo -e "\033[34;1mINFO:\033[0m Rendering Terraform ${command} comment from ${logs_path}"
output="## Build ${BUILD_BUILDNUMBER}: Terraform ${command}\n\n"

for cmd_log in "${logs_path}"/*".${command}.txt"; do
    echo -e "\033[34;1mINFO:\033[0m Reading ${command} output from ${cmd_log}"
    # Extract name of known layer from e.g. dev_04-platform.validate.txt
    layer=$(basename "${cmd_log}")
    layer=$(echo "${layer}" | cut -d '_' -f 2 | cut -d . -f 1)
    raw_log=$(< "${cmd_log//$'│'/''}")
    # Render section for layer
    output+="### Layer: ${layer}\n\n"
    # shellcheck disable=SC2076
    if [[ "${raw_log}" =~ "Success! The configuration is valid." ]]; then
        output+="${raw_log}\n"
    else
        output+="<details><summary>Show</summary>\n\n<verbatim>\n${raw_log}\n</verbatim>\n</details>\n\n"
    fi
    ((logs_collected++))
done

echo -e "\033[34;1mINFO:\033[0m Exporting TERRAFORM_COMMAND_PR_COMMENT environment variable"
if [[ $logs_collected -gt 0 ]]; then
    #TERRAFORM_COMMAND_PR_COMMENT=$(echo -e "${output}")
    TERRAFORM_COMMAND_PR_COMMENT="${output}"
else
    TERRAFORM_COMMAND_PR_COMMENT=""
fi
export TERRAFORM_COMMAND_PR_COMMENT
