#!/usr/bin/env bash

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

#### Terminal Colors ####
BOLD="\033[1m"
BRIGHT_RED="\033[91m"
RESET="\033[0m"
CYAN="\033[36m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
ORANGE="\033[38;5;208m"
BLUE="\033[34m"


#### Variables ####

# Default output folder
OUTPUT_DIR="output"

SEPARATOR="=================================================================================="

ibmcloud_account_id(){
    ibmcloud target -o JSON|jq -r '.account.guid'
}

ibmcloud_access_token(){
    curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" https://iam.cloud.ibm.com/identity/token | jq -r '.access_token'
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

# Check if jq is installed
require_jq() {
    check_command "jq" || failure "Unable to find the ${BOLD}jq${RESET} utility, please install it and run this script again."
}

# Check if curl is installed
require_curl() {
    check_command "curl" || failure "Unable to find the ${BOLD}curl${RESET} utility, please install it and run this script again."
}

# Check if IBM Cloud VPC plugin ("is") is installed
require_ibmcloud_is() {
    if ! ibmcloud plugin list | grep -qw "vpc-infrastructure"; then
        failure "IBM Cloud VPC plugin ('is') is not installed. Please run: ibmcloud plugin install vpc-infrastructure"
    fi
}

# Check if IBM Cloud Classic Infrastructure plugin ("sl") is installed
require_ibmcloud_sl() {
    if ! ibmcloud plugin list | grep -qw "sl"; then
        failure "IBM Cloud Classic Infrastructure plugin ('sl') is not installed. Please run: ibmcloud plugin install sl"
    fi
}

# Check if IBM Cloud cloud-databases plugin ("cdb") is installed
require_ibmcloud_cdb() {
    if ! ibmcloud plugin list | grep -qw "cloud-databases"; then
        failure "IBM Cloud databases plugin ('cdb') is not installed. Please run: ibmcloud plugin install cloud-databases"
    fi
}

# Check if IBM Cloud schematics plugin ("sch") is installed
require_ibmcloud_schematics() {
    if ! ibmcloud plugin list | grep -qw "schematics"; then
        failure "IBM Cloud schematics plugin ('sch') is not installed. Please run: ibmcloud plugin install schematics"
    fi
}

require_ibmcloud_cos() {
    if ! ibmcloud plugin list | grep -qw "cloud-object-storage"; then
        failure "IBM Cloud cloud-object-storage plugin is not installed. Please run: ibmcloud plugin install cloud-object-storage"
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
    REGIONS=$(ibmcloud regions --output json | jq -r '.[].Name') || failure "Could not retrieve regions. Retry."
    if [[ -z "${REGIONS:-}" ]]; then
        failure "No regions found. Please ensure you are logged in to IBM Cloud."
    fi
    echo "$REGIONS"
}