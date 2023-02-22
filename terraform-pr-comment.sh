#!/bin/bash
VERSION="0.3.0"
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
#set -x
function usage
{
    echo "Usage: $0 [arguments]"
    echo "  -v,--verbose                Advertise detailed steps and actions (pass first for arguments logging)"
    echo "  -c,--command <name>         Terraform command: fmt, plan, validate"
    echo "  -p,--logs-path <path>       Path to directory with log files or to single log file with Terraform command output"
    echo "  -b,--build-number <number>  Build number or identifier provided by CI/CD service (for comment title)"
    echo "  -u,--build-url <url>        Build results URL provided by CI/CD service (for comment title)"
    echo "  -e,--build-env <name>       Name of environment or stage of this build (for comment title)"
    echo "  -d,--disable-outer-details  Disable outer HTML <details> section"
    echo "  -l,--dry-run-list-logs      Dry run listing log files only"
    echo "  -h,--help                   Displays this message"
    exit 1
}
function die
{
    set -e
    /bin/false
}
function echolog
{
    if [ $arg_verbose -ne 0 ]; then
        echo -n "[$(printf '%(%F %T)T')] " >&2
        echo -e "\033[32;1mINFO:\033[0m $*" >&2
    fi
}
function echoerr
{
    echo -n "[$(printf '%(%F %T)T')] " >&2
    echo -e "\033[31;1mERROR:\033[0m $*" >&2
    die
}

### Arguments ##################################################################
arg_tf_command=""
arg_logs_path=""
arg_build_number=""
arg_build_url=""
arg_build_env=""
arg_verbose=0
arg_disable_outer_details=0
arg_dry_run_list_logs=0
while [[ $# -gt 0 ]];
do
    case $1 in
        -v|--verbose) arg_verbose=1; echolog "Enabling verbose logging";;
        -c|--command)  test ! -z "$2" && arg_tf_command=$2; echolog "Setting command: ${arg_tf_command}"; shift;;
        -p|--logs-path) test ! -z "$2" && arg_logs_path=$2; echolog "Setting logs path: ${arg_logs_path}"; shift;;
        -b|--build-number) test ! -z "$2" && arg_build_number=$2; echolog "Setting build number: ${arg_build_number}"; shift;;
        -u|--build-url) test ! -z "$2" && arg_build_url=$2; echolog "Setting build url: ${arg_build_url}"; shift;;
        -e|--build-env) test ! -z "$2" && arg_build_env=$2; echolog "Setting build env: ${arg_build_env}"; shift;;
        -d|--disable-outer-details) arg_disable_outer_details=1; echolog "Disabling outer details";;
        -l|--dry-run-list-logs) arg_dry_run_list_logs=1; echolog "Dry run listing logs"; shift;;
        -h|--help) usage;;
        *) echolog "Unknown argument: $1"; usage;;
    esac;
    shift
done

if [[ -z "$arg_tf_command" ]]; then
    echoerr "Missing Terraform command"
fi
if [[ ! "$arg_tf_command" =~ ^(fmt|plan|validate)$ ]]; then
    echoerr "Unsupported command ${arg_tf_command}. Valid commands: fmt, plan, validate."
fi
if [[ ! -d "$arg_logs_path" ]] && [[ ! -f "$arg_logs_path" ]]; then
    echoerr "Missing path to Terraform command output files"
fi
if [[ -z "$arg_build_number" ]]; then
    echoerr "Missing build number"
fi

### Check for any options given that disable comment rendering
cfg_enable_rendering=1
if [[ $arg_dry_run_list_logs -gt 0 ]]; then
    cfg_enable_rendering=0
fi
cfg_enable_single_file=0
if [[ -f "${arg_logs_path}" ]]; then
    cfg_enable_single_file=1
fi

### Check required tools
# TODO: Add more conversion methods
if command -v "iconv" &> /dev/null; then
    echolog "Using iconv to escape comment content"
elif command -v "konwert" &> /dev/null; then
    echolog "Using konwert to escape comment content"
else
    echoerr "Missing reliable Unicode to ASCII converter for the fancy Terraform output"
fi

### Comment Rendering ##########################################################
function _escape_content
{
    local escaped

    if [[ -n "${1}" ]]; then
        if command -v "iconv" &> /dev/null; then
            escaped=$(echo "${1}" | iconv -c -f utf-8 -t ascii//TRANSLIT)
        elif command -v "konwert" &> /dev/null; then
            escaped=$("${1}" | konwert utf8-ascii)
        fi
        # shellcheck disable=SC2001
        echo "${escaped}" | sed s/^\?//g
        # FIXME: This breaks content of code blocks: | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g'
    fi
}
function _render_html_details_summary
{
    local title
    title="${1}"
    if [[ -z "${title}" ]]; then
        title="Details"
    fi
    # shellcheck disable=SC2028
    echo "<summary><strong>${title}</strong></summary>\n\n"
}
function _render_command_fmt
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
        # shellcheck disable=SC2028,SC2119
        echo "<details>$(_render_html_details_summary)\`\`\`diff\n${esc_log}\n\`\`\`\n</details>\n\n"
    else
        # shellcheck disable=SC2028
        echo "Success! The files are well-formed.\n\n"
    fi
}
function _render_command_plan
{
    local show_plan show_plan_json
    show_plan="${1}"
    show_plan_json="${show_plan%.*}.json"
    if [[ ! -f "${show_plan}" ]] && [[ ! -f "${show_plan_json}" ]]; then
        return 1
    fi

    local content esc_log summary
    content=""
    # First, render summary from `terraform show -json`, if json file available
    if [[ -f "${show_plan_json}" ]]; then
        local changes details
        # shellcheck disable=SC2002
        changes=$(cat "${show_plan_json}" | jq -r '[.resource_changes[]? | { resource: .address, action: .change.actions[] } | select (.action != "no-op")]')
        summary=$(echo "${changes}" | jq -r '.   | "Plan will apply \(length) changes (based on JSON output)"')
        details=$(echo "${changes}" | jq -r '.[] | "* \(.resource) will be \(.action)d"')
        esc_log+=$(_escape_content "${details}")
        content+="${summary}\n\n"
        if [[ -n "${details}" ]]; then
            # shellcheck disable=SC2119
            content+="<details>$(_render_html_details_summary)\`\`\`\n${esc_log}\n\`\`\`\n</details>\n\n"
        fi
    fi
    # Next, render `terraform show`
    if [[ -f "${show_plan}" ]]; then
        local raw_log
        raw_log=$(< "${1}")
        # shellcheck disable=SC2001
        raw_log=$(echo "${raw_log}" | sed 's/\x1b\[[0-9;]*m//g')
        # Trim leading and trailing empty lines
        raw_log=$(echo "${raw_log}" | sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}')
        if [[ -n "${raw_log}" ]]; then
            # Plan clean up rules stolen from https://github.com/gunkow/terraform-pr-commenter
            #raw_log=$(echo "${raw_log}" | sed -r '/^(An execution plan has been generated and is shown below.|Terraform used the selected providers to generate the following execution|plan. Resource actions are indicated with the following symbols:|Note: Objects have changed outside of Terraform)$/d') # Strip refresh section
            raw_log=$(echo "${raw_log}" | sed -r '/Plan: /q') # Ignore everything after plan summary
            raw_log=${raw_log::65300} # GitHub has a 65535-char comment limit - truncate plan, leaving space for comment wrapper
            raw_log=$(echo "${raw_log}" | sed -r 's/^([[:blank:]]*)([-+~])/\2\1/g') # Move any diff characters to start of line
            summary=$(echo "${raw_log}" | grep -E "^Plan\:.+$" | tail -n 1) # Extract Plan: line from diff summary (may not be present)
            esc_log=$(_escape_content "${raw_log}")
            if [[ -n "${summary}" ]]; then
                content+="${summary}\n\n"
            fi
            # shellcheck disable=SC2119
            content+="<details>$(_render_html_details_summary)\`\`\`diff\n${esc_log}\n\`\`\`\n</details>\n\n"
        fi
    fi
    echo "${content}"
}
function _render_command_validate
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
            # shellcheck disable=SC2028,SC2119
            echo "<details>$(_render_html_details_summary)\`\`\`\n${esc_log}\n\`\`\`\n</details>\n\n"
        fi
    fi
}

### Main Script ################################################################
logs_collected=0

echolog "Rendering Terraform ${arg_tf_command} comment from ${arg_logs_path}"

### Collect log files
if [[ $cfg_enable_single_file -gt 0 ]]; then
    log_files=$(ls "${arg_logs_path}" 2>/dev/null)
else
    log_files=$(ls --sort=version "${arg_logs_path}"/*."${arg_tf_command}".{log,txt} 2>/dev/null)
fi

### Render comment body
comment_body=""
# Open outer <details>, optional
if [[ $cfg_enable_rendering -gt 0 ]] && [[ $arg_disable_outer_details -ne 1 ]]; then
    comment_body+="<details>$(_render_html_details_summary "Run Details")"
fi

section_component=""
for log_file in $log_files; do
    if [[ $arg_dry_run_list_logs -gt 0 ]]; then
        echo "${log_file}"
    else
        echolog "Rendering ${arg_tf_command} output from ${log_file}"
    fi

    if [[ $cfg_enable_rendering -eq 0 ]]; then
        continue
    fi
    # Render section title
    section_component=$(basename "${log_file}")
    section_component=$(echo "${section_component}" | cut -d '_' -f 2 | cut -d . -f 1)
    if [[ $cfg_enable_single_file -eq 0 ]]; then
        comment_body+="### Component: \`${section_component}\`\n\n"
        section_component=""
    fi
    # Render section body
    section_body=$(_render_command_"${arg_tf_command}"  "${log_file}")
    if [[ -z "${section_body}" ]]; then
        echoerr "Rendering ${arg_tf_command} output failed"
    fi
    comment_body+="${section_body}"

    ((++logs_collected))
done

# Close outer <details>, optional
if [[ $cfg_enable_rendering -gt 0 ]] && [[ $arg_disable_outer_details -ne 1 ]]; then
    comment_body+="</details>\n"
fi

### Render comment title
comment_title=""
if [[ $cfg_enable_rendering -gt 0 ]]; then
    if [[ -n "${arg_build_url}" ]]; then
        comment_title+="## [${arg_build_number}](${arg_build_url})"
    else
        comment_title+="## \`${arg_build_number}\`"
    fi
    if [[ -n "${arg_build_env}" ]]; then
        comment_title+=" - \`${arg_build_env}\`"
    fi
    if [[ -n "${section_component}" ]]; then
        comment_title+=" - \`${section_component}\`"
    fi
    comment_title+=" - \`${arg_tf_command}\` "
fi

# Return result
echolog "Exporting TERRAFORM_COMMAND_PR_COMMENT environment variable"
TERRAFORM_COMMAND_PR_COMMENT=""
if [[ $cfg_enable_rendering -gt 0 ]] && [[ $logs_collected -gt 0 ]]; then
    # GitHub API uses \r\n as line breaks in bodies
    # https://github.com/actions/runner/issues/1462#issuecomment-1030124116
    TERRAFORM_COMMAND_PR_COMMENT+="${comment_title//\\n/%0D%0A}"
    TERRAFORM_COMMAND_PR_COMMENT+="${comment_body//\\n/%0D%0A}"
fi
unset logs_collected
unset comment

echo "${TERRAFORM_COMMAND_PR_COMMENT}"
export TERRAFORM_COMMAND_PR_COMMENT
