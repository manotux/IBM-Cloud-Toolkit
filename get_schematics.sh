#!/usr/bin/env bash

# get_schematics.sh
#
# This script enumerates all IBM Cloud Schematics workspaces in each enabled IBM Cloud region and outputs them as a JSON array.
# The output can be reviewed manually or with tools like TruffleHog or detect-secrets to identify 
# sensitive information insecurely stored in variables and Terraform templates.
# Requires IBM Cloud CLI and the schematics plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="schematics_workspaces.json"
DEBUG=false
REGIONS="us-south eu-de ca-tor"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-r REGIONS] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'schematics_workspaces.json')"
    echo "  -r REGIONS      Specify regions to check, space or comma-separated (default: 'us-south eu-de ca-tor')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script enumerates all IBM Cloud Schematics workspaces in each enabled region."
    echo
    echo "Examples:"
    echo "  ./$scriptname -r \"us-south eu-gb\""
    echo "  ./$scriptname -r \"us-south,eu-gb,ca-tor\""
    echo "  ./$scriptname -r \"\$(xargs < output/regions.txt)\""
}

while getopts ":ho:f:r:v" opt; do
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
        r)
            # Replace commas with spaces for consistent parsing
            REGIONS="${OPTARG//,/ }"
            ;;
        v)
            DEBUG=true
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
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Processing Schematics regions: $REGIONS"
fi

ALL_WORKSPACES_JSON="[]"
TOTAL_WORKSPACES=0
declare -A REGION_WORKSPACE_COUNTS
for region in $REGIONS; do
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Processing region: $region"
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud target -r \"$region\""
    fi
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Skipping region $region"
        fi
        continue
    fi
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud schematics workspace list --output json"
    fi
    WORKSPACES_JSON=$(ibmcloud schematics workspace list --output json 2>&1) || true
    EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 || "$WORKSPACES_JSON" == "[]" || "$WORKSPACES_JSON" == "null" ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve workspaces for region $region"
        fi
        warning "Failed to retrieve Schematics workspaces for region $region"
        REGION_WORKSPACE_COUNTS[$region]=0
        continue
    fi

    if [[ -z "${WORKSPACES_JSON:-}" || "$WORKSPACES_JSON" == "[]" || "$WORKSPACES_JSON" == "null" ]]; then
        REGION_WORKSPACE_COUNTS[$region]=0
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: No workspaces found"
        fi
        continue
    fi

    # Extract the workspaces array from the returned object
    REGION_WORKSPACES=$(echo "$WORKSPACES_JSON" | jq '.workspaces // []')
    if [[ -z "${REGION_WORKSPACES:-}" || "$REGION_WORKSPACES" == "[]" || "$REGION_WORKSPACES" == "null" ]]; then
        REGION_WORKSPACE_COUNTS[$region]=0
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: No workspaces found"
        fi
        continue
    fi
    WORKSPACE_COUNT=$(echo "$REGION_WORKSPACES" | jq 'length')
    REGION_WORKSPACE_COUNTS[$region]=$WORKSPACE_COUNT
    TOTAL_WORKSPACES=$((TOTAL_WORKSPACES + WORKSPACE_COUNT))
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $WORKSPACE_COUNT workspace(s)"
    fi
    ALL_WORKSPACES_JSON=$(jq -s 'add' <(echo "$ALL_WORKSPACES_JSON") <(echo "$REGION_WORKSPACES"))
    unset WORKSPACES_JSON REGION_WORKSPACES

done

echo -e "${BOLD}Total workspaces found: $TOTAL_WORKSPACES${RESET}"
echo " "
if [[ "$ALL_WORKSPACES_JSON" == "[]" || $TOTAL_WORKSPACES -eq 0 ]]; then
    echo "No Schematics workspaces found."
    exit 0
fi

# Display workspaces by region
echo -e "${BOLD}Workspaces by region:${RESET}"
for region in $REGIONS; do
    if [[ ${REGION_WORKSPACE_COUNTS[$region]:-0} -gt 0 ]]; then
        echo -e "  ${BOLD}$region:${RESET} ${REGION_WORKSPACE_COUNTS[$region]} workspace(s)"
        # Extract and display workspace names for this region
        REGION_WS=$(echo "$ALL_WORKSPACES_JSON" | jq -r --arg region "$region" '.[] | select(.location == $region) | .name')
        while IFS= read -r ws_name; do
            if [[ -n "$ws_name" ]]; then
                echo "    - $ws_name"
            fi
        done <<< "$REGION_WS"
    fi
done

echo " "
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo "$ALL_WORKSPACES_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All Schematics workspaces saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
echo ""
echo -e "${YELLOW}${BOLD}Security Note:${RESET} Review this file for secrets in variables using tools like TruffleHog/detect-secrets or manually."
if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total workspaces: $TOTAL_WORKSPACES"
    echo -e "${BOLD}[DEBUG]${RESET}   Workspaces by region:"
    for region in $REGIONS; do
        echo -e "${BOLD}[DEBUG]${RESET}     $region: ${REGION_WORKSPACE_COUNTS[$region]:-0}"
    done
fi
