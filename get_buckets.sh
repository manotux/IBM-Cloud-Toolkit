#!/usr/bin/env bash

# get_buckets.sh
#
# This script enumerates all IBM Cloud Object Storage buckets in the account and outputs them as a JSON array.
# For each bucket, it outputs: bucket name, service instance name, service instance crn, region_id, and bucket CreationDate.
# Requires IBM Cloud CLI and jq.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"
OUTPUT_FILE="buckets.json"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'buckets.json')"
    echo
    echo "This script enumerates all IBM Cloud Object Storage buckets in the account."
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

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating IBM Cloud ${ORANGE}${BOLD}Object Storage buckets${RESET}..."
echo " "

# Get all COS service instances (no region iteration needed)
INSTANCES_JSON=$(ibmcloud resource service-instances --service-name cloud-object-storage --output json)
if [[ -z "${INSTANCES_JSON:-}" || "$INSTANCES_JSON" == "[]" || "$INSTANCES_JSON" == "null" ]]; then
    failure "Failed to retrieve Cloud Object Storage service instances."
fi

ALL_BUCKETS_JSON="[]"

while IFS= read -r instance; do 
    INSTANCE_NAME=$(echo "$instance" | jq -r '.name')
    INSTANCE_CRN=$(echo "$instance" | jq -r '.crn')
    REGION_ID=$(echo "$instance" | jq -r '.region_id')
    BUCKETS_JSON=$(ibmcloud cos buckets --ibm-service-instance-id "$INSTANCE_CRN" --output json 2>/dev/null)

    # check if there are no buckets
    if [[ -z "$BUCKETS_JSON:-" || "$BUCKETS_JSON" == "null" || $(echo "$BUCKETS_JSON" | jq '.Buckets == null') == "true" ]]; then
        continue
    fi

    for bucket in $(echo "$BUCKETS_JSON" | jq -c '.Buckets[]'); do
        BUCKET_NAME=$(echo "$bucket" | jq -r '.Name')
        CREATION_DATE=$(echo "$bucket" | jq -r '.CreationDate')
        BUCKET_OBJ=$(jq -n --arg name "$BUCKET_NAME" --arg instance "$INSTANCE_NAME" --arg crn "$INSTANCE_CRN" --arg region "$REGION_ID" --arg date "$CREATION_DATE" '{bucket_name: $name, service_instance_name: $instance, service_instance_crn: $crn, region_id: $region, CreationDate: $date}')
        ALL_BUCKETS_JSON=$(jq -s 'add' <(echo "$ALL_BUCKETS_JSON") <(echo "[$BUCKET_OBJ]"))
    done
done < <(echo "$INSTANCES_JSON" | jq -c '.[]')

if [[ "$ALL_BUCKETS_JSON" == "[]" ]]; then
    echo "No Cloud Object Storage buckets found."
    exit 0
fi

OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILE}"
: > "$OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$OUTPUT_PATH${RESET}"

echo "$ALL_BUCKETS_JSON" | jq '.' > "$OUTPUT_PATH"
echo -e "All buckets saved to: ${BOLD}${OUTPUT_PATH}${RESET}"
