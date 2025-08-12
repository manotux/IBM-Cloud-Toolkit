

<h1 align="center"><img src="IBM_Cloud_logo.png" alt="IBM Cloud" width=300 height=214></h1>

# IBM Cloud ToolKit
A collection of scripts and one-liners for enumeration of IBM Cloud resources. 

## Why was this project created?

This toolkit is intended to automate the enumeration of resources and security settings during penetration testing engagements on IBM Cloud accounts. Manual enumeration is time consuming, repetitive, tedious and prone to human error, especially when dealing with complex cloud environments. This collection of scripts aims to improve efficiency, and ensure more accurate coverage of IBM Cloud assets and configurations. 

While there are several well-established open-source tools for major cloud providers like AWS and Azure, there are very few similar initiatives focused on IBM Cloud. This project was created to help fill that gap and provide the IBM Cloud community with tools for security assessments and resource inventory. If you find these scripts useful, have suggestions for improvements, or want to contribute new features, feel free to open an issue or submit a PR. Community feedback and contributions are welcome!

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

- **[get_api_keys.sh](get_api_keys.sh)**
Enumerates existing API Keys.

- **[get_regions.sh](get_regions.sh)**
Enumerates enabled regions on the IBM Cloud account.

- **[install_ibmcloud_cli.sh](install_ibmcloud_cli.sh)**
Automates the installation of the IBM Cloud CLI for macOS and Linux.

- **[ibm_cloud_enum.sh](ibm_cloud_enum.sh)**
TBD - Executes all enumeration scripts against the IBM Cloud Account.

- **[public_buckets.py](public_buckets.py)**
Verifies if public access is enabled on the IBM Cloud account and enumerates all Cloud Object Storage buckets that are publicly accessible from the Internet.

## TODO
- ibm_cloud_enum.sh script
- Support for handling multiple IBM Cloud accounts in batch mode across all enumeration scripts.
- Implemente different output formats (json, table, csv)

## Creator
Heber Blain Gonçalves

- [linkedin.com/hebergoncalves/](https://linkedin.com/in/hebergoncalves/)
- [github.com/manotux](https://github.com/manotux)

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
