#!/usr/bin/env bash

# get_security_groups.sh
#
# This script enumerates all VPC and Classic Infrastructure security groups in each enabled IBM Cloud region.
# For VPC:
#   - Outputs all security groups to security_groups.json
#   - Outputs only those with overly permissive inbound rules (0.0.0.0/0) to security_groups_unrestricted.json
# For Classic Infrastructure:
#   - Outputs all security groups to security_groups_classic.json
#   - Outputs only those with overly permissive inbound rules (0.0.0.0/0) to security_groups_classic_unrestricted.json
# Requires IBM Cloud CLI and vpc-infrastructure ("is") plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo
    echo "This script enumerates IBM Cloud VPC and Classic Infrastructure security groups."
}

while getopts ":ho:" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
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
require_ibmcloud_sl

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

VPC_OUTPUT_PATH="${OUTPUT_DIR}/security_groups.json"
VPC_UNRESTRICTED_OUTPUT_PATH="${OUTPUT_DIR}/security_groups_unrestricted.json"
CLASSIC_OUTPUT_PATH="${OUTPUT_DIR}/security_groups_classic.json"
CLASSIC_UNRESTRICTED_OUTPUT_PATH="${OUTPUT_DIR}/security_groups_classic_unrestricted.json"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}VPC Security Groups${RESET} in all enabled IBM Cloud regions..."
echo " "

REGIONS=$(get_regions)
ALL_VPC_JSON="[]"
ALL_VPC_UNRESTRICTED_JSON="[]"

for region in $REGIONS; do
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        continue
    fi
    SG_JSON=$(ibmcloud is security-groups --all-resource-groups --output json 2>/dev/null) || { warning "Failed to retrieve VPC security groups for region $region"; continue; }

    if [[ -z "${SG_JSON:-}" || "$SG_JSON" == "[]" || "$SG_JSON" == "null" ]]; then
        continue
    fi

    REGION_SG=$(echo "$SG_JSON" | jq '[.[] | {region: "'$region'", name: .name, id: .id, rules: .rules}]')
    ALL_VPC_JSON=$(jq -s 'add' <(echo "$ALL_VPC_JSON") <(echo "$REGION_SG"))

    REGION_UNRESTRICTED=$(echo "$REGION_SG" | jq '[.[] | {region, name, rules: [.rules[] | select(.direction=="inbound" and .remote.cidr_block=="0.0.0.0/0")]} | select(.rules|length>0)]')
    if [[ $(echo "$REGION_UNRESTRICTED" | jq 'length') -gt 0 ]]; then
        ALL_VPC_UNRESTRICTED_JSON=$(jq -s 'add' <(echo "$ALL_VPC_UNRESTRICTED_JSON") <(echo "$REGION_UNRESTRICTED"))
    fi
    unset SG_JSON REGION_SG REGION_UNRESTRICTED
done

if [[ $(echo "$ALL_VPC_JSON" | jq 'length') -gt 0 ]]; then
    : > "$VPC_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$VPC_OUTPUT_PATH${RESET}"
    echo "$ALL_VPC_JSON" | jq '.' > "$VPC_OUTPUT_PATH"
    echo -e "All VPC Security Groups saved to: ${BOLD}${VPC_OUTPUT_PATH}${RESET}"

    if [[ $(echo "$ALL_VPC_UNRESTRICTED_JSON" | jq 'length') -gt 0 ]]; then
        : > "$VPC_UNRESTRICTED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$VPC_UNRESTRICTED_OUTPUT_PATH${RESET}"
        echo "$ALL_VPC_UNRESTRICTED_JSON" | jq '.' > "$VPC_UNRESTRICTED_OUTPUT_PATH"
        echo -e "VPC Security Groups with unrestricted inbound rules saved to: ${BOLD}${VPC_UNRESTRICTED_OUTPUT_PATH}${RESET}"
    fi
else
    echo "No VPC Security Groups found."
fi

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}Classic Infrastructure Security Groups${RESET}..."
echo " "

CLASSIC_JSON="[]"

CLASSIC_SG_JSON=$(ibmcloud sl securitygroup list --output json 2>/dev/null) || { warning "Failed to retrieve Classic Infrastructure security groups"; CLASSIC_SG_JSON="[]"; }

if [[ -n "${CLASSIC_SG_JSON:-}" && "$CLASSIC_SG_JSON" != "[]" && "$CLASSIC_SG_JSON" != "null" ]]; then
    CLASSIC_JSON="$CLASSIC_SG_JSON"

    # CLASSIC_UNRESTRICTED=$(echo "$CLASSIC_SG_JSON" | jq '[.[] | {name, id, rules: [.rules[]? | select(.direction=="inbound" and .remoteIp=="0.0.0.0")]} | select(.rules|length>0)]')

    if [[ $(echo "$CLASSIC_JSON" | jq 'length') -gt 0 ]]; then
        : > "$CLASSIC_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CLASSIC_OUTPUT_PATH${RESET}"
        echo "$CLASSIC_JSON" | jq '.' > "$CLASSIC_OUTPUT_PATH"
        echo -e "All Classic Infrastructure Security Groups saved to: ${BOLD}${CLASSIC_OUTPUT_PATH}${RESET}"

        # if [[ $(echo "$CLASSIC_UNRESTRICTED_JSON" | jq 'length') -gt 0 ]]; then
        #     : > "$CLASSIC_UNRESTRICTED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CLASSIC_UNRESTRICTED_OUTPUT_PATH${RESET}"
        #     echo "$CLASSIC_UNRESTRICTED_JSON" | jq '.' > "$CLASSIC_UNRESTRICTED_OUTPUT_PATH"
        #     echo -e "Classic Infrastructure Security Groups with unrestricted inbound rules saved to: ${BOLD}${CLASSIC_UNRESTRICTED_OUTPUT_PATH}${RESET}"
        # fi
    fi
else
    echo "No Classic Infrastructure Security Groups found."
fi