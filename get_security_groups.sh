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
DEBUG=false

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script enumerates IBM Cloud VPC and Classic Infrastructure security groups."
}

while getopts ":ho:v" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
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

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving regions"
fi

REGIONS=$(get_regions)
if [ "$DEBUG" = true ]; then
    REGION_COUNT=$(echo "$REGIONS" | wc -w | tr -d ' ')
    echo -e "${BOLD}[DEBUG]${RESET} Found $REGION_COUNT region(s) to process"
fi

ALL_VPC_JSON="[]"
ALL_VPC_UNRESTRICTED_JSON="[]"
TOTAL_VPC_SG=0
TOTAL_UNRESTRICTED_SG=0
declare -A REGION_SG_COUNTS

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
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud is security-groups --all-resource-groups --output json"
    fi
    SG_JSON=$(ibmcloud is security-groups --all-resource-groups --output json 2>&1) || true

    EXIT_CODE=$?
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Command exit code: $EXIT_CODE"
    fi
    # Validate JSON output
    if ! echo "$SG_JSON" | jq empty 2>/dev/null; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON response from region $region"
            echo -e "${BOLD}[DEBUG]${RESET} Response: $SG_JSON"
        fi
        warning "Failed to retrieve valid JSON for security groups in region $region"
        REGION_SG_COUNTS[$region]=0
        continue
    fi
    if [ $EXIT_CODE -ne 0 ] || [[ "$SG_JSON" =~ "FAILED" ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve security groups for region $region"
        fi
        warning "Failed to retrieve VPC security groups for region $region"
        REGION_SG_COUNTS[$region]=0
        continue
    fi
    if [[ -z "${SG_JSON:-}" || "$SG_JSON" == "[]" || "$SG_JSON" == "null" ]]; then
        REGION_SG_COUNTS[$region]=0
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: No security groups found"
        fi
        continue
    fi

    REGION_SG=$(echo "$SG_JSON" | jq '[.[] | {region: "'$region'", name: .name, id: .id, rules: .rules}]')
    SG_COUNT=$(echo "$REGION_SG" | jq 'length')
    REGION_SG_COUNTS[$region]=$SG_COUNT
    TOTAL_VPC_SG=$((TOTAL_VPC_SG + SG_COUNT))
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $SG_COUNT security group(s)"
    fi
    ALL_VPC_JSON=$(jq -s 'add' <(echo "$ALL_VPC_JSON") <(echo "$REGION_SG"))

    REGION_UNRESTRICTED=$(echo "$REGION_SG" | jq '[.[] | {region, name, id, rules: [.rules[] | select(.direction=="inbound" and .remote.cidr_block=="0.0.0.0/0")]} | select(.rules|length>0)]')
    UNRESTRICTED_COUNT=$(echo "$REGION_UNRESTRICTED" | jq 'length')
    if [[ $UNRESTRICTED_COUNT -gt 0 ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $UNRESTRICTED_COUNT security group(s) with unrestricted rules"
        fi
        TOTAL_UNRESTRICTED_SG=$((TOTAL_UNRESTRICTED_SG + UNRESTRICTED_COUNT))
        ALL_VPC_UNRESTRICTED_JSON=$(jq -s 'add' <(echo "$ALL_VPC_UNRESTRICTED_JSON") <(echo "$REGION_UNRESTRICTED"))
    fi
    unset SG_JSON REGION_SG REGION_UNRESTRICTED
done

echo " "
echo -e "${BOLD}Total VPC Security Groups: $TOTAL_VPC_SG${RESET}"
if [[ $TOTAL_UNRESTRICTED_SG -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}Security Groups with unrestricted inbound rules (0.0.0.0/0): $TOTAL_UNRESTRICTED_SG${RESET}"
else
    echo -e "${BOLD}Security Groups with unrestricted inbound rules: 0${RESET}"
fi

echo " "
if [[ $(echo "$ALL_VPC_JSON" | jq 'length') -gt 0 ]]; then
    # Display security groups by region
    echo -e "${BOLD}VPC Security Groups by region:${RESET}"
    for region in $REGIONS; do
        if [[ ${REGION_SG_COUNTS[$region]:-0} -gt 0 ]]; then
            echo -e "  ${BOLD}$region:${RESET} ${REGION_SG_COUNTS[$region]} security group(s)"
            # Extract and display security group names for this region
            REGION_SGS=$(echo "$ALL_VPC_JSON" | jq -r --arg region "$region" '.[] | select(.region == $region) | .name')
            while IFS= read -r sg_name; do
                if [[ -n "$sg_name" ]]; then
                    echo "    - $sg_name"
                fi
            done <<< "$REGION_SGS"
        fi
    done
    echo " "
    : > "$VPC_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$VPC_OUTPUT_PATH${RESET}"
    echo "$ALL_VPC_JSON" | jq '.' > "$VPC_OUTPUT_PATH"
    echo -e "All VPC Security Groups saved to: ${BOLD}${VPC_OUTPUT_PATH}${RESET}"

    if [[ $(echo "$ALL_VPC_UNRESTRICTED_JSON" | jq 'length') -gt 0 ]]; then
        : > "$VPC_UNRESTRICTED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$VPC_UNRESTRICTED_OUTPUT_PATH${RESET}"
        echo "$ALL_VPC_UNRESTRICTED_JSON" | jq '.' > "$VPC_UNRESTRICTED_OUTPUT_PATH"
        echo -e "${YELLOW}${BOLD}Warning:${RESET} VPC Security Groups with unrestricted inbound rules saved to: ${BOLD}${VPC_UNRESTRICTED_OUTPUT_PATH}${RESET}"
    fi
else
    echo "No VPC Security Groups found."
fi

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}Classic Infrastructure Security Groups${RESET}..."
echo " "
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud sl securitygroup list --output json"
fi

CLASSIC_JSON="[]"
CLASSIC_SG_JSON=$(ibmcloud sl securitygroup list --output json 2>&1) || true
EXIT_CODE=$?
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Command exit code: $EXIT_CODE"
fi

# Check for FAILED or authorization errors first
if [[ "$CLASSIC_SG_JSON" =~ "FAILED" ]] || [[ "$CLASSIC_SG_JSON" =~ "Unauthorized" ]] || [[ "$CLASSIC_SG_JSON" =~ "not linked to an account in IMS" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Classic Infrastructure not available or not authorized"
        echo -e "${BOLD}[DEBUG]${RESET} Response: $CLASSIC_SG_JSON"
    fi
    echo -e "${CYAN}Classic Infrastructure security groups: Not available${RESET}"
    echo -e "${CYAN}(Account may not have Classic Infrastructure enabled)${RESET}"
    CLASSIC_SG_JSON="[]"
elif [[ -n "${CLASSIC_SG_JSON:-}" ]] && ! echo "$CLASSIC_SG_JSON" | jq empty 2>/dev/null; then
    # Only warn for other types of invalid JSON
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON response for Classic security groups"
        echo -e "${BOLD}[DEBUG]${RESET} Response: $CLASSIC_SG_JSON"
    fi
    warning "Failed to retrieve valid JSON for Classic Infrastructure security groups"
    CLASSIC_SG_JSON="[]"
fi

if [[ -n "${CLASSIC_SG_JSON:-}" && "$CLASSIC_SG_JSON" != "[]" && "$CLASSIC_SG_JSON" != "null" ]]; then
    CLASSIC_JSON="$CLASSIC_SG_JSON"
    CLASSIC_COUNT=$(echo "$CLASSIC_JSON" | jq 'length')

    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Found $CLASSIC_COUNT Classic security group(s)"
    fi

    # TODO: Uncomment below to detect and save Classic Infrastructure security groups with unrestricted inbound rules
    # CLASSIC_UNRESTRICTED=$(echo "$CLASSIC_SG_JSON" | jq '[.[] | {name, id, rules: [.rules[]? | select(.direction=="inbound" and .remoteIp=="0.0.0.0")]} | select(.rules|length>0)]')
    echo -e "${BOLD}Total Classic Security Groups: $CLASSIC_COUNT${RESET}"
    echo " "
    if [[ $CLASSIC_COUNT -gt 0 ]]; then
        echo -e "${BOLD}Classic Security Groups:${RESET}"
        CLASSIC_NAMES=$(echo "$CLASSIC_JSON" | jq -r '.[].name')
        while IFS= read -r sg_name; do
            if [[ -n "$sg_name" ]]; then
                echo "  - $sg_name"
            fi
        done <<< "$CLASSIC_NAMES"
        echo " "
        : > "$CLASSIC_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CLASSIC_OUTPUT_PATH${RESET}"
        echo "$CLASSIC_JSON" | jq '.' > "$CLASSIC_OUTPUT_PATH"
        echo -e "All Classic Infrastructure Security Groups saved to: ${BOLD}${CLASSIC_OUTPUT_PATH}${RESET}"

        # TODO: Uncomment below to save Classic Infrastructure security groups with unrestricted inbound rules
        # if [[ $(echo "$CLASSIC_UNRESTRICTED" | jq 'length') -gt 0 ]]; then
        #     : > "$CLASSIC_UNRESTRICTED_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CLASSIC_UNRESTRICTED_OUTPUT_PATH${RESET}"
        #     echo "$CLASSIC_UNRESTRICTED" | jq '.' > "$CLASSIC_UNRESTRICTED_OUTPUT_PATH"
        #     echo -e "Classic Infrastructure Security Groups with unrestricted inbound rules saved to: ${BOLD}${CLASSIC_UNRESTRICTED_OUTPUT_PATH}${RESET}"
        # fi
    fi
else
    if [[ ! "$CLASSIC_SG_JSON" =~ "not linked to an account in IMS" ]]; then
        echo -e "${BOLD}Total Classic Security Groups: 0${RESET}"
        echo "No Classic Infrastructure Security Groups found."
    fi
fi

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   VPC Security Groups: $TOTAL_VPC_SG"
    echo -e "${BOLD}[DEBUG]${RESET}   VPC Unrestricted: $TOTAL_UNRESTRICTED_SG"
    echo -e "${BOLD}[DEBUG]${RESET}   Classic Security Groups: ${CLASSIC_COUNT:-0}"
    echo -e "${BOLD}[DEBUG]${RESET}   VPC Security Groups by region:"
    for region in $REGIONS; do
        if [[ ${REGION_SG_COUNTS[$region]:-0} -gt 0 ]]; then
            echo -e "${BOLD}[DEBUG]${RESET}     $region: ${REGION_SG_COUNTS[$region]}"
        fi
    done
fi