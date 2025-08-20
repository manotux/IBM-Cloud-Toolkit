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
OUTPUT_FILE="regions.txt"

# Usage
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'regions.txt')"
    echo
    echo "This script retrieves the list of enabled regions in an IBM Cloud account."
}

# Parse arguments
while getopts ":ho:" opt; do
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
echo "Retrieving enabled regions on IBM Cloud account..."
echo " "

REGIONS=$(ibmcloud regions --output json | jq -r '.[].Name')

if [[ -z "$REGIONS" ]]; then
    echo "No regions found."
else
    while IFS= read -r region; do
        echo "$region" >> "$OUTPUT_PATH"
    done <<< "$REGIONS"
    echo -e "Output saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
fi
