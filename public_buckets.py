import requests
import json

api_key = 'IBMCLOUD_API_KEY'
account_id = '<ACCOUNT_ID>'

url_public_access = f'https://iam.cloud.ibm.com/v2/groups/settings?account_id={account_id}'
url_token = 'https://iam.cloud.ibm.com/identity/token'
data_token = {
    'grant_type': 'urn:ibm:params:oauth:grant-type:apikey',
    'apikey': api_key
}

print("Obtaining IAM token...")
response = requests.post(url_token, data=data_token, headers={'Content-Type': 'application/x-www-form-urlencoded'})

if response.status_code == 200:
    token_data = response.json()
    ibmcloud_access_token = token_data['access_token']
    print(f"IBMCLOUD_ACCESS_TOKEN={ibmcloud_access_token[:10]}...")
else:
    print(f"Failed to obtain access token. Status code: {response.status_code}")
    print(response.text)

headers = {
    'Authorization': f'Bearer {ibmcloud_access_token}',
    'Accept': 'application/json'
}
response = requests.get(url_public_access, headers=headers)



# Check if the request was successful
if response.status_code == 200:
    data = response.json()
    public_access_enabled = data.get('public_access_enabled')
    if public_access_enabled:
        print("WARNING: Public Access is enabled for the account. Checking for public resources ...")
    else:
        print("INFO: Public Access is not enabled for the account.")
else:
    print(f"Failed to retrieve settings. Status code: {response.status_code}")
    print(response.text)

# {"account_id":"8e5158d44fd45edcd727e077fa4f6b16","last_modified_at":"","last_modified_by_id":"","public_access_enabled":true} 
