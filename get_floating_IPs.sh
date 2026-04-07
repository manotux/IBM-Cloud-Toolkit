#!/usr/bin/env bash

# get_floating_IPs.sh
#
# This script enumerates all floating IPs in each enabled IBM Cloud region and outputs them to a single file.
# Requires IBM Cloud CLI and vpc-infrastructure ("is") plugin.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="floating_ips.txt"

DEBUG=false
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'floating_ips.txt')"
    echo "  -v              Enable debug mode (outputs commands)"
    echo
    echo "This script enumerates all floating IPs in each enabled IBM Cloud region."
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

require_ibmcloud
require_ibmcloud_is
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}floating IPs${RESET} in all enabled IBM Cloud regions..."
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
ALL_IPS=""

TOTAL_IPS=0
declare -A REGION_IP_COUNTS
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
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud is floating-ips"
    fi
    IPS=$(ibmcloud is floating-ips -q 2>/dev/null | awk 'NR>1 {print $2}') || warning "Failed to retrieve floating IPs for region $region"
    if [[ -n "$IPS" ]]; then
        REGION_IP_COUNT=$(echo "$IPS" | wc -l | tr -d ' ')
        REGION_IP_COUNTS[$region]=$REGION_IP_COUNT
        TOTAL_IPS=$((TOTAL_IPS + REGION_IP_COUNT))
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: Found $REGION_IP_COUNT floating IP(s)"
        fi
        ALL_IPS+="$IPS\n"
    else
        REGION_IP_COUNTS[$region]=0
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Region $region: No floating IPs found"
        fi
    fi

done

echo " "
echo -e "${BOLD}Total floating IPs found: $TOTAL_IPS${RESET}"
echo " "
if [[ -z "${ALL_IPS:-}" || $TOTAL_IPS -eq 0 ]]; then
    echo "No floating IPs found in any region."
    exit 0
fi

# Display floating IPs by region
echo -e "${BOLD}Floating IPs by region:${RESET}"
for region in $REGIONS; do
    if [[ ${REGION_IP_COUNTS[$region]:-0} -gt 0 ]]; then
        echo -e "  ${BOLD}$region:${RESET} ${REGION_IP_COUNTS[$region]} IP(s)"
        # Re-target region to get IPs for display
        ibmcloud target -r "$region" -q &>/dev/null
        IPS=$(ibmcloud is floating-ips -q 2>/dev/null | awk 'NR>1 {print $2}')
        while IFS= read -r ip; do
            if [[ -n "$ip" ]]; then
                echo "    - $ip"
            fi
        done <<< "$IPS"
    fi
done
echo " "
# Remove trailing newline and save to OUTPUT_PATH
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"
echo -e "$ALL_IPS" | sed '/^$/d' > "$OUTPUT_PATH"

echo -e "All floating IPs saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Total regions processed: ${#REGION_IP_COUNTS[@]}"
    echo -e "${BOLD}[DEBUG]${RESET}   Total floating IPs: $TOTAL_IPS"
    echo -e "${BOLD}[DEBUG]${RESET}   Regions with IPs:"
    for region in "${!REGION_IP_COUNTS[@]}"; do
        if [[ ${REGION_IP_COUNTS[$region]} -gt 0 ]]; then
            echo -e "${BOLD}[DEBUG]${RESET}     $region: ${REGION_IP_COUNTS[$region]}"
        fi
    done
fi