#!/usr/bin/env bash

# get_mfa.sh
#
# This script retrieves the IBM Cloud account identity settings and determines the MFA requirement status.
# Requires curl, jq, and an authenticated IBM Cloud CLI session.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="account_settings.json"

DEBUG=false
DEBUG_FULL=false
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v] [-d]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'account_settings.json')"
    echo "  -v              Enable debug mode (outputs commands with redacted sensitive data)"
    echo "  -d              Show full debug output without redaction (requires -v)"
    echo
    echo "This script checks the MFA requirement status for the IBM Cloud account."
}

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
require_jq
require_curl
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Checking IBM Cloud ${ORANGE}${BOLD}MFA Status${RESET}..."
echo " "
# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving access token"
fi

# Get access token and account ID
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)

if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "${IBMCLOUD_ACCESS_TOKEN}" == "null" ]]; then
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

IBMCLOUD_ACCOUNT_ID=$(ibmcloud_account_id)

if [[ -z "${IBMCLOUD_ACCOUNT_ID:-}" || "${IBMCLOUD_ACCOUNT_ID}" == "null" ]]; then
    failure "Failed to obtain IBM Cloud account ID."
fi

if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Account ID: $IBMCLOUD_ACCOUNT_ID"
        echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://iam.cloud.ibm.com/v1/accounts/$IBMCLOUD_ACCOUNT_ID/settings/identity\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
    else
        echo -e "${BOLD}[DEBUG]${RESET} Account ID obtained"
        echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://iam.cloud.ibm.com/v1/accounts/<redacted>/settings/identity\" -H \"Authorization: Bearer <redacted>\""
    fi
fi
# Retrieve identity settings
IDENTITY_JSON=$(curl -s -X GET "https://iam.cloud.ibm.com/v1/accounts/$IBMCLOUD_ACCOUNT_ID/settings/identity" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")

if [[ -z "${IDENTITY_JSON:-}" || "${IDENTITY_JSON}" == "null" ]]; then
    failure "Failed to retrieve account identity settings."
fi

: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo "$IDENTITY_JSON" | jq '.' > "$OUTPUT_PATH"

# Check account MFA setting and if there are user-specific MFA settings
MFA_SETTING=$(echo "$IDENTITY_JSON" | jq -r '.mfa')
USER_MFA_COUNT=$(echo "$IDENTITY_JSON" | jq '.user_mfa | length')

echo " "
echo -e "${BOLD}MFA Configuration:${RESET}"
echo -e "  Account: ${BOLD}${IBMCLOUD_ACCOUNT_ID}${RESET}"
echo -e "  MFA Setting: ${CYAN}${BOLD}${MFA_SETTING}${RESET}"
if [[ "$MFA_SETTING" != "TOTP4ALL" ]]; then
    echo -e "  ${YELLOW}${BOLD}Warning:${RESET} MFA might ${BOLD}not be required${RESET} for all users"
else
    echo -e "  ${BOLD}Status:${RESET} MFA is required for all users"
fi

if [[ "$USER_MFA_COUNT" -gt 0 ]]; then
    echo -e "  User-specific MFA settings: ${BOLD}${USER_MFA_COUNT}${RESET}"
    echo " "
    echo -e "${YELLOW}${BOLD}Note:${RESET} There are user-specific MFA configurations. Review the output file for details."
else
    echo -e "  User-specific MFA settings: ${BOLD}0${RESET}"
fi
echo " "
echo -e "Account identity settings saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   MFA Setting: $MFA_SETTING"
    echo -e "${BOLD}[DEBUG]${RESET}   User-specific settings: $USER_MFA_COUNT"
    echo -e "${BOLD}[DEBUG]${RESET}   MFA Required for all: $([ "$MFA_SETTING" = "TOTP4ALL" ] && echo "Yes" || echo "No")"
fi