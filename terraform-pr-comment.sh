#!/bin/bash
# Collect output of given Terraform command from log files in given location
# and render it in Markdown for PR comment,
# then return it via exported environment variable.
#
# The script renders single comment titled with given build number and command.
# The script supports multiple logs from multiple runs of terraform <command>,
# e.g. separate run per directory, and each log is rendered as a separate section.
#
# Log file name format is: <00N>_<title>.<command>.{log,txt}
#
# <00N> part controls order in which files are read
# <title> part is used as heading of section for given log
# <command> used in the comment title together with given build number
#
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
# shellcheck disable=SC2045
for log_file in $(ls --sort=version "${logs_path}"/*."${command}".{log,txt}); do
    echo -e "\033[32;1mINFO:\033[0m Reading ${command} output from ${log_file}"
    # Extract name of known layer from e.g. dev_04-platform.validate.txt
    layer=$(basename "${log_file}")
    layer=$(echo "${layer}" | cut -d '_' -f 2 | cut -d . -f 1)
    raw_log=$(< "${log_file}")
    raw_log=$(echo "${raw_log}" | iconv -c -f utf-8 -t ascii//TRANSLIT | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
    # Render section for layer
    comment+="### Layer: ${layer}\n\n"
    # shellcheck disable=SC2076
    if [[ "${raw_log}" =~ "Success! The configuration is valid." ]]; then
        comment+="${raw_log}\n"
    else
        comment+="<details><summary>Show</summary>\n\n<pre>\n${raw_log}\n</pre>\n</details>\n\n"
    fi
    ((logs_collected++))
done
comment+="\n\n"

echo -e "\033[32;1mINFO:\033[0m Exporting TERRAFORM_COMMAND_PR_COMMENT environment variable"
if [[ $logs_collected -gt 0 ]]; then
    # GitHub API uses \r\n as line breaks in bodies
    # https://github.com/actions/runner/issues/1462#issuecomment-1030124116
    TERRAFORM_COMMAND_PR_COMMENT="${comment//\\n/%0D%0A}"
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
