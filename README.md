<h1 align="center"><img src="IBM_Cloud_logo.png" alt="IBM Cloud" width=300 height=214></h1>

# IBM Cloud ToolKit
A collection of scripts for enumeration of IBM Cloud resources and identification of weak security settings.

## Why was this project created?

This toolkit is intended to automate the enumeration of resources and security settings during penetration testing engagements on IBM Cloud accounts. Manual enumeration is time consuming, repetitive, tedious and prone to human error, especially when dealing with complex cloud environments. This collection of scripts aims to improve efficiency, and ensure more accurate coverage of IBM Cloud assets and configurations. 

While there are several well-established open-source tools for major cloud providers like AWS and Azure, there are very few similar initiatives focused on IBM Cloud. This project was created to help fill that gap and provide the IBM Cloud community with tools for security assessments and resource inventory. 

Contributions and community feedback are welcome! If you find these scripts useful, have suggestions for improvements, feature requests, or want to contribute in any way, feel free to open an issue or submit a PR.

## Requirements
- IBM Cloud CLI
- The `jq` utility - lightweight command-line JSON processor
- Authenticated session

To install the IBM Cloud CLI, you can use the provided script:

```bash
./install_ibmcloud_cli.sh
```

Or follow the instructions at [IBM Cloud CLI Installation Guide](https://cloud.ibm.com/docs/cli?topic=cli-install-ibmcloud-cli).

## Scripts

#### - [ibm_cloud_enum.sh](ibm_cloud_enum.sh)
Executes all enumeration scripts against the IBM Cloud Account.

#### - [get_custom_roles.sh](get_custom_roles.sh)
Enumerates custom IAM roles to be verified for excessive privileges granted to users.

#### - [get_user_policies.sh](get_user_policies.sh)
Identifies users with access policies assigned directly (not via groups) in the IBM Cloud account. Outputs user_id and policies in jq-formatted JSON for each such user.

#### - [get_api_keys.sh](get_api_keys.sh)
Enumerates existing API Keys and identifies those not rotated within a configurable period (default: 90 days).

#### - [get_regions.sh](get_regions.sh)
Enumerates enabled regions on the IBM Cloud account.

#### - [install_ibmcloud_cli.sh](install_ibmcloud_cli.sh)
Automates the installation of the IBM Cloud CLI for macOS and Linux.

#### - [public_buckets.py](public_buckets.py)
Verifies if public access is enabled on the IBM Cloud account and enumerates all Cloud Object Storage buckets that are publicly accessible from the Internet.

#### - [get_floating_IPs.sh](get_floating_IPs.sh)
Enumerates all floating IPs in each enabled IBM Cloud region.

#### - [get_VSIs.sh](get_VSIs.sh)
Enumerates all VSIs (IBM Cloud VMs) in each enabled IBM Cloud region. Also generates a separate file for VSIs with metadata enabled.

#### - [get_clusters.sh](get_clusters.sh)
Enumerates all IBM Cloud Kubernetes/Openshift clusters using the IBM Cloud REST API. Also generates a separate file for clusters with public endpoint enabled.

#### - [get_databases.sh](get_databases.sh)
Enumerates all IBM Cloud Databases. Also generates a separate file for databases with public endpoint enabled.

## Usage
Each script has its own Usage instructions documented in the code and that can be verified through the -h option. Example for `get_api_keys.sh`:

```
$ ./get_api_keys.sh -h
Usage: ./get_api_keys.sh [-h] [-o OUTPUT_DIR] [-f OUTPUT_FILE]

Options:
  -h              Show this help message
  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')
  -f OUTPUT_FILE  Specify the output file name (default: 'api_keys.txt')
  -d ROTATION_DAYS  Set the rotation threshold in days (default: 90)

This script retrieves all API keys in the IBM Cloud account.
```

## TODO
- get_resources.sh
- get_users.sh
- get_mfa.sh
- Support for handling multiple IBM Cloud accounts in batch mode across all enumeration scripts.
- Implement different output formats (json, table, csv)

## Author
Heber Blain Gonçalves

- [linkedin.com/hebergoncalves/](https://linkedin.com/in/hebergoncalves/)
- [github.com/manotux](https://github.com/manotux)

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
