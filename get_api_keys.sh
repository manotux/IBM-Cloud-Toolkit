#!/usr/bin/env bash

# get_api_keys.sh
#
# This script retrieves all API keys in the IBM Cloud account and outputs their
# id, name, created_at, and created_by fields in a readable format.
# It also identifies API keys that have not been rotated within a configurable 
# period (default: 90 days).
# Requires IBM Cloud CLI and jq for JSON parsing.

# Load common functions and variables
srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

# Default values
OUTPUT_DIR="output"
OUTPUT_FILE="api_keys.txt"
ROTATION_DAYS=90

# Usage
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'api_keys.txt')"
    echo "  -d ROTATION_DAYS  Set the rotation threshold in days (default: 90)"
    echo
    echo "This script retrieves all API keys in the IBM Cloud account."
}

# Parse arguments
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
        d)
            ROTATION_DAYS="$OPTARG"
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

# Prepare output for non-rotated keys
NON_ROTATED_OUTPUT_PATH="${OUTPUT_DIR}/non_rotated_${OUTPUT_FILE}"
: > "$NON_ROTATED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$NON_ROTATED_OUTPUT_PATH${RESET}"

echo " "
echo "${SEPARATOR}"
echo "Retrieving all API keys in IBM Cloud account..."
echo " "

API_KEYS=$(ibmcloud iam api-keys -a -o JSON | jq '[.[] | {id, name, created_at, created_by}]')

if [[ -z "${API_KEYS:-}" ]]; then
    echo "No API keys found."
else
    echo "${API_KEYS}" > "$OUTPUT_PATH"
    echo -e "Output saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

    NOW_EPOCH=$(date +%s)
    NON_ROTATED_FOUND=0

    while read -r line; do
        id=$(jq -r '.id' <<< "$line")
        name=$(jq -r '.name' <<< "$line")
        created_at=$(jq -r '.created_at' <<< "$line")
        created_by=$(jq -r '.created_by' <<< "$line")

        # If there is not created at, skip entry
        [[ -z "$created_at" ]] && continue

        # Convert created_at to epoch seconds
        created_epoch=$(date -j -f "%Y-%m-%dT%H:%M%z" "$created_at" +%s 2>/dev/null || date -d "$created_at" +%s 2>/dev/null)
        [[ -z "$created_epoch" ]] && continue
   
        age_days=$(( (NOW_EPOCH - created_epoch) / 86400 ))

        if (( age_days > ROTATION_DAYS )); then
            echo "$line" >> "$NON_ROTATED_OUTPUT_PATH"
            NON_ROTATED_FOUND=1
        fi
    done < <(echo "$API_KEYS" | jq -c '.[]')

    if (( NON_ROTATED_FOUND )); then
        jq -s '.' "$NON_ROTATED_OUTPUT_PATH" > "${NON_ROTATED_OUTPUT_PATH}.tmp" && mv "${NON_ROTATED_OUTPUT_PATH}.tmp" "$NON_ROTATED_OUTPUT_PATH"
        echo -e "API keys not rotated in the last ${BOLD}${ROTATION_DAYS} days${RESET} saved to: ${BOLD}${NON_ROTATED_OUTPUT_PATH}${RESET}"
    else
        echo "All API keys have been rotated within the last ${BOLD}${ROTATION_DAYS} days${RESET}."
        rm -f "$NON_ROTATED_OUTPUT_PATH"
    fi
fi