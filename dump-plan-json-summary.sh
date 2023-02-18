#!/bin/bash
changes=$(cat "${1}" | jq -r '[.resource_changes[]? | { resource: .address, action: .change.actions[] } | select (.action != "no-op")]')
summary=$(echo $changes | jq -r '.   | "Environment has \(length) changes"')
details=$(echo $changes | jq -r '.[] | "* \(.resource) will be \(.action)d"')
echo "Summary: ${summary}"
echo "${details}"