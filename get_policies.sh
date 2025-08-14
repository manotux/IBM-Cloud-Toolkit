

### PENDING ###

# check if IBMCLOUD_API_KEY is set as envvar or provided in the command line as argument for the script

############




#!/usr/bin/env bash

# get_policies.sh
#
# This script retrieves all access policies in the IBM Cloud account and outputs them in a readable format.
# It also identifies policies assigned directly to users (not via groups).
# Requires IBM Cloud CLI and jq for JSON parsing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="access_policies.txt"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name for all policies (default: 'access_policies.txt')"
    echo
    echo "This script retrieves all access policies and those assigned directly to users in the IBM Cloud account."
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

# Check if IBM Cloud CLI and jq are installed
require_ibmcloud_jq

# Check if IBM Cloud CLI is logged in
require_ibmcloud_login

# Ensure output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

# Prepare output file
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

# Prepare output for user access policies
USER_POLICIES_PATH="${OUTPUT_DIR}/user_${OUTPUT_FILE}"
: > "$USER_POLICIES_PATH" || failure "Error while creating the output file: ${BOLD}$USER_POLICIES_PATH${RESET}"

echo " "
echo "====================================================="
echo "Retrieving all access policies in IBM Cloud account..."

IBMCLOUD_ACCESS_TOKEN=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" https://iam.cloud.ibm.com/identity/token | jq -r '.access_token')
IBMCLOUD_ACCOUNT_ID=$(ibmcloud target -o JSON | jq -r '.account.guid')

# Get all access policies
curl -s -X GET "https://iam.cloud.ibm.com/v1/policies?account_id=$IBMCLOUD_ACCOUNT_ID" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq '.' | tee "$OUTPUT_PATH"

echo
echo "All access policies saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

echo
echo "Retrieving policies assigned directly to users..."

curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -c '.resources[]' | while read user; do
    iam_id=$(echo $user | jq -r '.iam_id')
    user_id=$(echo $user | jq -r '.user_id')
    policies=$(curl -s -X GET "https://iam.cloud.ibm.com/v1/policies?account_id=$IBMCLOUD_ACCOUNT_ID&iam_id=$iam_id" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
    if [ "$policies" = '{"policies":[]}' ]; then
        continue
    fi
    echo "User ID: $user_id" | tee -a "$USER_POLICIES_PATH"
    echo "$policies" | tee -a "$USER_POLICIES_PATH"
    echo | tee -a "$USER_POLICIES_PATH"
done

echo
echo "User-specific access policies saved to: ${BOLD}${USER_POLICIES_PATH}${RESET}"
echo "====================================================="

