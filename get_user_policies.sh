#!/usr/bin/env bash

# get_user_policies.sh
#
# This script identifies users with access policies assigned directly (not via groups) in the IBM Cloud account.
# For each such user, outputs their user_id and the policies in jq-formatted JSON.
# Requires IBM Cloud CLI, jq, and curl.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="user_policies.txt"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'user_policies.txt')"
    echo
    echo "This script identifies users with direct access policies in the IBM Cloud account."
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
require_curl
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating Users with ${ORANGE}${BOLD}direct access policies${RESET} in IAM..."
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
    failure "Failed to obtain IBM Cloud account ID. Make sure you are logged in."
fi

# Enumerate users
USERS_JSON=$(curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
if [[ -z "${USERS_JSON:-}" || "$USERS_JSON" == "[]" || "$USERS_JSON" == "null" ]]; then
    failure "Failed to retrieve users for account $IBMCLOUD_ACCOUNT_ID."
fi

USERS_FOUND=0
USER_POLICIES=""

while IFS= read -r user; do
    IAM_ID=("$(echo "$user" | jq -r '.iam_id')")
    USER_ID=("$(echo "$user" | jq -r '.user_id')")
    POLICIES=$(curl -s -X GET "https://iam.cloud.ibm.com/v1/policies?account_id=$IBMCLOUD_ACCOUNT_ID&iam_id=$IAM_ID" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
    if [[ $(echo "$POLICIES" | jq '.policies | length') -gt 0 ]]; then
        USERS_FOUND=1
        USER_POLICIES+="User ID: $USER_ID"$'\n'
        USER_POLICIES+="$(echo "$POLICIES" | jq '.')"$'\n\n'
    fi
done < <(echo "$USERS_JSON" | jq -c '.resources[]')

if [[ $USERS_FOUND -eq 1 ]]; then
    : > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
    echo -e "$USER_POLICIES" > "$OUTPUT_PATH"
    echo -e "Users with direct access policies saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
else
    echo "No users with direct access policies found."
fi