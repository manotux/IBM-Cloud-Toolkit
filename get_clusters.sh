#!/usr/bin/env bash

# get_clusters.sh
#
# This script enumerates all IBM Cloud Kubernetes/Openshift clusters using the IBM Cloud REST API and outputs them as a JSON array.
# For each cluster, it outputs: name, region, masterKubeVersion, type, serviceEndpoints.publicServiceEndpointEnabled, serviceEndpoints.publicServiceEndpointURL.
# If any cluster has public endpoint enabled, a separate output file is created with only those clusters.
# Requires curl, jq, and an authenticated IBM Cloud CLI session.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="clusters.json"

DEBUG=false
DEBUG_FULL=false
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v] [-d]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'clusters.json')"
    echo "  -v              Enable debug mode (outputs API calls with redacted sensitive data)"
    echo "  -d              Show full debug output without redaction (requires -v)"
    echo
    echo "This script enumerates all IBM Cloud Kubernetes/Openshift clusters."
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
PUBLIC_ENDPOINT_OUTPUT_PATH="${OUTPUT_DIR}/public_endpoint_${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating IBM Cloud ${ORANGE}${BOLD}Clusters${RESET}..."
echo " "

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving access token: ibmcloud iam oauth-tokens"
fi

# Get access token from ibmcloud cli session
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)

if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "${IBMCLOUD_ACCESS_TOKEN}" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token. Please ensure you are logged in with 'ibmcloud login'."
fi
if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Access token obtained: $IBMCLOUD_ACCESS_TOKEN"
        echo -e "${BOLD}[DEBUG]${RESET} Running command: curl -X GET \"https://containers.cloud.ibm.com/global/v2/vpc/getClusters\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
    else
        TOKEN_PREFIX="${IBMCLOUD_ACCESS_TOKEN:0:20}"
        echo -e "${BOLD}[DEBUG]${RESET} Access token obtained (${TOKEN_PREFIX}...) [use -d flag for full token]"
        echo -e "${BOLD}[DEBUG]${RESET} Running command: curl -X GET \"https://containers.cloud.ibm.com/global/v2/vpc/getClusters\" -H \"Authorization: Bearer <redacted>\""
    fi
fi

CLUSTERS_JSON=$(curl -s -X GET "https://containers.cloud.ibm.com/global/v2/vpc/getClusters" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")

if [[ -z "${CLUSTERS_JSON:-}" || "$CLUSTERS_JSON" == "[]" || "$CLUSTERS_JSON" == "null" ]]; then
    echo "No clusters found."
    exit 0
fi

# Count clusters
TOTAL_CLUSTERS=$(echo "$CLUSTERS_JSON" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Total clusters found: $TOTAL_CLUSTERS"
fi
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

# Extract required fields for all clusters
CLUSTERS_OUT=$(echo "$CLUSTERS_JSON" | jq '[.[] | {name, region, masterKubeVersion, type, publicServiceEndpointEnabled: .serviceEndpoints.publicServiceEndpointEnabled, publicServiceEndpointURL: .serviceEndpoints.publicServiceEndpointURL, ingress: .ingress.hostname}]')
echo "$CLUSTERS_OUT" | jq '.' > "$OUTPUT_PATH"
echo -e "${BOLD}Total clusters found: $TOTAL_CLUSTERS${RESET}"
echo -e "All clusters saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

# Filter clusters with public endpoint enabled
PUBLIC_CLUSTERS=$(echo "$CLUSTERS_OUT" | jq '[.[] | select(.publicServiceEndpointEnabled == true)]')
PUBLIC_COUNT=$(echo "$PUBLIC_CLUSTERS" | jq 'length')
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Clusters with public endpoint: $PUBLIC_COUNT"
fi
if [[ $PUBLIC_COUNT -gt 0 ]]; then
    : > "$PUBLIC_ENDPOINT_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_ENDPOINT_OUTPUT_PATH${RESET}"
    echo "$PUBLIC_CLUSTERS" | jq '.' > "$PUBLIC_ENDPOINT_OUTPUT_PATH"
    echo -e "${BOLD}Clusters with public endpoint: $PUBLIC_COUNT${RESET}"
    echo -e "Clusters with public endpoint saved to: ${BOLD}${PUBLIC_ENDPOINT_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Clusters with public endpoint: 0${RESET}"
fi