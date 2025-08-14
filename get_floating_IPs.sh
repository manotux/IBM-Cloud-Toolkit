#!/usr/bin/env bash

# get_floating_IPs.sh
#
# This script enumerates all floating IPs in each enabled IBM Cloud region and outputs them to a single file.
# Requires IBM Cloud CLI and vpc-infrastructure ("is") plugin.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="floating_ips.txt"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'floating_ips.txt')"
    echo
    echo "This script enumerates all floating IPs in each enabled IBM Cloud region."
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

require_ibmcloud
require_ibmcloud_is
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

echo " "
echo "============================================================"
echo "Enumerating floating IPs in all enabled IBM Cloud regions..."

REGIONS=$(get_regions)

for region in $REGIONS; do
    if ! ibmcloud target -r "$region" -q &>/dev/null; then
        warning "Failed to target region $region"
        continue
    fi
    ibmcloud is floating-ips -q 2>/dev/null | awk 'NR>1 {print $2}' >> "$OUTPUT_PATH" || warning "Failed to retrieve floating IPs for region $region"
done

echo -e "All floating IPs saved to: ${BOLD}${OUTPUT_PATH}${RESET}"

