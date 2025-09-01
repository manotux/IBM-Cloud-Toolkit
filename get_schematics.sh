#!/usr/bin/env bash

# get_schematics.sh
#
# This script enumerates all IBM Cloud Schematics workspaces in each enabled IBM Cloud region and outputs them as a JSON array.
# The output can be reviewed manually or with tools like TruffleHog or detect-secrets to identify 
# sensitive information insecurelly stored in variables and Terraform templates.
# Requires IBM Cloud CLI and the schematics plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="schematics_workspaces.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'schematics_workspaces.json')"
    echo
    echo "This script enumerates all IBM Cloud Schematics workspaces in each enabled region."
}

while getopts ":ho:f:" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        f)
            OUTPUT_FILE="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
    esac
done

require_ibmcloud_jq
require_ibmcloud_login
require_ibmcloud_schematics

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}Schematics${RESET} workspaces ..."
echo " "

# Use only valid Schematics locations
# us-south also retrieves us-east, the same seems to happen with eu-de/eu-gb and ca-tor/ca-mon
REGIONS="us-south eu-de ca-tor"
ALL_WORKSPACES_JSON="[]"

for region in $REGIONS; do
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        continue
    fi

    WORKSPACES_JSON=$(ibmcloud schematics workspace list --output json 2>/dev/null) || { warning "Failed to retrieve Schematics workspaces for region $region"; continue; }
    if [[ -z "${WORKSPACES_JSON:-}" || "$WORKSPACES_JSON" == "[]" || "$WORKSPACES_JSON" == "null" ]]; then
        continue
    fi

    # Extract the workspaces array from the returned object
    REGION_WORKSPACES=$(echo "$WORKSPACES_JSON" | jq '.workspaces // []')
    if [[ -z "${REGION_WORKSPACES:-}" || "$REGION_WORKSPACES" == "[]" || "$REGION_WORKSPACES" == "null" ]]; then
        continue
    fi
    ALL_WORKSPACES_JSON=$(jq -s 'add' <(echo "$ALL_WORKSPACES_JSON") <(echo "$REGION_WORKSPACES"))
    unset WORKSPACES_JSON REGION_WORKSPACES

done

if [[ "$ALL_WORKSPACES_JSON" == "[]" ]]; then
    echo "No Schematics workspaces found."
    exit 0
fi

: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo "$ALL_WORKSPACES_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All Schematics workspaces saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
echo -e "Review this file for secrets in variables using tools like TruffleHog/detect-secrets or manually."
