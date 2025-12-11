#!/usr/bin/env bash

# get_clusters.sh
#
# This script enumerates all IBM Cloud Kubernetes/Openshift clusters using the IBM Cloud REST API and outputs them as a JSON array.
# For each cluster, it outputs: name, region, masterKubeVersion, type, serviceEndpoints.publicServiceEndpointEnabled, serviceEndpoints.publicServiceEndpointURL.
# If any cluster has public endpoint enabled, a separate output file is created with only those clusters.
# Requires curl, jq, and IBM Cloud API Key (IBMCLOUD_API_KEY env var).

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="clusters.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'clusters.json')"
    echo
    echo "This script enumerates all IBM Cloud Kubernetes/Openshift clusters."
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
PUBLIC_ENDPOINT_OUTPUT_PATH="${OUTPUT_DIR}/public_endpoint_${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating IBM Cloud ${ORANGE}${BOLD}Clusters${RESET}..."
echo " "

# Check for API key
if [[ -z "${IBMCLOUD_API_KEY:-}" ]]; then
    failure "IBMCLOUD_API_KEY environment variable is not set. Please export your IBM Cloud API key as IBMCLOUD_API_KEY."
fi

# Get access token
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)

if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "${IBMCLOUD_ACCESS_TOKEN}" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token. Check your IBMCLOUD_API_KEY."
fi

CLUSTERS_JSON=$(curl -s -X GET "https://containers.cloud.ibm.com/global/v2/vpc/getClusters" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")

if [[ -z "${CLUSTERS_JSON:-}" || "$CLUSTERS_JSON" == "[]" || "$CLUSTERS_JSON" == "null" ]]; then
    echo "No clusters found."
    exit 0
fi

: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

# Extract required fields for all clusters
CLUSTERS_OUT=$(echo "$CLUSTERS_JSON" | jq '[.[] | {name, region, masterKubeVersion, type, publicServiceEndpointEnabled: .serviceEndpoints.publicServiceEndpointEnabled, publicServiceEndpointURL: .serviceEndpoints.publicServiceEndpointURL, ingress: .ingress.hostname}]')
echo "$CLUSTERS_OUT" | jq '.' > "$OUTPUT_PATH"
echo -e "All clusters saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

# Filter clusters with public endpoint enabled
PUBLIC_CLUSTERS=$(echo "$CLUSTERS_OUT" | jq '[.[] | select(.publicServiceEndpointEnabled == true)]')
if [[ $(echo "$PUBLIC_CLUSTERS" | jq 'length') -gt 0 ]]; then
    : > "$PUBLIC_ENDPOINT_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_ENDPOINT_OUTPUT_PATH${RESET}"
    echo "$PUBLIC_CLUSTERS" | jq '.' > "$PUBLIC_ENDPOINT_OUTPUT_PATH"
    echo -e "Clusters with public endpoint saved to: ${BOLD}${PUBLIC_ENDPOINT_OUTPUT_PATH}${RESET}"
else
    echo "No clusters with public endpoint enabled found."
fi
