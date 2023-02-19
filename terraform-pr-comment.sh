#!/bin/bash
VERSION="0.1.0"
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
    echo "terraform-githbu-pr-commenter v${VERSION}"
    echo
    echo "Usage: $0 <terraform command> <path to terraform command output files> <build number>"
    echo
    echo "  <terraform command> is fmt, plan or validate"
    echo "  <build number> is anything Azure Pipelines or GitHub Actions can provide"
    echo
    exit 1
fi
if [[ -z "$1" ]]; then
    echo -e "\033[31;1mERROR:\033[0m Missing terraform command"
    exit 1
fi
if [[ ! "$1" =~ ^(fmt|plan|validate)$ ]]; then
    echo -e "\033[31;1mERROR:\033[0m Unsupported command ${1}. Valid commands are fmt, plan, validate."
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
        echo "${1}" | iconv -c -f utf-8 -t ascii//TRANSLIT | sed s/^\?//g | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g'
    elif command -v "konwert" &> /dev/null; then
        echo "${1}" | konwert utf8-ascii | sed s/^\?//g | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g'
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
        echo "<details><summary>Details</summary>\n\n\`\`\`diff\n${esc_log}\n\`\`\`\n</details>\n\n"
    else
        # shellcheck disable=SC2028
        echo "Success! The files are well-formed.\n\n"
    fi
}

function _render_plan
{
    local show_plan
    local show_plan_json
    show_plan="${1}"
    show_plan_json="${show_plan%.*}.json"
    if [[ ! -f "${show_plan}" ]] && [[ ! -f "${show_plan_json}" ]]; then
        return 1
    fi

    local esc_log
    local content
    content=""
    # First, render summary from `terraform show -json`, if json file available
    if [[ -f "${show_plan_json}" ]]; then
        # shellcheck disable=SC2002
        changes=$(cat "${show_plan_json}" | jq -r '[.resource_changes[]? | { resource: .address, action: .change.actions[] } | select (.action != "no-op")]')
        summary=$(echo "${changes}" | jq -r '.   | "Environment has \(length) changes"')
        details=$(echo "${changes}" | jq -r '.[] | "* \(.resource) will be \(.action)d"')
        esc_log+=$(_escape_content "${details}")
        content+="Summary: ${summary}\n\n"
        content+="<details><summary>Details</summary>\n\n\`\`\`\n${esc_log}\n\`\`\`\n</details>\n\n"
    fi
    # Next, render `terraform show`
    local raw_log
    if [[ -f "${show_plan}" ]]; then
        raw_log=$(< "${1}")
        # Trim leading and trailing empty lines
        raw_log=$(echo "${raw_log}" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}')
        if [[ -n "${raw_log}" ]]; then
            # Plan clean up rules stolen from https://github.com/gunkow/terraform-pr-commenter
            raw_log=$(echo "${raw_log}" | sed -r '/^(An execution plan has been generated and is shown below.|Terraform used the selected providers to generate the following execution|No changes. Infrastructure is up-to-date.|No changes. Your infrastructure matches the configuration.|Note: Objects have changed outside of Terraform)$/,$!d') # Strip refresh section
            raw_log=$(echo "${raw_log}" | sed -r '/Plan: /q') # Ignore everything after plan summary
            raw_log=${raw_log::65300} # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
            raw_log=$(echo "${raw_log}" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
            esc_log=$(_escape_content "${raw_log}")
            # shellcheck disable=SC2028
            content+="<details><summary>Details</summary>\n\n\`\`\`diff\n${esc_log}\n\`\`\`\n</details>\n\n"
        fi
    fi
    echo "${content}"
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
            echo "${esc_log}\n\n"
        else
            # shellcheck disable=SC2028
            echo "<details><summary>Details</summary>\n\n\`\`\`\n${esc_log}\n\`\`\`\n</details>\n\n"
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
