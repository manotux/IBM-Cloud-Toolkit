#!/usr/bin/env bash

# get_VSIs.sh
#
# This script enumerates all VSIs (IBM Cloud VMs) in each enabled IBM Cloud region and outputs them as a JSON array.
# For each VSI, it outputs: id, name, image, metadata_enabled, and floating_IPs.
# If any VSI has metadata enabled, a separate output file is created with only those VSIs.
# Requires IBM Cloud CLI and vpc-infrastructure ("is") plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="VSIs.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'VSIs.json')"
    echo
    echo "This script enumerates all VSIs (IBM Cloud VMs) in each enabled IBM Cloud region."
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
require_ibmcloud_login
require_ibmcloud_is

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
METADATA_ENABLED_OUTPUT_PATH="${OUTPUT_DIR}/metadata_enabled_${OUTPUT_FILE}"
: > "$METADATA_ENABLED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$METADATA_ENABLED_OUTPUT_PATH${RESET}"

echo " "
echo "============================================================"
echo "Enumerating VSIs in all enabled IBM Cloud regions..."

REGIONS=$(get_regions)
ALL_VSI_JSON="[]"
METADATA_ENABLED_VSIS_JSON="[]"

for region in $REGIONS; do
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        continue
    fi
    VSI_JSON=$(ibmcloud is instances --output json 2>/dev/null) || { warning "Failed to retrieve VSIs for region $region"; continue; }

    if [[ -z "$VSI_JSON" || "$VSI_JSON" == "[]" ]]; then
        continue
    fi
    # Extract required fields and build JSON objects
    REGION_VSI=$(echo "$VSI_JSON" | jq '[.[] | {id: .id, name: .name, image: .image.name, metadata_enabled: .metadata_service.enabled, floating_IPs: (if .network_interfaces then ([.network_interfaces[]?.floating_ips[]?.address] | join(", ")) else "" end)}]')
    ALL_VSI_JSON=$(jq -s 'add' <(echo "$ALL_VSI_JSON") <(echo "$REGION_VSI"))
    # Filter VSIs with metadata enabled
    REGION_METADATA_ENABLED=$(echo "$REGION_VSI" | jq '[.[] | select(.metadata_enabled == true)]')
    if [[ $(echo "$REGION_METADATA_ENABLED" | jq 'length') -gt 0 ]]; then
        METADATA_ENABLED_VSIS_JSON=$(jq -s 'add' <(echo "$METADATA_ENABLED_VSIS_JSON") <(echo "$REGION_METADATA_ENABLED"))
    fi
    unset VSI_JSON REGION_VSI REGION_METADATA_ENABLED
done

echo "$ALL_VSI_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All VSIs saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

if [[ $(echo "$METADATA_ENABLED_VSIS_JSON" | jq 'length') -gt 0 ]]; then
    echo "$METADATA_ENABLED_VSIS_JSON" | jq '.' > "$METADATA_ENABLED_OUTPUT_PATH"
    echo -e "VSIs with metadata enabled saved to: ${BOLD}${METADATA_ENABLED_OUTPUT_PATH}${RESET}"
else
    rm -f "$METADATA_ENABLED_OUTPUT_PATH"
    echo "No VSIs with metadata enabled found."
fi

