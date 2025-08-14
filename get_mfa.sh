
IBMCLOUD_ACCESS_TOKEN=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" https://iam.cloud.ibm.com/identity/token | jq -r '.access_token')
         
IBMCLOUD_ACCOUNT_ID=$(ibmcloud target -o JSON|jq -r '.account.guid')

curl -s -X GET "https://iam.cloud.ibm.com/v1/accounts/$IBMCLOUD_ACCOUNT_ID/settings/identity" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" |jq