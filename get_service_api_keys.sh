#!/usr/bin/env bash

# get_service_api_keys.sh
#
# This script retrieves all Service IDs in the IBM Cloud account
# and extracts all associated Service API keys for each Service ID.
# It outputs their id, name, created_at, and created_by fields
# in a readable JSON format.
# It also identifies Service API keys that have not been rotated within
# a configurable period (default: 90 days), and API keys that contain
# an actual apikey value (saved separately to leaked_service_api_keys.json).
#
# Requires IBM Cloud CLI and jq for JSON parsing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

# Default values
OUTPUT_DIR="output"
OUTPUT_FILE="service_api_keys.json"
ROTATION_DAYS=90
DEBUG=false
MAX_PARALLEL=10

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-d ROTATION_DAYS] [-p MAX_PARALLEL] [-v]"
    echo
    echo "Options:"
    echo "  -h                 Show this help message"
    echo "  -o OUTPUT_DIR      Specify the output folder (default: 'output')"
    echo "  -f OUTPUT_FILE     Specify the output file name (default: 'service_api_keys.json')"
    echo "  -d ROTATION_DAYS   Set rotation threshold in days (default: 90)"
    echo "  -p MAX_PARALLEL    Number of parallel API calls (default: 10)"
    echo "  -v                 Enable debug mode (outputs commands)"
    echo
    echo "This script retrieves all Service IDs and their associated API keys."
}

# Parse arguments
while getopts ":ho:f:d:p:v" opt; do
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
        p)
            MAX_PARALLEL="$OPTARG"
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

# Checks
require_ibmcloud_jq
require_ibmcloud_login
mkdir -p "$OUTPUT_DIR" || failure "Error while creating output directory: $OUTPUT_DIR"
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
NON_ROTATED_OUTPUT_PATH="${OUTPUT_DIR}/non_rotated_${OUTPUT_FILE}"
LEAKED_OUTPUT_PATH="${OUTPUT_DIR}/leaked_service_api_keys.json"
TEMP_DIR="${OUTPUT_DIR}/.tmp_service_keys_$$"

# Create temp directory for parallel processing
mkdir -p "$TEMP_DIR" || failure "Failed to create temporary directory"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
echo " "
echo "${SEPARATOR}"
echo -e "Enumerating all ${ORANGE}${BOLD}Service IDs and their API keys${RESET}..."
echo " "

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud iam service-ids -o JSON"
fi

SERVICE_IDS_JSON=$(ibmcloud iam service-ids -o JSON 2>&1) || true
EXIT_CODE=$?

# Validate JSON
if ! echo "$SERVICE_IDS_JSON" | jq empty 2>/dev/null; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON response"
        echo -e "${BOLD}[DEBUG]${RESET} Response: $SERVICE_IDS_JSON"
    fi
    failure "Failed to retrieve valid JSON for Service IDs"
fi

if [ $EXIT_CODE -ne 0 ] || [[ "$SERVICE_IDS_JSON" =~ "FAILED" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Command failed"
    fi
    failure "Failed to retrieve Service IDs"
fi

SERVICE_IDS=$(echo "$SERVICE_IDS_JSON" | jq -r '.[].id')
if [[ -z "$SERVICE_IDS" ]]; then
    echo "No Service IDs found."
    exit 0
fi

# Count service IDs
TOTAL_SERVICE_IDS=$(echo "$SERVICE_IDS" | wc -l | tr -d ' ')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Found $TOTAL_SERVICE_IDS Service ID(s)"
    echo -e "${BOLD}[DEBUG]${RESET} Using $MAX_PARALLEL parallel workers"
fi

echo -e "${BOLD}Total Service IDs: $TOTAL_SERVICE_IDS${RESET}"
echo -e "Fetching API keys for each Service ID (using $MAX_PARALLEL parallel workers)..."
echo " "
# Function to fetch API keys for a Service ID
fetch_service_api_keys() {
    local service_id="$1"
    local service_index="$2"
    local temp_dir="$3"
    local service_ids_json="$4"
    local debug_mode="$5"
    local service_name=$(echo "$service_ids_json" | jq -r --arg id "$service_id" '.[] | select(.id == $id) | .name')
    if [ "$debug_mode" = "true" ]; then
        echo "[DEBUG] Processing Service ID: $service_name ($service_id)" >&2
        echo "[DEBUG] Running command: ibmcloud iam service-api-keys \"$service_id\" -o JSON" >&2
    fi
    local api_keys_json=$(ibmcloud iam service-api-keys "$service_id" -o JSON 2>&1)
    # Validate JSON
    if ! echo "$api_keys_json" | jq empty 2>/dev/null; then
        if [ "$debug_mode" = "true" ]; then
            echo "[DEBUG] Invalid JSON response for Service ID: $service_id" >&2
        fi
        echo "[]" > "${temp_dir}/${service_index}.json"
        return
    fi
    if [[ -z "$api_keys_json" || "$api_keys_json" == "[]" ]]; then
        if [ "$debug_mode" = "true" ]; then
            echo "[DEBUG] No API keys found for Service: $service_name" >&2
        fi
        echo "[]" > "${temp_dir}/${service_index}.json"
        return
    fi
    local key_count=$(echo "$api_keys_json" | jq 'length')
    if [ "$debug_mode" = "true" ]; then
        echo "[DEBUG] Service \"$service_name\": Found $key_count API key(s)" >&2
    fi
    # Add service info to keys
    local keys=$(echo "$api_keys_json" | jq --arg svc_id "$service_id" --arg svc_name "$service_name" '[.[] | . + {service_id: $svc_id, service_name: $svc_name}]')
    echo "$keys" > "${temp_dir}/${service_index}.json"
}

# Export function and variables for parallel execution
export -f fetch_service_api_keys
export SERVICE_IDS_JSON
export DEBUG
export TEMP_DIR

# Process Service IDs in parallel
SERVICE_INDEX=0
RUNNING_JOBS=0
while IFS= read -r service_id; do
    SERVICE_INDEX=$((SERVICE_INDEX + 1))
    # Launch background job
    fetch_service_api_keys "$service_id" "$SERVICE_INDEX" "$TEMP_DIR" "$SERVICE_IDS_JSON" "$DEBUG" &
    RUNNING_JOBS=$((RUNNING_JOBS + 1))
    # Wait if we've reached max parallel jobs
    if [ $RUNNING_JOBS -ge $MAX_PARALLEL ]; then
        wait -n  # Wait for any job to complete
        RUNNING_JOBS=$((RUNNING_JOBS - 1))
    fi
    # Show progress every 5 Service IDs (only in non-debug mode)
    if [ "$DEBUG" = false ] && [ $((SERVICE_INDEX % 5)) -eq 0 ]; then
        echo -ne "\rProcessed: $SERVICE_INDEX/$TOTAL_SERVICE_IDS Service IDs..."
    fi
done <<< "$SERVICE_IDS"

# Wait for all remaining jobs to complete
wait
if [ "$DEBUG" = false ]; then
    echo -e "\rProcessed: $TOTAL_SERVICE_IDS/$TOTAL_SERVICE_IDS Service IDs... Done!"
fi

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} All parallel jobs completed"
fi

# Aggregate results
echo " "
echo "Aggregating results..."
ALL_KEYS="[]"
TOTAL_API_KEYS=0

# Merge all results
for i in $(seq 1 $TOTAL_SERVICE_IDS); do
    if [ -f "${TEMP_DIR}/${i}.json" ]; then
        KEYS=$(cat "${TEMP_DIR}/${i}.json")
        KEY_COUNT=$(echo "$KEYS" | jq 'length')
        if [ $KEY_COUNT -gt 0 ]; then
            TOTAL_API_KEYS=$((TOTAL_API_KEYS + KEY_COUNT))
            ALL_KEYS=$(jq -s 'add' <(echo "$ALL_KEYS") <(echo "$KEYS"))
        fi
    fi
done

echo " "
if [[ "$ALL_KEYS" == "[]" || $TOTAL_API_KEYS -eq 0 ]]; then
    echo -e "${BOLD}Total Service API keys: 0${RESET}"
    echo "No Service API keys found."
    exit 0
fi

echo -e "${BOLD}Total Service API keys: $TOTAL_API_KEYS${RESET}"
echo " "
echo "$ALL_KEYS" | jq '.' > "$OUTPUT_PATH" || failure "Failed writing to $OUTPUT_PATH"
echo -e "All Service API keys saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

# Identify keys with apikey values (potential leaks)
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Checking for leaked API keys (containing actual apikey values)"
fi

jq '[.[] | select(.apikey != null and .apikey != "")]' "$OUTPUT_PATH" > "$LEAKED_OUTPUT_PATH" || failure "Failed to create leaked key list"
LEAKED_COUNT=$(jq 'length' "$LEAKED_OUTPUT_PATH")
if [[ -s "$LEAKED_OUTPUT_PATH" && $LEAKED_COUNT -gt 0 ]]; then
    echo " "
    echo -e "${YELLOW}${BOLD}Warning: Leaked Service API keys found: $LEAKED_COUNT${RESET}"
    echo -e "Service API keys containing actual apikey values saved to: ${BOLD}${LEAKED_OUTPUT_PATH}${RESET}"
    echo " "
    echo -e "${BOLD}Leaked Service API keys:${RESET}"
    while IFS= read -r key; do
        key_name=$(echo "$key" | jq -r '.name')
        key_service=$(echo "$key" | jq -r '.service_name')
        echo "  - $key_name (Service: $key_service)"
    done < <(jq -c '.[]' "$LEAKED_OUTPUT_PATH")
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Found $LEAKED_COUNT leaked API key(s)"
    fi
else
    echo " "
    echo -e "${BOLD}Good:${RESET} No Service API keys contained apikey values."
    rm -f "$LEAKED_OUTPUT_PATH"
fi

# Rotation analysis
echo " "
echo "Analyzing key rotation..."
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Checking for keys older than $ROTATION_DAYS days"
fi

NOW_EPOCH=$(date +%s)
NON_ROTATED_LINES=()
while read -r line; do
    id=$(jq -r '.id' <<< "$line")
    created_at=$(jq -r '.created_at' <<< "$line")
    [[ -z "$created_at" || "$created_at" == "null" ]] && continue
    created_epoch=$(date -j -f "%Y-%m-%dT%H:%M%z" "$created_at" +%s 2>/dev/null || date -d "$created_at" +%s 2>/dev/null)
    [[ -z "$created_epoch" ]] && continue
    age_days=$(( (NOW_EPOCH - created_epoch) / 86400 ))
    if (( age_days > ROTATION_DAYS )); then
        NON_ROTATED_LINES+=("$line")
    fi
done < <(jq -c '.[]' "$OUTPUT_PATH")

echo " "
if (( ${#NON_ROTATED_LINES[@]} > 0 )); then
    NON_ROTATED_COUNT=${#NON_ROTATED_LINES[@]}
    echo -e "${YELLOW}${BOLD}Service API keys not rotated in $ROTATION_DAYS days: $NON_ROTATED_COUNT${RESET}"
    printf "%s\n" "${NON_ROTATED_LINES[@]}" | jq -s '.' > "$NON_ROTATED_OUTPUT_PATH" \
        || failure "Error while writing $NON_ROTATED_OUTPUT_PATH"
    echo -e "Non-rotated keys saved to: ${BOLD}${NON_ROTATED_OUTPUT_PATH}${RESET}"
    echo " "
    echo -e "${BOLD}Non-rotated Service API keys:${RESET}"
    while IFS= read -r key; do
        key_name=$(echo "$key" | jq -r '.name')
        key_service=$(echo "$key" | jq -r '.service_name')
        key_created=$(echo "$key" | jq -r '.created_at')
        echo "  - $key_name (Service: $key_service, Created: $key_created)"
    done < <(printf "%s\n" "${NON_ROTATED_LINES[@]}")
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Found $NON_ROTATED_COUNT non-rotated key(s)"
    fi
else
    echo -e "${BOLD}Service API keys not rotated in $ROTATION_DAYS days: 0${RESET}"
    echo -e "${BOLD}Good:${RESET} All Service API keys have been rotated within the last $ROTATION_DAYS days."
fi

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total Service IDs: $TOTAL_SERVICE_IDS"
    echo -e "${BOLD}[DEBUG]${RESET}   Total API keys: $TOTAL_API_KEYS"
    echo -e "${BOLD}[DEBUG]${RESET}   Leaked keys: ${LEAKED_COUNT:-0}"
    echo -e "${BOLD}[DEBUG]${RESET}   Non-rotated keys (>$ROTATION_DAYS days): ${#NON_ROTATED_LINES[@]}"
    echo -e "${BOLD}[DEBUG]${RESET}   Parallel workers: $MAX_PARALLEL"
fi

echo " "
echo "Completed Service API key extraction."