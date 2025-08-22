#!/usr/bin/env bash

# ibm_cloud_enum.sh
#
# Main enumeration script for IBM Cloud. Runs all resource enumeration scripts in sequence.
# Usage: ./ibm_cloud_enum.sh [-h] [-o OUTPUT_DIR]
# -h: Show help
# -o OUTPUT_DIR: Specify output directory for all scripts (default: output)
# Requires IBM Cloud CLI, jq for JSON parsing, curl for REST API requests,
# exported IBM Cloud API Key envvar (IBMCLOUD_API_KEY), and the following
# plugins of IBM Cloud CLI: databases ("cdb"), vpc-infrastructure ("is")

BANNER="
########################################
        IBM Cloud Enumeration
   github.com/manotux/IBM-Cloud-Toolkit
########################################"

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
    echo "This script runs all IBM Cloud enumeration scripts."
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

echo "$BANNER"

require_ibmcloud_jq
require_ibmcloud_cdb
require_ibmcloud_is
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

"$srcdir/get_api_keys.sh" -o "$OUTPUT_DIR"

"$srcdir/get_custom_roles.sh" -o "$OUTPUT_DIR"

"$srcdir/get_user_policies.sh" -o "$OUTPUT_DIR"

"$srcdir/get_regions.sh" -o "$OUTPUT_DIR"

"$srcdir/get_floating_IPs.sh" -o "$OUTPUT_DIR"

"$srcdir/get_VSIs.sh" -o "$OUTPUT_DIR"

"$srcdir/get_clusters.sh" -o "$OUTPUT_DIR"

"$srcdir/get_databases.sh" -o "$OUTPUT_DIR"

echo " "
echo "${SEPARATOR}"
echo "IBM Cloud enumeration completed."
echo -e "Results saved to folder ${BOLD}${OUTPUT_DIR}${RESET}"
echo " "