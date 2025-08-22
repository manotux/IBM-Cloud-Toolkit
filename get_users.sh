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

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'users.txt')"
    echo
    echo "This script retrieves all users and outputs inactive users if any."
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
            INACTIVE_FILE="inactive_${OUTPUT_FILE}"
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
require_curl
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
INACTIVE_PATH="${OUTPUT_DIR}/inactive_${OUTPUT_FILE}"
: > "$INACTIVE_PATH" || failure "Error while creating the output file: ${BOLD}$INACTIVE_PATH${RESET}"

echo " "
echo "${SEPARATOR}"
echo "Retrieving all users in IBM Cloud account..."
echo " "

# Check for API key
if [[ -z "${IBMCLOUD_API_KEY:-}" ]]; then
    failure "IBMCLOUD_API_KEY environment variable is not set. Please export your IBM Cloud API key as IBMCLOUD_API_KEY."
fi

# Get access token
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)
if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "$IBMCLOUD_ACCESS_TOKEN" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token. Check IBMCLOUD_API_KEY."
fi

# Retrieve account ID
IBMCLOUD_ACCOUNT_ID=$(ibmcloud_account_id)
if [[ -z "${IBMCLOUD_ACCOUNT_ID:-}" || "$IBMCLOUD_ACCOUNT_ID" == "null" ]]; then
    failure "Failed to obtain IBM Cloud account ID. Make sure you are logged."
fi

# Get all users

# Pagination: fetch all users
USERS_JSON_ALL="[]"
NEXT_URL="https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users"
while [[ -n "$NEXT_URL" ]]; do
    RESPONSE=$(curl -s -X GET "$NEXT_URL" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
    # Append resources from this page
    PAGE_USERS=$(echo "$RESPONSE" | jq '.resources')
    USERS_JSON_ALL=$(jq -s '.[0] + .[1]' <(echo "$USERS_JSON_ALL") <(echo "$PAGE_USERS"))
    # Check for next_url
    NEXT_URL_PATH=$(echo "$RESPONSE" | jq -r '.next_url // empty')
    if [[ -n "$NEXT_URL_PATH" ]]; then
        # next_url is a relative path, must append to base
        NEXT_URL="https://iam.cloud.ibm.com$NEXT_URL_PATH"
    else
        NEXT_URL=""
    fi
done

USERS_JSON=$(jq -n --argjson arr "$USERS_JSON_ALL" '{resources: $arr}')
if [[ -z "${USERS_JSON_ALL:-}" || "$USERS_JSON_ALL" == "[]" || "$USERS_JSON_ALL" == "null" ]]; then
    failure "Failed to retrieve users for account $IBMCLOUD_ACCOUNT_ID."
fi

USERS_FOUND=0
INACTIVE_FOUND=0

while IFS= read -r user; do
    iam_id=$(echo "$user" | jq -r '.iam_id')
    user_id=$(echo "$user" | jq -r '.user_id')
    email=$(echo "$user" | jq -r '.email')
    state=$(echo "$user" | jq -r '.state')

    # Fetch last_activity for this user
    user_activity_json=$(curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users/$iam_id?include_activity=true" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
    last_activity=$(echo "$user_activity_json" | jq -r '.activity // empty')

    jq -n --arg iam_id "$iam_id" --arg user_id "$user_id" --arg email "$email" --arg state "$state" --arg last_activity "$last_activity" '{iam_id: $iam_id, user_id: $user_id, email: $email, state: $state, last_activity: $last_activity}' >> "$OUTPUT_PATH"
    USERS_FOUND=1
    if [[ "$state" != "ACTIVE" ]]; then
        jq -n --arg iam_id "$iam_id" --arg user_id "$user_id" --arg email "$email" --arg state "$state" --arg last_activity "$last_activity" '{iam_id: $iam_id, user_id: $user_id, email: $email, state: $state, last_activity: $last_activity}' >> "$INACTIVE_PATH"
        INACTIVE_FOUND=1
    fi
done < <(echo "$USERS_JSON" | jq -c '.resources[]')

if [[ $USERS_FOUND -eq 1 ]]; then
    echo -e "All users saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
else
    echo "No users found."
    rm -f "$OUTPUT_PATH"
fi

if [[ $INACTIVE_FOUND -eq 1 ]]; then
    echo -e "Inactive users saved to: ${BOLD}${INACTIVE_PATH}${RESET}"
else
    rm -f "$INACTIVE_PATH"
    echo "No inactive users found."
fi

echo "${SEPARATOR}"


