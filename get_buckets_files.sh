#!/usr/bin/env bash

# get_buckets_files.sh
#
# This script enumerates all files in all IBM Cloud Object Storage buckets in the account.
# For each bucket, it outputs a section:
# +Bucket <service_instance_name>/<bucket_name>
# <File list>
# Requires IBM Cloud CLI and jq.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="buckets_files.txt"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'buckets_files.txt')"
    echo
    echo "This script lists all files in all IBM Cloud Object Storage buckets in the account."
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
require_ibmcloud_cos
require_ibmcloud_login

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}files${RESET} in all IBM Cloud Object Storage buckets..."
echo " "

# Get all COS service instances (no region iteration needed)
INSTANCES_JSON=$(ibmcloud resource service-instances --service-name cloud-object-storage --all-resource-groups --output json)
if [[ -z "${INSTANCES_JSON:-}" || "$INSTANCES_JSON" == "[]" || "$INSTANCES_JSON" == "null" ]]; then
    failure "Failed to retrieve Cloud Object Storage service instances."
fi

while IFS= read -r instance; do 
    INSTANCE_NAME=$(echo "$instance" | jq -r '.name')
    INSTANCE_CRN=$(echo "$instance" | jq -r '.crn')
    BUCKETS_JSON=$(ibmcloud cos buckets-extended --ibm-service-instance-id "$INSTANCE_CRN" --output json 2>/dev/null)
    
    # check if there are no buckets
    if [[ -z "${BUCKETS_JSON:-}" || "$BUCKETS_JSON" == "null" || $(echo "$BUCKETS_JSON" | jq '.Buckets == null') == "true" ]]; then
        continue
    fi

    while IFS= read -r bucket; do 
    # for bucket in $(echo "$BUCKETS_JSON" | jq -c '.Buckets[]'); do
        BUCKET_NAME=$(echo "$bucket" | jq -r '.Name')
        BUCKET_REGION=$(echo "$bucket" | jq -r '.LocationConstraint')
        echo "## Bucket ${INSTANCE_NAME}/${BUCKET_NAME} ##" >> "$OUTPUT_PATH"

        # List files in the bucket (first 1000 objects)
        FILES_JSON=$(ibmcloud cos list-objects-v2 --bucket "$BUCKET_NAME" --region $BUCKET_REGION --output json 2>/dev/null) | warning "Could not list files in bucket \"$BUCKET_NAME\". It may contain too many objects."

        # If no files exist or list-objects-v2 does not return anything
        if [[ -z "${FILES_JSON:-}" || "$FILES_JSON" == "null" || $(echo "$FILES_JSON" | jq '.KeyCount == 0') == "true" ]]; then
            echo "(No files found)" >> "$OUTPUT_PATH"
        else
            echo "${FILES_JSON}" | jq -r '.Contents[].Key' >> "$OUTPUT_PATH"
        fi
        echo >> "$OUTPUT_PATH"
    done < <(echo "$BUCKETS_JSON" | jq -c '.Buckets[]')

done < <(echo "$INSTANCES_JSON" | jq -c '.[]')

echo -e "All bucket file listings saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
