#!/usr/bin/env bash

# get_mfa.sh
#
# This script retrieves the IBM Cloud account identity settings and determines the MFA requirement status.
# Requires curl, jq, and IBM Cloud API Key (IBMCLOUD_API_KEY env var).

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="account_settings.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'account_settings.json')"
    echo
    echo "This script checks the MFA requirement status for the IBM Cloud account."
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

require_jq
require_curl

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

# Check for API key
if [[ -z "${IBMCLOUD_API_KEY:-}" ]]; then
    failure "IBMCLOUD_API_KEY environment variable is not set. Please export your IBM Cloud API key as IBMCLOUD_API_KEY."
fi

# Get access token and account ID
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)

if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "${IBMCLOUD_ACCESS_TOKEN}" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token. Check your IBMCLOUD_API_KEY."
fi

IBMCLOUD_ACCOUNT_ID=$(ibmcloud_account_id)

if [[ -z "${IBMCLOUD_ACCOUNT_ID:-}" || "${IBMCLOUD_ACCOUNT_ID}" == "null" ]]; then
    failure "Failed to obtain IBM Cloud account ID."
fi

echo " "
echo "${SEPARATOR}"
echo -e "Checking IBM Cloud ${ORANGE}${BOLD}MFA Status${RESET}..."
echo " "

# Retrieve identity settings
IDENTITY_JSON=$(curl -s -X GET "https://iam.cloud.ibm.com/v1/accounts/$IBMCLOUD_ACCOUNT_ID/settings/identity" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")

if [[ -z "${IDENTITY_JSON:-}" || "${IDENTITY_JSON}" == "null" ]]; then
    failure "Failed to retrieve account identity settings."
fi

echo "$IDENTITY_JSON" | jq '.' > "$OUTPUT_PATH"

MFA_SETTING=$(echo "$IDENTITY_JSON" | jq -r '.mfa')

echo -e "Account identity settings saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
echo -e "MFA setting for account ${BOLD}${IBMCLOUD_ACCOUNT_ID}${RESET}: ${CYAN}${MFA_SETTING}${RESET}"

if [[ "$MFA_SETTING" != "TOTP4ALL" ]]; then
    echo -e "MFA might ${BOLD}not be required${RESET} for all users."
fi
