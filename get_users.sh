
# retrieve the list of users in json format and also any user that is not in ACTIVE status

IBMCLOUD_ACCESS_TOKEN=$(curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=$IBMCLOUD_API_KEY" https://iam.cloud.ibm.com/identity/token | jq -r '.access_token')
         
IBMCLOUD_ACCOUNT_ID=$(ibmcloud target -o JSON|jq -r '.account.guid')

# get all users
curl -s -X GET https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" |jq -r 

#inactive users -> needs to filter by status different than ACTIVE
curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -r '.resources[] | {iam_id, user_id, email, state}'

# invetigate if it is worth to get INACTIVE user's last activity:
curl -s -X GET "https://iam.cloud.ibm.com/v2/accounts/$IBMCLOUD_ACCOUNT_ID/users/$IAM_ID?include_activity=true" -H "Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN" | jq -r '{user_id, activity}'