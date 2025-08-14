#!/bin/bash

# IBM Cloud Object Storage Public Bucket Scanner
# For penetration testing teams - detects publicly accessible buckets across all regions

# Variables
API_KEY="your_api_key"
ACCOUNT_ID="your_account_id"

# Get IAM Token
echo "Obtaining IAM token..."
IAM_TOKEN=$(curl -s -X POST "https://iam.cloud.ibm.com/identity/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$API_KEY" | jq -r '.access_token')

if [[ -z "$IAM_TOKEN" || "$IAM_TOKEN" == "null" ]]; then
  echo "Error: Failed to obtain IAM token. Check your API key."
  exit 1
fi

echo "IAM token obtained successfully: ${IAM_TOKEN:0:10}..."

# Define regions to check
REGIONS=("au-syd" "in-che" "jp-osa" "jp-tok" "eu-de" "eu-es" "eu-gb" "ca-mon" "ca-tor" "us-south" "us-south-test" "us-east" "br-sao")

# Report file
REPORT_FILE="ibm_cos_public_buckets_$(date +%Y%m%d_%H%M%S).txt"
echo "IBM Cloud Object Storage Public Buckets Report" > $REPORT_FILE
echo "Date: $(date)" >> $REPORT_FILE
echo "Account: $ACCOUNT_ID" >> $REPORT_FILE
echo "----------------------------------------" >> $REPORT_FILE

# Statistics counters
TOTAL_BUCKETS=0
PUBLIC_BUCKETS=0

# For each region
for REGION in "${REGIONS[@]}"; do
  echo "Checking region: $REGION"
  echo -e "\nRegion: $REGION" >> $REPORT_FILE
  
  # Get list of service instances
  # The resource_id is specific to Cloud Object Storage
  echo "  Getting COS service instances in region $REGION..."
  SERVICE_INSTANCES=$(curl -s "https://$REGION.resource-controller.cloud.ibm.com/v2/resource_instances?resource_id=dff97f5c-bc5e-4455-b470-411c3edbe49c" \
    -H "Authorization: Bearer $IAM_TOKEN" \
    -H "Accept: application/json" | jq -r '.resources[].guid')
  
  # If no instances found, continue to next region
  if [[ -z "$SERVICE_INSTANCES" || "$SERVICE_INSTANCES" == "null" ]]; then
    echo "  No COS service instances found in this region."
    echo "  No COS service instances found." >> $REPORT_FILE
    continue
  fi
  
  for SERVICE_ID in $SERVICE_INSTANCES; do
    echo "  Processing service instance ID: $SERVICE_ID"
    
    # Get buckets for this service instance
    BUCKET_RESPONSE=$(curl -s "https://s3.$REGION.cloud-object-storage.appdomain.cloud" \
      -H "Authorization: Bearer $IAM_TOKEN" \
      -H "ibm-service-instance-id: $SERVICE_ID")
    
    # Check if response contains error
    if [[ "$BUCKET_RESPONSE" == *"Error"* ]]; then
      echo "    Error getting buckets for service instance: $SERVICE_ID"
      echo "    Response: $BUCKET_RESPONSE"
      continue
    fi
    
    # Extract bucket names from XML response
    BUCKETS=$(echo "$BUCKET_RESPONSE" | grep -o "<Name>.*</Name>" | sed -e 's/<Name>//' -e 's/<\/Name>//')
    
    # If no buckets found, continue to next instance
    if [[ -z "$BUCKETS" ]]; then
      echo "    No buckets found in this service instance."
      continue
    fi
    
    for BUCKET in $BUCKETS; do
      TOTAL_BUCKETS=$((TOTAL_BUCKETS + 1))
      echo "    Checking bucket: $BUCKET"
      
      # Check if bucket is publicly accessible using multiple methods
      # Method 1: Check via HEAD request
      PUBLIC_HEAD=$(curl -s -I -o /dev/null -w "%{http_code}" "https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud")
      
      # Method 2: Check by trying to list objects
      PUBLIC_LIST=$(curl -s -o /dev/null -w "%{http_code}" "https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud")
      
      # Method 3: Check via alternative URL
      ALT_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET")
      
      if [[ "$PUBLIC_HEAD" == "200" || "$PUBLIC_LIST" == "200" || "$ALT_CHECK" == "200" ]]; then
        PUBLIC_BUCKETS=$((PUBLIC_BUCKETS + 1))
        echo "      [VULNERABLE] Bucket: $BUCKET in service instance: $SERVICE_ID, region: $REGION is publicly accessible!"
        echo "[VULNERABLE] Bucket: $BUCKET" >> $REPORT_FILE
        echo "  Service Instance: $SERVICE_ID" >> $REPORT_FILE
        echo "  Region: $REGION" >> $REPORT_FILE
        echo "  URL: https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud" >> $REPORT_FILE
        echo "  Alt URL: https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET" >> $REPORT_FILE
        
        # Try to list some objects to check access depth
        OBJECTS_RESPONSE=$(curl -s "https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud")
        OBJECTS=$(echo "$OBJECTS_RESPONSE" | grep -o "<Key>.*</Key>" | head -5 | sed -e 's/<Key>//' -e 's/<\/Key>//')
        
        if [[ ! -z "$OBJECTS" ]]; then
          echo "  Accessible Objects (sample):" >> $REPORT_FILE
          echo "$OBJECTS" | while read object; do
            echo "    - $object" >> $REPORT_FILE
            # Check if specific object is accessible
            OBJECT_CHECK=$(curl -s -I -o /dev/null -w "%{http_code}" "https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud/$object")
            if [[ "$OBJECT_CHECK" == "200" ]]; then
              echo "      URL: https://$BUCKET.s3.$REGION.cloud-object-storage.appdomain.cloud/$object" >> $REPORT_FILE
            fi
          done
        fi
        
        # Check bucket configurations to understand why it's public
        echo "  Configuration Analysis:" >> $REPORT_FILE
        
        # Check ACL using the token
        ACL_RESPONSE=$(curl -s "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET?acl" \
          -H "Authorization: Bearer $IAM_TOKEN")
        
        if [[ "$ACL_RESPONSE" == *"AllUsers"* ]]; then
          echo "    - ACL configured to allow access to 'AllUsers'" >> $REPORT_FILE
        fi
        
        # Check CORS
        CORS_RESPONSE=$(curl -s "https://s3.$REGION.cloud-object-storage.appdomain.cloud/$BUCKET?cors" \
          -H "Authorization: Bearer $IAM_TOKEN")
        
        if [[ "$CORS_RESPONSE" != *"NoSuchCORSConfiguration"* ]]; then
          echo "    - CORS configuration found, may be overly permissive" >> $REPORT_FILE
        fi
        
        echo "----------------------------------------" >> $REPORT_FILE
      else
        echo "      Bucket: $BUCKET in service instance: $SERVICE_ID, region: $REGION is not publicly accessible."
      fi
    done
  done
done

# Add statistics to report
echo -e "\nSummary:" >> $REPORT_FILE
echo "Total buckets checked: $TOTAL_BUCKETS" >> $REPORT_FILE
echo "Public buckets found: $PUBLIC_BUCKETS" >> $REPORT_FILE
if [[ $TOTAL_BUCKETS -gt 0 ]]; then
  PERCENTAGE=$(awk "BEGIN {print ($PUBLIC_BUCKETS/$TOTAL_BUCKETS)*100}")
  echo "Exposure rate: $PERCENTAGE%" >> $REPORT_FILE
fi

echo "----------------------------------------"
echo "Scan completed."
echo "Total buckets checked: $TOTAL_BUCKETS"
echo "Public buckets found: $PUBLIC_BUCKETS"
if [[ $TOTAL_BUCKETS -gt 0 ]]; then
  PERCENTAGE=$(awk "BEGIN {print ($PUBLIC_BUCKETS/$TOTAL_BUCKETS)*100}")
  echo "Exposure rate: $PERCENTAGE%"
fi
echo "Report saved to: $REPORT_FILE"




#!/bin/bash

ACCOUNT_ID="your_account_id"
REGIONS=("us-south" "eu-de" "us-east" "jp-tok") # Add other regions as needed

for REGION in "${REGIONS[@]}"; do
  echo "Processing region: $REGION"
  
  # List all service instances in the region
  SERVICE_INSTANCES=$(curl -s "https://resource-controller.cloud.ibm.com/v2/resource_instances?account_id=$ACCOUNT_ID&region=$REGION" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -r '.resources[] | select(.resource_type == "cos") | .name')
  

curl -s "https://resource-controller.cloud.ibm.com/v2/resource_instances?type=service_instance" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -r '.resources[]'



  for SERVICE_ID in $SERVICE_INSTANCES; do
    echo "Processing service instance: $SERVICE_ID"
    
    # List buckets within the service instance
    BUCKETS=$(curl -s "https://$REGION.objectstorage.cloud.ibm.com/v2/buckets?service_instance_id=$SERVICE_ID" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -r '.buckets[] | .name')
    
    curl -X "GET" "https://s3.$REGION.cloud-object-storage.appdomain.cloud/" -H "Authorization: Bearer $IAM_TOKEN" -H "ibm-service-instance-id: $SERVICE_INSTANCE_ID"


    for BUCKET in $BUCKETS; do
      echo "Checking bucket: $BUCKET"
      
      # Check public accessibility of the bucket
      RESPONSE=$(curl -s "https://$REGION.objectstorage.cloud.ibm.com/v2/buckets/$BUCKET/access_policies" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN")
      PUBLICLY_ACCESSIBLE=$(echo $RESPONSE | jq -r '.access_policies[] | select(.public_access == true)')
      
      if [ ! -z "$PUBLICLY_ACCESSIBLE" ]; then
        echo "Bucket: $BUCKET in region: $REGION is publicly accessible."
      else
        echo "Bucket: $BUCKET in region: $REGION is not publicly accessible."
      fi
    done
  done
done
