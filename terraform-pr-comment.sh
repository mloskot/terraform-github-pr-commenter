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
    echo -e "\033[31;1mERROR:\033[0m Missing terraform command"
    exit 1
fi
if [[ ! -d "$2" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing path to terraform command output files"
    exit 1
fi
if [[ -z "$3" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing build number"
    exit 1
fi

# TODO: Add more conversion methods
if command -v "iconv" &> /dev/null; then
    echo -e "\033[32;1mINFO:\033[0m Using iconv to escape comment content"
elif command -v "konwert" &> /dev/null; then
    echo -e "\033[32;1mINFO:\033[0m Using konwert to escape comment content"
else
    echo -e "\033[31;1mERROR:\033[0m Missing reliable Unicode to ASCII converter for the fancy Terraform output"
    exit 1
fi

function _escape_content
{
    if command -v "iconv" &> /dev/null; then
        echo "${1}" | iconv -c -f utf-8 -t ascii//TRANSLIT | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g'
    elif command -v "konwert" &> /dev/null; then
        echo "${1}" | konwert utf8-ascii | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | sed s/^\?//g
    fi
}

function _render_fmt
{
    if [[ ! -f "${1}" ]]; then
        return 1
    fi
    local raw_log
    raw_log=$(< "${1}")
    raw_log="${raw_log%%*( )}"
    if [[ -n "${raw_log}" ]]; then
        local esc_log
        esc_log=$(_escape_content "${raw_log}")
        # shellcheck disable=SC2028
        echo "<details><summary>Show</summary>\n\n\`\`\`diff\n${esc_log}\n\`\`\`\n</details>\n\n"
    else
        echo "Success! The files are well-formed."
    fi
}

function _render_validate
{
    if [[ ! -f "${1}" ]]; then
        return 1
    fi
    local raw_log
    raw_log=$(< "${1}")
    local esc_log
    esc_log=$(_escape_content "${raw_log}")
    if [[ -n "${esc_log}" ]]; then
        # shellcheck disable=SC2076
        if [[ "${esc_log}" =~ "Success! The configuration is valid." ]]; then
            # shellcheck disable=SC2028
            echo "${esc_log}\n"
        else
            # shellcheck disable=SC2028
            echo "<details><summary>Show</summary>\n\n\`\`\`\n${esc_log}\n\`\`\`\n</details>\n\n"
        fi
    fi
}

arg_command="${1}"
arg_logs_path="${2}"
arg_build_number="${3}"
logs_collected=0

echo -e "\033[32;1mINFO:\033[0m Rendering Terraform ${arg_command} comment from ${arg_logs_path}"
comment="## Build \`${arg_build_number}\`: Terraform \`${arg_command}\`\n\n"
# shellcheck disable=SC2045
for log_file in $(ls --sort=version "${arg_logs_path}"/*."${arg_command}".{log,txt} 2>/dev/null); do
    echo -e "\033[32;1mINFO:\033[0m Rendering ${arg_command} output from ${log_file}"
    # Render section title
    section=$(basename "${log_file}")
    section=$(echo "${section}" | cut -d '_' -f 2 | cut -d . -f 1)
    comment+="### Layer: \`${section}\`\n\n"
    # Render section content
    content=$(_render_"${arg_command}"  "${log_file}")
    if [[ -z "${content}" ]]; then
        set -e
        echo -e "\033[31;1mERROR:\033[0m Rendering ${arg_command} output failed"
        exit 1
    fi
    comment+="${content}"

    ((logs_collected++))
done
comment+="\n\n"

unset arg_command
unset arg_logs_path
unset arg_build_number

echo -e "\033[32;1mINFO:\033[0m Exporting TERRAFORM_COMMAND_PR_COMMENT environment variable"
if [[ $logs_collected -gt 0 ]]; then
    # GitHub API uses \r\n as line breaks in bodies
    # https://github.com/actions/runner/issues/1462#issuecomment-1030124116
    TERRAFORM_COMMAND_PR_COMMENT="${comment//\\n/%0D%0A}"
else
    TERRAFORM_COMMAND_PR_COMMENT=""
fi
unset logs_collected
unset comment

echo "${TERRAFORM_COMMAND_PR_COMMENT}"
export TERRAFORM_COMMAND_PR_COMMENT
