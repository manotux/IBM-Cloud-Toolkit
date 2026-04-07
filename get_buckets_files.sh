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

DEBUG=false
MAX_ITEMS=100
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE] [-m MAX_ITEMS] [-v]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -f OUTPUT_FILE  Specify the output file name (default: 'buckets_files.txt')"
    echo "  -m MAX_ITEMS    Maximum number of items to retrieve per bucket (default: 100)"
    echo "  -v              Enable debug mode (outputs ibmcloud commands)"
    echo
    echo "This script lists all files in all IBM Cloud Object Storage buckets in the account."
}

while getopts ":ho:f:m:v" opt; do
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
        m)
            MAX_ITEMS="$OPTARG"
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

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud resource service-instances --service-name cloud-object-storage --all-resource-groups --output json"
fi
# Get all COS service instances (no region iteration needed)
INSTANCES_JSON=$(ibmcloud resource service-instances --service-name cloud-object-storage --all-resource-groups --output json)
if [[ -z "${INSTANCES_JSON:-}" || "$INSTANCES_JSON" == "[]" || "$INSTANCES_JSON" == "null" ]]; then
    failure "Failed to retrieve Cloud Object Storage service instances."
fi

# Initialize counters
TOTAL_BUCKETS=0
TOTAL_FILES=0
while IFS= read -r instance; do 
    INSTANCE_NAME=$(echo "$instance" | jq -r '.name')
    INSTANCE_CRN=$(echo "$instance" | jq -r '.crn')
    
    # Debug output
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud cos buckets-extended --ibm-service-instance-id \"$INSTANCE_CRN\" --output json"
    fi
    # Use || true to prevent script from exiting on command failure
    BUCKETS_JSON=$(ibmcloud cos buckets-extended --ibm-service-instance-id "$INSTANCE_CRN" --output json 2>&1) || true
    EXIT_CODE=$?
    # Check if command failed or returned error message
    if [ $EXIT_CODE -ne 0 ] || [[ "$BUCKETS_JSON" =~ "FAILED" ]]; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Command failed or access denied, skipping this instance"
        fi
        continue
    fi
    # check if there are no buckets (valid JSON with null or empty Buckets array)
    if [[ -z "${BUCKETS_JSON:-}" ]] || \
       [[ "$BUCKETS_JSON" == "null" ]] || \
       $(echo "$BUCKETS_JSON" | jq -e '.Buckets == null' 2>/dev/null) == "true"; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} No buckets in this instance"
        fi
        continue
    fi
    # Validate that we have valid JSON with Buckets array
    if ! echo "$BUCKETS_JSON" | jq -e '.Buckets' &>/dev/null; then
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Invalid JSON structure, skipping this instance"
        fi
        continue
    fi

    while IFS= read -r bucket; do 
    # for bucket in $(echo "$BUCKETS_JSON" | jq -c '.Buckets[]'); do
        BUCKET_NAME=$(echo "$bucket" | jq -r '.Name')
        BUCKET_REGION=$(echo "$bucket" | jq -r '.LocationConstraint')
        echo "## Bucket ${INSTANCE_NAME}/${BUCKET_NAME} ##" >> "$OUTPUT_PATH"

        # Debug output
        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud cos list-objects-v2 --bucket \"$BUCKET_NAME\" --region $BUCKET_REGION --max-items $MAX_ITEMS --output json"
        fi
        # List files in the bucket (with max-items limit)
        FILES_JSON=$(ibmcloud cos list-objects-v2 --bucket "$BUCKET_NAME" --region $BUCKET_REGION --max-items $MAX_ITEMS --output json 2>/dev/null) || warning "Could not list files in bucket \"$BUCKET_NAME\". It may contain too many objects."
        # Count items and increment counters
        TOTAL_BUCKETS=$((TOTAL_BUCKETS + 1))
        # If no files exist or list-objects-v2 does not return anything
        if [[ -z "${FILES_JSON:-}" || "$FILES_JSON" == "null" || $(echo "$FILES_JSON" | jq '.KeyCount == 0') == "true" ]]; then
            echo "(No files found)" >> "$OUTPUT_PATH"
            if [ "$DEBUG" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Bucket \"$BUCKET_NAME\": 0 items"
            fi
        else
            BUCKET_FILE_COUNT=$(echo "${FILES_JSON}" | jq -r '.Contents | length')
            TOTAL_FILES=$((TOTAL_FILES + BUCKET_FILE_COUNT))
            if [ "$DEBUG" = true ]; then
                IS_TRUNCATED=$(echo "$FILES_JSON" | jq -r '.IsTruncated // false')
                if [ "$IS_TRUNCATED" = "true" ]; then
                    echo -e "${BOLD}[DEBUG]${RESET} Bucket \"$BUCKET_NAME\": $BUCKET_FILE_COUNT items (truncated)"
                else
                    echo -e "${BOLD}[DEBUG]${RESET} Bucket \"$BUCKET_NAME\": $BUCKET_FILE_COUNT items"
                fi
            fi
            echo "${FILES_JSON}" | jq -r '.Contents[].Key' >> "$OUTPUT_PATH"
        fi
        echo >> "$OUTPUT_PATH"
    done < <(echo "$BUCKETS_JSON" | jq -c '.Buckets[]')

done < <(echo "$INSTANCES_JSON" | jq -c '.[]')

if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Total buckets: $TOTAL_BUCKETS"
    echo -e "${BOLD}[DEBUG]${RESET} Total files: $TOTAL_FILES"
fi
echo " "
echo -e "All bucket file listings saved to: ${BOLD}${OUTPUT_PATH}${RESET}"