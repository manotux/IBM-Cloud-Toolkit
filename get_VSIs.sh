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
DEBUG=false

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'VSIs.json')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script enumerates all VSIs (IBM Cloud VMs) in each enabled IBM Cloud region."
}

while getopts ":ho:f:v" opt; do
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
METADATA_ENABLED_OUTPUT_PATH="${OUTPUT_DIR}/metadata_enabled_${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}VSIs${RESET} in all enabled IBM Cloud regions..."
echo " "
# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving regions"
fi

REGIONS=$(get_regions)
if [ "$DEBUG" = true ]; then
    REGION_COUNT=$(echo "$REGIONS" | wc -w | tr -d ' ')
    echo -e "${BOLD}[DEBUG]${RESET} Found $REGION_COUNT region(s) to process"
fi

ALL_VSI_JSON="[]"
METADATA_ENABLED_VSIS_JSON="[]"
TOTAL_VSIS=0
METADATA_ENABLED_COUNT=0
declare -A REGION_VSI_COUNTS

for region in $REGIONS; do
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Processing region: $region"
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud target -r \"$region\""
    fi
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Skipping region $region"
        fi
        continue
    fi
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud is instances --output json"
    fi
    VSI_JSON=$(ibmcloud is instances --output json 2>&1) || true
    EXIT_CODE=$?
    # Validate JSON output
    if ! echo "$VSI_JSON" | jq empty 2>/dev/null; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON response from region $region"
            echo -e "${BOLD}[DEBUG]${RESET} Response: $VSI_JSON"
        fi
        warning "Failed to retrieve valid JSON for VSIs in region $region"
        REGION_VSI_COUNTS[$region]=0
        continue
    fi
    if [ $EXIT_CODE -ne 0 ] || [[ "$VSI_JSON" =~ "FAILED" ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve VSIs for region $region"
        fi
        warning "Failed to retrieve VSIs for region $region"
        REGION_VSI_COUNTS[$region]=0
        continue
    fi
    if [[ -z "${VSI_JSON:-}" || "$VSI_JSON" == "[]" || "$VSI_JSON" == "null" ]]; then
        REGION_VSI_COUNTS[$region]=0
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: No VSIs found"
        fi
        continue
    fi
    # Extract required fields and build JSON objects
    REGION_VSI=$(echo "$VSI_JSON" | jq '[.[] | {id: .id, name: .name, region: "'$region'", image: .image.name, metadata_enabled: .metadata_service.enabled, floating_IPs: (if .network_interfaces then ([.network_interfaces[]?.floating_ips[]?.address] | join(", ")) else "" end)}]')
    VSI_COUNT=$(echo "$REGION_VSI" | jq 'length')
    REGION_VSI_COUNTS[$region]=$VSI_COUNT
    TOTAL_VSIS=$((TOTAL_VSIS + VSI_COUNT))
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $VSI_COUNT VSI(s)"
    fi
    ALL_VSI_JSON=$(jq -s 'add' <(echo "$ALL_VSI_JSON") <(echo "$REGION_VSI"))
    # Filter VSIs with metadata enabled
    REGION_METADATA_ENABLED=$(echo "$REGION_VSI" | jq '[.[] | select(.metadata_enabled == true)]')
    REGION_METADATA_COUNT=$(echo "$REGION_METADATA_ENABLED" | jq 'length')
    if [[ $REGION_METADATA_COUNT -gt 0 ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $REGION_METADATA_COUNT VSI(s) with metadata enabled"
        fi
        METADATA_ENABLED_COUNT=$((METADATA_ENABLED_COUNT + REGION_METADATA_COUNT))
        METADATA_ENABLED_VSIS_JSON=$(jq -s 'add' <(echo "$METADATA_ENABLED_VSIS_JSON") <(echo "$REGION_METADATA_ENABLED"))
    fi
    unset VSI_JSON REGION_VSI REGION_METADATA_ENABLED
done

echo " "
echo -e "${BOLD}Total VSIs: $TOTAL_VSIS${RESET}"
if [[ $METADATA_ENABLED_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}VSIs with metadata enabled: $METADATA_ENABLED_COUNT${RESET}"
else
    echo -e "${BOLD}VSIs with metadata enabled: 0${RESET}"
fi

echo " "
if [[ -z "${ALL_VSI_JSON:-}" || "$ALL_VSI_JSON" == "[]" || "$ALL_VSI_JSON" == "null" || $TOTAL_VSIS -eq 0 ]]; then
    echo "No VSIs found."
    exit 0
fi

# Display VSIs by region
echo -e "${BOLD}VSIs by region:${RESET}"
for region in $REGIONS; do
    if [[ ${REGION_VSI_COUNTS[$region]:-0} -gt 0 ]]; then
        echo -e "  ${BOLD}$region:${RESET} ${REGION_VSI_COUNTS[$region]} VSI(s)"
        # Extract and display VSI names for this region
        REGION_VSIS=$(echo "$ALL_VSI_JSON" | jq -r --arg region "$region" '.[] | select(.region == $region) | .name')
        while IFS= read -r vsi_name; do
            if [[ -n "$vsi_name" ]]; then
                # Check if this VSI has metadata enabled
                HAS_METADATA=$(echo "$ALL_VSI_JSON" | jq -r --arg region "$region" --arg name "$vsi_name" '.[] | select(.region == $region and .name == $name) | .metadata_enabled')
                if [[ "$HAS_METADATA" == "true" ]]; then
                    echo -e "    - $vsi_name ${YELLOW}(metadata enabled)${RESET}"
                else
                    echo "    - $vsi_name"
                fi
            fi
        done <<< "$REGION_VSIS"
    fi
done

echo " "
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo "$ALL_VSI_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All VSIs saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
if [[ $(echo "$METADATA_ENABLED_VSIS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$METADATA_ENABLED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$METADATA_ENABLED_OUTPUT_PATH${RESET}"
    echo "$METADATA_ENABLED_VSIS_JSON" | jq '.' > "$METADATA_ENABLED_OUTPUT_PATH"
    echo " "
    echo -e "${YELLOW}${BOLD}Warning: VSIs with metadata enabled${RESET}"
    echo -e "VSIs with metadata enabled saved to: ${BOLD}${METADATA_ENABLED_OUTPUT_PATH}${RESET}"
    echo " "
    echo -e "${BOLD}VSIs with metadata enabled:${RESET}"
    while IFS= read -r vsi; do
        vsi_name=$(echo "$vsi" | jq -r '.name')
        vsi_region=$(echo "$vsi" | jq -r '.region')
        echo "  - $vsi_name (Region: $vsi_region)"
    done < <(echo "$METADATA_ENABLED_VSIS_JSON" | jq -c '.[]')
else
    echo " "
    echo -e "${BOLD}Good:${RESET} No VSIs with metadata enabled found."
fi

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total VSIs: $TOTAL_VSIS"
    echo -e "${BOLD}[DEBUG]${RESET}   Metadata enabled: $METADATA_ENABLED_COUNT"
    if [ $TOTAL_VSIS -gt 0 ]; then
        echo -e "${BOLD}[DEBUG]${RESET}   Percentage with meta $(awk "BEGIN {printf \"%.1f\", ($METADATA_ENABLED_COUNT/$TOTAL_VSIS)*100}")%"
    fi
    echo -e "${BOLD}[DEBUG]${RESET}   VSIs by region:"
    for region in $REGIONS; do
        if [[ ${REGION_VSI_COUNTS[$region]:-0} -gt 0 ]]; then
            echo -e "${BOLD}[DEBUG]${RESET}     $region: ${REGION_VSI_COUNTS[$region]}"
        fi
    done
fi