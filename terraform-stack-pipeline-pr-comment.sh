#!/bin/bash
# Collect outputs of Terraform command run for the (ordered) known layers
# and generate content of PR comment in Markdown,
# and return it via environment variable.
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <terraform command> <path to terraform command output files> <build number>"
    exit 1
fi
if [[ -z "$1" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing terraform command."
    exit 1
fi
if [[ ! -d "$2" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing path to terraform command output files."
    exit 1
fi
if [[ -z "$3" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing build number."
    exit 1
fi

command="${1}"
logs_path="${2}"
build_number="${3}"
logs_collected=0

echo -e "\033[32;1mINFO:\033[0m Rendering Terraform ${command} comment from ${logs_path}"
comment="## Build ${build_number}: Terraform ${command}\n\n"
comment="<verbatim>"
for cmd_log in "${logs_path}"/*".${command}.txt"; do
    echo -e "\033[32;1mINFO:\033[0m Reading ${command} output from ${cmd_log}"
    # Extract name of known layer from e.g. dev_04-platform.validate.txt
    layer=$(basename "${cmd_log}")
    layer=$(echo "${layer}" | cut -d '_' -f 2 | cut -d . -f 1)
    raw_log=$(< "${cmd_log}")
    # Render section for layer
    #comment+="### Layer: ${layer}\n\n"
    comment+=$(echo "${raw_log}" | iconv -c -f utf-8 -t ascii | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
    # shellcheck disable=SC2076
    # if [[ "${raw_log}" =~ "Success! The configuration is valid." ]]; then
    #     comment+="${raw_log}\n"
    # else
    #     comment+="<details><summary>Show</summary>\n\n<verbatim>\n${raw_log}\n</verbatim>\n</details>\n\n"
    # fi
    ((logs_collected++))
    if [[ $logs_collected -gt 1 ]]; then
        break
    fi
done
comment+="</verbatim>"

echo -e "\033[32;1mINFO:\033[0m Exporting TERRAFORM_COMMAND_PR_COMMENT environment variable"
if [[ $logs_collected -gt 0 ]]; then
    TERRAFORM_COMMAND_PR_COMMENT="${comment}"
else
    TERRAFORM_COMMAND_PR_COMMENT=""
fi

# if command -v "iconv" &> /dev/null; then
#     echo -e "\033[32;1mINFO:\033[0m Running iconv to escape comment content"
#     TERRAFORM_COMMAND_PR_COMMENT=$(echo "$RESULT_PR_COMMENT" | iconv -c -f utf-8 -t ascii | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
# else
#     echo -e "\033[32;1mINFO:\033[0m iconv not found, escaping comment content using simpler methods"
# fi

export TERRAFORM_COMMAND_PR_COMMENT
