#!/usr/bin/env bash

# get_code_engine.sh
#
# This script enumerates all IBM Cloud Code Engine projects in each enabled region, along with:
#   - Applications (including environment variables and public endpoints)
#   - Functions
#   - ConfigMaps
#   - Secrets
# Requires IBM Cloud CLI and code-engine plugin. Requires jq for JSON processing.

srcdir="$(dirname "${BASH_SOURCE[0]}")"
. "$srcdir/utils.sh"

OUTPUT_DIR="output"

usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo
    echo "This script enumerates IBM Cloud Code Engine projects, applications, functions, configmaps, and secrets."
}

while getopts ":ho:" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
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
require_curl
require_ibmcloud_login
require_ibmcloud_ce

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || failure "Error while creating the output directory: ${BOLD}$OUTPUT_DIR${RESET}"
fi

PROJECTS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_projects.json"
APPS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_apps.json"
ENVVARS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_apps_envvars.json"
PUBLIC_APPS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_apps_public_endpoints.json"
FUNCS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_functions.json"
CONFIGMAPS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_configmaps.json"
SECRETS_OUTPUT_PATH="${OUTPUT_DIR}/code_engine_secrets.json"

PROJECTS="[]"
ALL_APPS_JSON="[]"
ALL_FUNCS_JSON="[]"
ALL_CONFIGMAPS_JSON="[]"
ALL_SECRETS_JSON="[]"

echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}Code Engine Projects${RESET} across all regions via API..."
echo " "

# Target only us-east region and Default resource group
if ! ibmcloud target -r us-east -g Default -q &>/dev/null; then
    failure "Failed to target us-east region with Default resource group"
fi

# Get access token
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)
if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "$IBMCLOUD_ACCESS_TOKEN" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token. Check IBMCLOUD_API_KEY."
fi

# List all projects across all regions/resource groups
PROJECTS=$(ibmcloud ce project list --all --output json 2>/dev/null) || failure "Failed to retrieve Code Engine projects"
if [[ -z "${PROJECTS:-}" || "$PROJECTS" == "[]" ]]; then
    echo "No Code Engine projects found"
    exit 0
else

    ALL_APPS_JSON="[]"
    ALL_ENVVARS_JSON="[]"
    ALL_PUBLIC_APPS_JSON="[]"
    ALL_FUNCTIONS_JSON="[]"

    while IFS= read -r row; do
        project_name=$(echo "$row" | jq -r '.name')
        region_id=$(echo "$row" | jq -r '.region_id')
        project_id=$(echo "$row" | jq -r '.guid')

        apps_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/apps" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$apps_json" && "$apps_json" != "{}" ]]; then
            # Accumulate apps list
            apps_array=$(echo "$apps_json" | jq '.apps')
            ALL_APPS_JSON=$(jq -s 'add' <(echo "$ALL_APPS_JSON") <(echo "$apps_array"))

            # Extract env vars
            envvars=$(echo "$apps_json" | jq --arg pname "$project_name" '[.apps[] | {project: $pname, name: .name, run_env_variables: .run_env_variables}]')
            ALL_ENVVARS_JSON=$(jq -s 'add' <(echo "$ALL_ENVVARS_JSON") <(echo "$envvars"))

            # Public endpoints
            public_apps=$(echo "$apps_json" | jq --arg pname "$project_name" '[.apps[] | select(.managed_domain_mappings=="local_public") | {project: $pname, name: .name, managed_domain_mappings: .managed_domain_mappings}]')
            if [[ $(echo "$public_apps" | jq 'length') -gt 0 ]]; then
                ALL_PUBLIC_APPS_JSON=$(jq -s 'add' <(echo "$ALL_PUBLIC_APPS_JSON") <(echo "$public_apps"))
            fi
        fi
        functions_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/functions" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$functions_json" && "$functions_json" != "{}" ]]; then
            # Accumulate functions list
            functions_array=$(echo "$functions_json" | jq '.functions')
            ALL_FUNCTIONS_JSON=$(jq -s 'add' <(echo "$ALL_FUNCTIONS_JSON") <(echo "$functions_array"))
        fi

        # Retrieve ConfigMaps
        configmaps_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/config_maps" \
            -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$configmaps_json" && "$configmaps_json" != "{}" ]]; then
            configmaps_array=$(echo "$configmaps_json" | jq '.config_maps')
            if [[ $(echo "$configmaps_array" | jq 'length') -gt 0 ]]; then
                ALL_CONFIGMAPS_JSON=$(jq -s 'add' <(echo "$ALL_CONFIGMAPS_JSON") <(echo "$configmaps_array"))
            fi
        fi

        # Retrieve Secrets
        secrets_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/secrets" \
            -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$secrets_json" && "$secrets_json" != "{}" ]]; then
            secrets_array=$(echo "$secrets_json" | jq '.secrets')
            if [[ $(echo "$secrets_array" | jq 'length') -gt 0 ]]; then
                ALL_SECRETS_JSON=$(jq -s 'add' <(echo "$ALL_SECRETS_JSON") <(echo "$secrets_array"))
            fi
        fi

    done < <(echo "$PROJECTS" | jq -c '.[]')

fi

# Save Code Engine Projects
if [[ $(echo "$PROJECTS" | jq 'length') -gt 0 ]]; then
    : > "$PROJECTS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PROJECTS_OUTPUT_PATH${RESET}"
    echo "$PROJECTS" | jq '.' > "$PROJECTS_OUTPUT_PATH"
    echo -e "All Code Engine Projects saved to: ${BOLD}${PROJECTS_OUTPUT_PATH}${RESET}"
fi

# Save Code Engine Applications
if [[ $(echo "$ALL_APPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$APPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$APPS_OUTPUT_PATH${RESET}"
    echo "$ALL_APPS_JSON" | jq '.' > "$APPS_OUTPUT_PATH"
    echo -e "Code Engine Applications saved to: ${BOLD}${APPS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine Applications found."
fi

# Save Code Engine Apps Env Vars
if [[ $(echo "$ALL_ENVVARS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$ENVVARS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$ENVVARS_OUTPUT_PATH${RESET}"
    echo "$ALL_ENVVARS_JSON" | jq '.' > "$ENVVARS_OUTPUT_PATH"
    echo -e "Code Engine Applications Environment Variables saved to: ${BOLD}${ENVVARS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine Environment Variables found."
fi

# Save Code Engine Apps Public Endpoints
if [[ $(echo "$ALL_PUBLIC_APPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$PUBLIC_APPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_APPS_OUTPUT_PATH${RESET}"
    echo "$ALL_PUBLIC_APPS_JSON" | jq '.' > "$PUBLIC_APPS_OUTPUT_PATH"
    echo -e "Code Engine Applications with public endpoint saved to: ${BOLD}${PUBLIC_APPS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine Applications with public endpoint enabled."
fi

# Save Code Engine Functions
if [[ $(echo "$ALL_FUNCTIONS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$FUNCS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$FUNCS_OUTPUT_PATH${RESET}"
    echo "$ALL_FUNCTIONS_JSON" | jq '.' > "$FUNCS_OUTPUT_PATH"
    echo -e "Code Engine Functions saved to: ${BOLD}${FUNCS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine Functions found."
fi

# Save Code Engine ConfigMaps
if [[ $(echo "$ALL_CONFIGMAPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$CONFIGMAPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CONFIGMAPS_OUTPUT_PATH${RESET}"
    echo "$ALL_CONFIGMAPS_JSON" | jq '.' > "$CONFIGMAPS_OUTPUT_PATH"
    echo -e "Code Engine ConfigMaps saved to: ${BOLD}${CONFIGMAPS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine ConfigMaps found."
fi

# Save Code Engine Secrets
if [[ $(echo "$ALL_SECRETS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$SECRETS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$SECRETS_OUTPUT_PATH${RESET}"
    echo "$ALL_SECRETS_JSON" | jq '.' > "$SECRETS_OUTPUT_PATH"
    echo -e "Code Engine Secrets saved to: ${BOLD}${SECRETS_OUTPUT_PATH}${RESET}"
else
    echo "No Code Engine Secrets found."
fi

echo -e "Review Env Vars and ConfigMaps for secrets using tools like TruffleHog/detect-secrets or manually."