#!/usr/bin/env bash

# get_custom_roles.sh
#
# This script enumerates all custom IAM roles defined in the IBM Cloud account.
# Requires IBM Cloud CLI and jq for JSON parsing.

# Load common functions and variables
srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

# Default values
OUTPUT_DIR="output"
OUTPUT_FILE="custom_roles.txt"

DEBUG=false
DEBUG_FULL=false
# Usage
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v] [-d]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'custom_roles.txt')"
    echo "  -v              Enable debug mode (outputs commands with redacted sensitive data)"
    echo "  -d              Show full debug output without redaction (requires -v)"
    echo
    echo "This script enumerates all custom IAM roles in the IBM Cloud account."
}

# Parse arguments
while getopts ":ho:f:vd" opt; do
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
# Check if IBM Cloud CLI and jq are installed
require_ibmcloud_jq

# Check if IBM Cloud CLI is logged in
require_ibmcloud_login

# Ensure output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating all ${ORANGE}${BOLD}custom IAM roles${RESET} ..."
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
    failure "Failed to obtain IBM Cloud account ID. Make sure you are logged in and targeting an account."
fi

if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Account ID: $IBMCLOUD_ACCOUNT_ID"
        echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\" \"https://iam.cloud.ibm.com/v2/roles?account_id=$IBMCLOUD_ACCOUNT_ID\""
    else
        echo -e "${BOLD}[DEBUG]${RESET} Account ID obtained"
        echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET -H \"Authorization: Bearer <redacted>\" \"https://iam.cloud.ibm.com/v2/roles?account_id=<redacted>\""
    fi
fi
# Enumerate custom roles
CUSTOM_ROLES=$(curl -s -X GET \
    -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" \
    "https://iam.cloud.ibm.com/v2/roles?account_id=$IBMCLOUD_ACCOUNT_ID" | jq '.custom_roles')

echo " "
if [[ -z "${CUSTOM_ROLES:-}" || "$CUSTOM_ROLES" == "[]" || "$CUSTOM_ROLES" == "null" ]]; then
    echo -e "${BOLD}Total custom roles found: 0${RESET}"
    echo "No custom roles found."
else
    # Count custom roles
    TOTAL_CUSTOM_ROLES=$(echo "$CUSTOM_ROLES" | jq 'length')
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Total custom roles found: $TOTAL_CUSTOM_ROLES"
    fi
    : > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
    echo "$CUSTOM_ROLES" | jq > "$OUTPUT_PATH"
    echo -e "${BOLD}Total custom roles found: $TOTAL_CUSTOM_ROLES${RESET}"
    echo -e "Output with all custom roles saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
    echo " "
    echo -e "Review custom roles for excessive privileges."
fi