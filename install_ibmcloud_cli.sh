#!/usr/bin/env bash

# This script will install the IBM Cloud CLI
# Requires curl

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

read -rp "Install and Configure IBM Cloud CLI? (y/n) " INSTALL
if [[ $INSTALL =~ ^([yY])$ ]]; then

    # Check if ibmcloud CLI is already installed
    if ! check_command "ibmcloud"; then
        echo "IBM Cloud CLI not found. Installing..."

        # Detect OS and install accordingly
        OS_TYPE="$(uname -s)"
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            echo "Detected macOS."
            echo "Running: curl -fsSL https://clis.cloud.ibm.com/install/osx | sh"
            curl -fsSL https://clis.cloud.ibm.com/install/osx | sh
        elif [[ "$OS_TYPE" == "Linux" ]]; then
            echo "Detected Linux."
            echo "Running: curl -fsSL https://clis.cloud.ibm.com/install/linux | sh"
            curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
        else
            echo "Unsupported OS: $OS_TYPE"
            exit 1
        fi
        echo "IBM Cloud CLI installed."
    else
        echo "IBM Cloud CLI already installed."
    fi

    echo
    echo "To log in, run: ibmcloud login"
    echo "For more info, see: https://cloud.ibm.com/docs/cli"
    echo "Completed."
fi