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
DEBUG=false

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'databases.json')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script enumerates all IBM Cloud Databases."
}

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

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud cdb deployments --json"
fi

# Get Cloud Databases (cdb plugin)
DBS_JSON=$(ibmcloud cdb deployments --json 2>&1) || true
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ] || [[ "$DBS_JSON" =~ "FAILED" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve Cloud Databases"
    fi
    DBS_JSON="[]"
fi

CDB_COUNT=$(echo "${DBS_JSON:-[]}" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Found $CDB_COUNT Cloud Database(s)"
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud resource service-instances --service-name dashdb-for-transactions --all-resource-groups --output json"
fi

# Get DB2 instances
DB2_JSON=$(ibmcloud resource service-instances --service-name dashdb-for-transactions --all-resource-groups --output json 2>&1) || true
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ] || [[ "$DB2_JSON" =~ "FAILED" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve DB2 instances"
    fi
    DB2_JSON="[]"
fi

DB2_COUNT=$(echo "${DB2_JSON:-[]}" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Found $DB2_COUNT DB2 instance(s)"
fi

# Merge both JSON arrays
COMBINED_DBS=$(jq -s 'add' <(echo "${DBS_JSON:-[]}") <(echo "${DB2_JSON:-[]}"))
if [[ -z "${COMBINED_DBS:-}" || "$COMBINED_DBS" == "[]" || "$COMBINED_DBS" == "null" ]]; then
    echo " "
    echo -e "${BOLD}Total databases found: 0${RESET}"
    echo "No databases found."
    exit 0
fi

# Use the combined JSON for processing
DBS_JSON="$COMBINED_DBS"
# Count total databases
TOTAL_DBS=$(echo "$DBS_JSON" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Total databases (combined): $TOTAL_DBS"
fi

echo -e "${BOLD}Total databases found: $TOTAL_DBS${RESET}"
echo " "

# Display database names and types
echo -e "${BOLD}Databases:${RESET}"
while IFS= read -r db; do
    db_name=$(echo "$db" | jq -r '.name')
    db_type=$(echo "$db" | jq -r '.type // .service_id // "unknown"')
    db_guid=$(echo "$db" | jq -r '.guid // .id')
    echo "  - $db_name (Type: $db_type)"
    if [ "$DEBUG" = true ]; then
        echo -e "    ${BOLD}[DEBUG]${RESET} GUID: $db_guid"
    fi
done < <(echo "$DBS_JSON" | jq -c '.[]')
echo " "
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

# Enumerate databases with public endpoint enabled
PUBLIC_ENDPOINT_DBS="[]"
DB_GUIDS=()

while IFS= read -r db_guid; do
    DB_GUIDS+=("$db_guid")
done < <(echo "$DBS_JSON" | jq -r '.[].guid')  # DB guid from both Cloud Databases and DB2

# unset resource group to check db_guid in all if previously set manually
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Unsetting resource group to query across all groups"
fi

ibmcloud target --unset-resource-group -q &>/dev/null
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Checking endpoint types for each database..."
fi

PUBLIC_COUNT=0
for db_guid in "${DB_GUIDS[@]}"; do
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud resource service-instance \"$db_guid\" --output json"
    fi
    DB_INSTANCE_JSON=$(ibmcloud resource service-instance "$db_guid" --output json 2>/dev/null)
    if [[ -z "${DB_INSTANCE_JSON:-}" || "$DB_INSTANCE_JSON" == "[]" ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Could not retrieve details for this database"
        fi
        continue
    fi
    ENDPOINT_TYPE=$(echo "$DB_INSTANCE_JSON" | jq -r '.[0].parameters["service-endpoints"] // "private"')
    if [ "$DEBUG" = true ]; then
        db_name=$(echo "$DB_INSTANCE_JSON" | jq -r '.[0].name')
        echo -e "${BOLD}[DEBUG]${RESET} Database \"$db_name\": endpoint type = $ENDPOINT_TYPE"
    fi
    if [[ "$ENDPOINT_TYPE" != "private" ]]; then
        PUBLIC_COUNT=$((PUBLIC_COUNT + 1))
        PUBLIC_ENDPOINT_DBS=$(jq -s 'add' <(echo "$PUBLIC_ENDPOINT_DBS") <(echo "$DB_INSTANCE_JSON" | jq '[.[] | {name, guid, crn, service_endpoints: .parameters["service-endpoints"]}]'))
    fi
done

# Save all databases to the output file
echo "$DBS_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All databases saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

# Save databases with public endpoint to a separate file
echo " "
if [[ $(echo "$PUBLIC_ENDPOINT_DBS" | jq 'length') -gt 0 ]]; then
    : > "$PUBLIC_ENDPOINT_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_ENDPOINT_OUTPUT_PATH${RESET}"
    echo "$PUBLIC_ENDPOINT_DBS" | jq '.' > "$PUBLIC_ENDPOINT_OUTPUT_PATH"
    echo -e "${BOLD}Databases with public endpoint: $PUBLIC_COUNT${RESET}"
    echo -e "Databases with public endpoint saved to: ${BOLD}${PUBLIC_ENDPOINT_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Databases with public endpoint: 0${RESET}"
fi

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Cloud Databases: $CDB_COUNT"
    echo -e "${BOLD}[DEBUG]${RESET}   DB2 Instances: $DB2_COUNT"
    echo -e "${BOLD}[DEBUG]${RESET}   Total: $TOTAL_DBS"
    echo -e "${BOLD}[DEBUG]${RESET}   Public Endpoints: $PUBLIC_COUNT"
fi
