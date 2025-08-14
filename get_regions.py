import json
import subprocess
import requests

# Get the list of enabled regions on IBM Cloud account
result = subprocess.run(['ibmcloud', 'regions', '--output', 'json'], capture_output=True, text=True)
regions = json.loads(result.stdout)['regions']

# Extract region names
region_names = [region['name'] for region in regions]

print("Enabled IBM Cloud regions:")
print(region_names)
print()

print("To export REGIONS envvar:")
print(f"export REGIONS='{"', '".join(region_names)}'")



# import requests
# import ibm_cloud_sdk_core
# from ibm_cloud_sdk_core.authenticators import IAMAuthenticator

# # Set up authentication
# authenticator = IAMAuthenticator('your_api_key')
# service = ibm_cloud_sdk_core.authenticators.IAMAuthenticator('your_api_key')

# # Get the list of enabled regions on IBM Cloud account
# url = 'https://api.cloud.ibm.com/v1/regions'
# headers = {
#     'Authorization': f'Bearer {authenticator.get_access_token()}',
#     'Accept': 'application/json'
# }

# response = requests.get(url, headers=headers)

# # Check if the request was successful
# if response.status_code == 200:
#     regions = response.json()['regions']
#     region_names = [region['name'] for region in regions]

#     print("Enabled IBM Cloud regions:")
#     print(region_names)
#     print()

#     print("To export REGIONS envvar:")
#     print(f"export REGIONS='{"', '".join(region_names)}'")
# else:
#     print(f"Failed to retrieve regions. Status code: {response.status_code}")
#     print(response.text)