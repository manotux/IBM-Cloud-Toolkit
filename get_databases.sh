#!/usr/bin/env bash

# get_databases.sh
#
# This script enumerates all IBM Cloud Databases and outputs them as a JSON array.
# For each database, it outputs: id, name, type, endpoint, and other relevant info.
# If any database has a public endpoint enabled, a separate output file is created with only those databases.
# Requires IBM Cloud CLI and databases ("cdb") plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="databases.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'databases.json')"
    echo
    echo "This script enumerates all IBM Cloud Databases."
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
require_ibmcloud_cdb

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
PUBLIC_ENDPOINT_OUTPUT_PATH="${OUTPUT_DIR}/public_endpoint_${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating IBM Cloud ${ORANGE}${BOLD}Databases${RESET}..."
echo " "

DBS_JSON=$(ibmcloud cdb deployments --json 2>/dev/null) || failure "Failed to retrieve databases."

if [[ -z "${DBS_JSON:-}" || "$DBS_JSON" == "[]" || "$DBS_JSON" == "null" ]]; then
    echo "No databases found."
    exit 0
fi

: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

# Enumerate databases with public endpoint enabled

PUBLIC_ENDPOINT_DBS="[]"
DB_NAMES=()

while IFS= read -r db_name; do
    DB_NAMES+=("$db_name")
done < <(echo "$DBS_JSON" | jq -r '.[].name')

for db_name in "${DB_NAMES[@]}"; do
    DB_INSTANCE_JSON=$(ibmcloud resource service-instance "$db_name" --output json 2>/dev/null)
    if [[ -z "${DB_INSTANCE_JSON:-}" || "$DB_INSTANCE_JSON" == "[]" ]]; then
        continue
    fi
    ENDPOINT_TYPE=$(echo "$DB_INSTANCE_JSON" | jq -r '.[0].parameters["service-endpoints"] // "private"')
    if [[ "$ENDPOINT_TYPE" != "private" ]]; then
        PUBLIC_ENDPOINT_DBS=$(jq -s 'add' <(echo "$PUBLIC_ENDPOINT_DBS") <(echo "$DB_INSTANCE_JSON" | jq '[.[] | {name, crn, service_endpoints: .parameters["service-endpoints"]}]'))
    fi
done

# Save all databases to the output file
echo "$DBS_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All databases saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

# Save databases with public endpoint to a separate file
if [[ $(echo "$PUBLIC_ENDPOINT_DBS" | jq 'length') -gt 0 ]]; then
    : > "$PUBLIC_ENDPOINT_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_ENDPOINT_OUTPUT_PATH${RESET}"
    echo "$PUBLIC_ENDPOINT_DBS" | jq '.' > "$PUBLIC_ENDPOINT_OUTPUT_PATH"
    echo -e "Databases with public endpoint saved to: ${BOLD}${PUBLIC_ENDPOINT_OUTPUT_PATH}${RESET}"
else
    echo "No databases with public endpoint found."
fi
