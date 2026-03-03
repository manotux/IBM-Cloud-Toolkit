#!/usr/bin/env bash

# get_regions.sh
#
# This script retrieves the list of enabled regions in an IBM Cloud account
# and provides an option to export them as an environment variable. 
# Requires IBM Cloud CLI and jq for JSON parsing.

# Load common functions and variables
srcdir="$(dirname "${BASH_SOURCE}")"
. "$srcdir/utils.sh"

# Variables
OUTPUT_DIR="output"
OUTPUT_FILE="regions.txt"
DEBUG=false

# Usage
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'regions.txt')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script retrieves the list of enabled regions in an IBM Cloud account."
}

# Parse arguments
while getopts ":ho:f:v" opt; do
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

# Check if IBM Cloud CLI and jq are installed
require_ibmcloud_jq

# Check if IBM Cloud CLI is logged in
require_ibmcloud_login

# Ensure output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

# Ensure the output file exists
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo " "
echo "${SEPARATOR}"
echo -e "Enumerating enabled ${ORANGE}${BOLD}regions${RESET} on IBM Cloud account..."
echo " "
# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud regions --output json"
fi
REGIONS=$(ibmcloud regions --output json 2>&1 | jq -r '.[].Name') || true
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ] || [[ -z "${REGIONS:-}" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve regions"
    fi
    failure "Could not retrieve regions. Retry."

fi
# Count regions
TOTAL_REGIONS=$(echo "$REGIONS" | wc -l | tr -d ' ')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Found $TOTAL_REGIONS region(s)"
fi
echo -e "${BOLD}Total regions found: $TOTAL_REGIONS${RESET}"
echo " "

# Display regions
echo -e "${BOLD}Regions:${RESET}"
while IFS= read -r region; do
    if [[ -n "$region" ]]; then
        echo "  - $region"
        echo "$region" >> "$OUTPUT_PATH"
    fi
done <<< "$REGIONS"
echo " "
echo -e "All regions saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total regions: $TOTAL_REGIONS"
    echo -e "${BOLD}[DEBUG]${RESET}   Output file: $OUTPUT_PATH"
fi