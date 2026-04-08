#!/usr/bin/env bash

# get_users.sh
#
# This script retrieves the list of users in the IBM Cloud account and outputs them to users.txt with fields:
# iam_id, user_id, email, state, last_activity
# If there are any users not in ACTIVE status, outputs them to inactive_users.txt with the same fields.
# Requires IBM Cloud CLI, jq, and curl.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"
OUTPUT_DIR="output"
OUTPUT_FILE="users.txt"
DEBUG=false
DEBUG_FULL=false
MAX_PARALLEL=10  # Number of parallel API calls

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-p MAX_PARALLEL] [-v] [-d]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'users.txt')"
    echo "  -p MAX_PARALLEL Number of parallel API calls (default: 10)"
    echo "  -v              Enable debug mode (outputs commands with redacted sensitive data)"
    echo "  -d              Show full debug output without redaction (requires -v)"
    echo
    echo "This script retrieves all users and outputs inactive users if any."
}

while getopts ":ho:f:p:vd" opt; do
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
        p)
            MAX_PARALLEL="$OPTARG"
            ;;
        v)
            DEBUG=true
            ;;
        d)
            DEBUG_FULL=true
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

# Check if -d is used without -v
if [ "$DEBUG_FULL" = true ] && [ "$DEBUG" = false ]; then
    echo "Error: -d flag requires -v flag to be set" >&2
    usage
    exit 1
fi

require_ibmcloud_jq
require_curl
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
INACTIVE_PATH="${OUTPUT_DIR}/inactive_${OUTPUT_FILE}"
TEMP_DIR="${OUTPUT_DIR}/.tmp_users_$$"

# Create temp directory for parallel processing
mkdir -p "$TEMP_DIR" || failure "Failed to create temporary directory"
# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
echo " "
echo "${SEPARATOR}"
echo -e "Enumerating all ${ORANGE}${BOLD}Users${RESET} in IAM..."
echo " "

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving access token"
fi

# Get access token
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)
if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "$IBMCLOUD_ACCESS_TOKEN" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token."
fi
if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Access token: $IBMCLOUD_ACCESS_TOKEN"
    else
        TOKEN_PREFIX="${IBMCLOUD_ACCESS_TOKEN:0:20}"
        echo -e "${BOLD}[DEBUG]${RESET} Access token obtained (${TOKEN_PREFIX}...) [use -d flag for full token]"
    fi
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving account ID"
fi

# Retrieve account ID
IBMCLOUD_ACCOUNT_ID=$(ibmcloud_account_id)
if [[ -z "${IBMCLOUD_ACCOUNT_ID:-}" || "$IBMCLOUD_ACCOUNT_ID" == "null" ]]; then
    failure "Failed to obtain IBM Cloud account ID. Make sure you are logged in."
fi
if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Account ID: $IBMCLOUD_ACCOUNT_ID"
    else
        echo -e "${BOLD}[DEBUG]${RESET} Account ID obtained"
    fi
fi

# Get all users with pagination
if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Starting pagination: curl -X GET \"https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
    else
        echo -e "${BOLD}[DEBUG]${RESET} Starting pagination: curl -X GET \"https://iam.cloud.ibm.com/v2/accounts/<redacted>/users\" -H \"Authorization: Bearer <redacted>\""
    fi
fi

USERS_JSON_ALL="[]"
NEXT_URL="https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users"
PAGE_COUNT=0
while [[ -n "$NEXT_URL" ]]; do
    PAGE_COUNT=$((PAGE_COUNT + 1))
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Fetching page $PAGE_COUNT"
    fi
    RESPONSE=$(curl -s -X GET "$NEXT_URL" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
    # Validate JSON
    if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON response on page $PAGE_COUNT"
            echo -e "${BOLD}[DEBUG]${RESET} Response: $RESPONSE"
        fi
        failure "Failed to retrieve valid JSON for users."
    fi
    # Append resources from this page
    PAGE_USERS=$(echo "$RESPONSE" | jq '.resources')
    PAGE_USER_COUNT=$(echo "$PAGE_USERS" | jq 'length')
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Page $PAGE_COUNT: Retrieved $PAGE_USER_COUNT user(s)"
    fi
    USERS_JSON_ALL=$(jq -s '.[0] + .[1]' <(echo "$USERS_JSON_ALL") <(echo "$PAGE_USERS"))
    # Check for next_url
    NEXT_URL_PATH=$(echo "$RESPONSE" | jq -r '.next_url // empty')
    if [[ -n "$NEXT_URL_PATH" ]]; then
        NEXT_URL="https://iam.cloud.ibm.com$NEXT_URL_PATH"
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} More pages available"
        fi
    else
        NEXT_URL=""
    fi
done

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Pagination complete: $PAGE_COUNT page(s)"
fi

USERS_JSON=$(jq -n --argjson arr "$USERS_JSON_ALL" '{resources: $arr}')
if [[ -z "${USERS_JSON_ALL:-}" || "$USERS_JSON_ALL" == "[]" || "$USERS_JSON_ALL" == "null" ]]; then
    failure "Failed to retrieve users for account $IBMCLOUD_ACCOUNT_ID."
fi

# Count users
TOTAL_USERS=$(echo "$USERS_JSON_ALL" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Total users retrieved: $TOTAL_USERS"
    echo -e "${BOLD}[DEBUG]${RESET} Using $MAX_PARALLEL parallel workers"
fi

echo -e "${BOLD}Total users: $TOTAL_USERS${RESET}"
echo -e "Fetching activity data for each user (using $MAX_PARALLEL parallel workers)..."
echo " "
# Function to fetch user details
fetch_user_details() {
    local user="$1"
    local user_index="$2"
    local temp_dir="$3"
    local account_id="$4"
    local access_token="$5"
    local debug_mode="$6"
    local debug_full_mode="$7"
    local iam_id=$(echo "$user" | jq -r '.iam_id')
    local user_id=$(echo "$user" | jq -r '.user_id')
    local email=$(echo "$user" | jq -r '.email')
    local state=$(echo "$user" | jq -r '.state')
    if [ "$debug_mode" = "true" ] && [ "$debug_full_mode" = "true" ]; then
        echo "[DEBUG] Processing user: $user_id (IAM ID: $iam_id)" >&2
    fi
    # Fetch last_activity for this user
    local user_activity_json=$(curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$account_id/users/$iam_id?include_activity=true" -H "Authorization: Bearer $access_token")
    # Validate JSON
    local last_activity
    if ! echo "$user_activity_json" | jq empty 2>/dev/null; then
        last_activity="unknown"
    else
        last_activity=$(echo "$user_activity_json" | jq -r '.activity // "none"')
    fi
    # Create user JSON and save to temp file
    local iam_user=$(jq -n --arg iam_id "$iam_id" --arg user_id "$user_id" --arg email "$email" --arg state "$state" --arg last_activity "$last_activity" '{iam_id: $iam_id, user_id: $user_id, email: $email, state: $state, last_activity: $last_activity}')
    echo "$iam_user" > "${temp_dir}/${user_index}.json"
}

# Export function and variables for parallel execution
export -f fetch_user_details
export IBMCLOUD_ACCOUNT_ID
export IBMCLOUD_ACCESS_TOKEN
export DEBUG
export DEBUG_FULL
export TEMP_DIR

# Process users in parallel
USER_INDEX=0
RUNNING_JOBS=0
while IFS= read -r user; do
    USER_INDEX=$((USER_INDEX + 1))
    # Launch background job
    fetch_user_details "$user" "$USER_INDEX" "$TEMP_DIR" "$IBMCLOUD_ACCOUNT_ID" "$IBMCLOUD_ACCESS_TOKEN" "$DEBUG" "$DEBUG_FULL" &
    RUNNING_JOBS=$((RUNNING_JOBS + 1))
    # Wait if we've reached max parallel jobs
    if [ $RUNNING_JOBS -ge $MAX_PARALLEL ]; then
        wait -n  # Wait for any job to complete
        RUNNING_JOBS=$((RUNNING_JOBS - 1))
    fi
    # Show progress every 10 users (only in non-debug mode)
    if [ "$DEBUG" = false ] && [ $((USER_INDEX % 10)) -eq 0 ]; then
        echo -ne "\rProcessed: $USER_INDEX/$TOTAL_USERS users..."
    fi
done < <(echo "$USERS_JSON" | jq -c '.resources[]')

# Wait for all remaining jobs to complete
wait
if [ "$DEBUG" = false ]; then
    echo -e "\rProcessed: $TOTAL_USERS/$TOTAL_USERS users... Done!"
fi

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} All parallel jobs completed"
fi

# Aggregate results
echo " "
echo "Aggregating results..."
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
ACTIVE_COUNT=0
VPN_ONLY_COUNT=0
INACTIVE_COUNT=0
INACTIVE_USERS=()

# Process results in order
for i in $(seq 1 $TOTAL_USERS); do
    if [ -f "${TEMP_DIR}/${i}.json" ]; then
        IAM_USER=$(cat "${TEMP_DIR}/${i}.json")
        echo "${IAM_USER}" | jq >> "$OUTPUT_PATH"
        state=$(echo "$IAM_USER" | jq -r '.state')
        # Count by state
        if [[ "$state" == "ACTIVE" ]]; then
            ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        elif [[ "$state" == "VPN_ONLY" ]]; then
            VPN_ONLY_COUNT=$((VPN_ONLY_COUNT + 1))
        else
            INACTIVE_COUNT=$((INACTIVE_COUNT + 1))
            INACTIVE_USERS+=("${IAM_USER}")
        fi
    fi
done

echo " "
echo -e "${BOLD}User Statistics:${RESET}"
echo -e "  Active users: ${BOLD}$ACTIVE_COUNT${RESET}"
echo -e "  VPN only users: ${BOLD}$VPN_ONLY_COUNT${RESET}"
echo -e "  Inactive users: ${BOLD}$INACTIVE_COUNT${RESET}"
echo " "
echo -e "All users saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
if [[ $INACTIVE_COUNT -gt 0 ]]; then
    : > "$INACTIVE_PATH" || failure "Error while creating the output file: ${BOLD}$INACTIVE_PATH${RESET}"
    printf "%s\n" "${INACTIVE_USERS[@]}" | jq -s '.' > "$INACTIVE_PATH"
    echo " "
    echo -e "${YELLOW}${BOLD}Warning:${RESET} Inactive users found"
    echo -e "Inactive users saved to: ${BOLD}${INACTIVE_PATH}${RESET}"
    echo " "
    echo -e "${BOLD}Inactive users:${RESET}"
    for inactive_user_json in "${INACTIVE_USERS[@]}"; do
        user_email=$(echo "$inactive_user_json" | jq -r '.email')
        user_state=$(echo "$inactive_user_json" | jq -r '.state')
        echo "  - $user_email (State: $user_state)"
    done
else
    echo " "
    echo -e "${BOLD}Good:${RESET} No inactive users found."
fi

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total users: $TOTAL_USERS"
    if [ $TOTAL_USERS -gt 0 ]; then
        echo -e "${BOLD}[DEBUG]${RESET}   Active: $ACTIVE_COUNT ($(awk "BEGIN {printf \"%.1f\", ($ACTIVE_COUNT/$TOTAL_USERS)*100}")%)"
        echo -e "${BOLD}[DEBUG]${RESET}   VPN only: $VPN_ONLY_COUNT ($(awk "BEGIN {printf \"%.1f\", ($VPN_ONLY_COUNT/$TOTAL_USERS)*100}")%)"
        echo -e "${BOLD}[DEBUG]${RESET}   Inactive: $INACTIVE_COUNT ($(awk "BEGIN {printf \"%.1f\", ($INACTIVE_COUNT/$TOTAL_USERS)*100}")%)"
    fi
    echo -e "${BOLD}[DEBUG]${RESET}   Pages fetched: $PAGE_COUNT"
    echo -e "${BOLD}[DEBUG]${RESET}   Parallel workers: $MAX_PARALLEL"
fi
