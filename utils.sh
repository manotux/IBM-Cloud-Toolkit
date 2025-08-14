#!/usr/bin/env bash

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

#### Terminal Colors ####
BOLD="\033[1m"
BRIGHT_RED="\033[91m"
RESET="\033[0m"

#### Variables ####

# Default output folder
OUTPUT_DIR="output"

ibmcloud_account_id(){
    ibmcloud target -o JSON|jq -r '.account.guid'
}

ibmcloud_account_name(){
    ibmcloud target -o JSON|jq -r '.account.name'
}

is_ibmcloud_logged_in() {
    ibmcloud iam oauth-tokens &>/dev/null
}

require_ibmcloud_login() {
    is_ibmcloud_logged_in || failure "IBM Cloud CLI not logged in. Please run ${BOLD}'ibmcloud login'${RESET}."
}

# Check if command exists
check_command() {
	type -P $1 &>/dev/null
}

# Check if IBM Cloud CLI is installed
require_ibmcloud() {
    check_command "ibmcloud" || failure "Unable to find the ${BOLD}IBM Cloud CLI${RESET}, please install it and run this script again."
}

# Check if IBM Cloud CLI and jq are installed
require_ibmcloud_jq() {
    check_command "ibmcloud" || failure "Unable to find the ${BOLD}IBM Cloud CLI${RESET}, please install it and run this script again."
    check_command "jq" || failure "Unable to find the ${BOLD}jq${RESET} utility, please install it and run this script again."
}

# Check if IBM Cloud VPC plugin ("is") is installed
require_ibmcloud_is() {
    if ! ibmcloud plugin list | grep -qw "vpc-infrastructure"; then
        failure "IBM Cloud VPC plugin ('is') is not installed. Please run: ibmcloud plugin install vpc-infrastructure"
    fi
}

# Failure function
failure() {
    echo -e "${BOLD}${BRIGHT_RED}FAILED: ${RESET}$*"
    exit 1
}

warning() {
    echo -e "${BOLD}WARNING: ${RESET}$*"
}

get_regions() {
    REGIONS=$(ibmcloud regions --output json | jq -r '.[].Name')
    if [ -z "$REGIONS" ]; then
        failure "No regions found. Please ensure you are logged in to IBM Cloud."
    fi
    echo "$REGIONS"
}

