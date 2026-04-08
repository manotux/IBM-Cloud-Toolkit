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

DEBUG=false
DEBUG_FULL=false
usage() {
    scriptname=$(basename "$0")
    echo "Usage: ./$scriptname [-h] [-o OUTPUT_DIR] [-v] [-d]"
    echo
    echo "Options:"
    echo "  -h              Show this help message"
    echo "  -o OUTPUT_DIR   Specify the output folder for results (default: 'output')"
    echo "  -v              Enable debug mode (outputs commands with redacted sensitive data)"
    echo "  -d              Show full debug output without redaction (requires -v)"
    echo
    echo "This script enumerates IBM Cloud Code Engine projects, applications, functions, configmaps, and secrets."
}

while getopts ":ho:vd" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        v)
            DEBUG=true
            ;;
        d)
            DEBUG_FULL=true
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

# Check if -d is used without -v
if [ "$DEBUG_FULL" = true ] && [ "$DEBUG" = false ]; then
    echo "Error: -d flag requires -v flag to be set" >&2
    usage
    exit 1
fi
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

# Counters
_PROJECTS=0
_APPS=0
_PUBLIC_APPS=0
_FUNCTIONS=0
_CONFIGMAPS=0
_SECRETS=0
echo " "
echo "${SEPARATOR}"
echo -e "Enumerating ${ORANGE}${BOLD}Code Engine Projects${RESET} across all regions via API..."
echo " "

# Debug output
if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Retrieving access token"
fi
# Get access token
IBMCLOUD_ACCESS_TOKEN=$(ibmcloud_access_token)
if [[ -z "${IBMCLOUD_ACCESS_TOKEN:-}" || "$IBMCLOUD_ACCESS_TOKEN" == "null" ]]; then
    failure "Failed to obtain IBM Cloud access token."
fi
if [ "$DEBUG" = true ]; then
    if [ "$DEBUG_FULL" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Access token: $IBMCLOUD_ACCESS_TOKEN"
    else
        TOKEN_PREFIX="${IBMCLOUD_ACCESS_TOKEN:0:20}"
        echo -e "${BOLD}[DEBUG]${RESET} Access token obtained (${TOKEN_PREFIX}...) [use -d flag for full token]"
    fi
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud resource groups --output json"
fi

# Get all resource groups
RESOURCE_GROUPS=$(ibmcloud resource groups --output json 2>&1) || true
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ] || [[ "$RESOURCE_GROUPS" =~ "FAILED" ]]; then
    failure "Failed to retrieve resource groups"
fi
if [[ -z "${RESOURCE_GROUPS:-}" || "$RESOURCE_GROUPS" == "[]" ]]; then
    failure "No resource groups found in this account"
fi

# Get a valid resource group (first available one)
FIRST_RG=$(echo "$RESOURCE_GROUPS" | jq -r '.[0].name')
if [[ -z "${FIRST_RG:-}" || "$FIRST_RG" == "null" ]]; then
    failure "Could not determine a valid resource group"
fi

if [ "$DEBUG" = true ]; then
    RG_COUNT=$(echo "$RESOURCE_GROUPS" | jq 'length')
    echo -e "${BOLD}[DEBUG]${RESET} Found $RG_COUNT resource group(s), using: $FIRST_RG"
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud target -r us-east -g \"$FIRST_RG\""
fi
# Target us-east region with the valid resource group
if ! ibmcloud target -r us-east -g "$FIRST_RG" -q &>/dev/null; then
    failure "Failed to target us-east region with resource group: $FIRST_RG"
fi

if [ "$DEBUG" = true ]; then
    echo -e "${BOLD}[DEBUG]${RESET} Running command: ibmcloud ce project list --all --output json"
fi
# List all projects across all regions/resource groups
PROJECTS=$(ibmcloud ce project list --all --output json 2>&1) || true
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ] || [[ "$PROJECTS" =~ "FAILED" ]]; then
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Failed to retrieve Code Engine projects"
    fi
    failure "Failed to retrieve Code Engine projects"
fi
if [[ -z "${PROJECTS:-}" || "$PROJECTS" == "[]" ]]; then
    echo "No Code Engine projects found"
    exit 0
else

    _PROJECTS=$(echo "$PROJECTS" | jq 'length')
    if [ "$DEBUG" = true ]; then
        echo -e "${BOLD}[DEBUG]${RESET} Found $TOTAL_PROJECTS Code Engine project(s)"
    fi
    ALL_APPS_JSON="[]"
    ALL_ENVVARS_JSON="[]"
    ALL_PUBLIC_APPS_JSON="[]"
    ALL_FUNCTIONS_JSON="[]"

    while IFS= read -r row; do
        project_name=$(echo "$row" | jq -r '.name')
        region_id=$(echo "$row" | jq -r '.region_id')
        project_id=$(echo "$row" | jq -r '.guid')

        if [ "$DEBUG" = true ]; then
            echo -e "${BOLD}[DEBUG]${RESET} Processing project: $project_name (region: $region_id)"
        fi
        # Retrieve Applications
        if [ "$DEBUG" = true ]; then
            if [ "$DEBUG_FULL" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/apps\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
            else
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/apps\" -H \"Authorization: Bearer <redacted>\""
            fi
        fi
        apps_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/apps" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$apps_json" && "$apps_json" != "{}" ]]; then
            apps_array=$(echo "$apps_json" | jq '.apps')
            apps_count=$(echo "$apps_array" | jq 'length')
            if [ "$DEBUG" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Project \"$project_name\": Found $apps_count application(s)"
            fi
            TOTAL_APPS=$((TOTAL_APPS + apps_count))
            ALL_APPS_JSON=$(jq -s 'add' <(echo "$ALL_APPS_JSON") <(echo "$apps_array"))

            # Extract env vars
            envvars=$(echo "$apps_json" | jq --arg pname "$project_name" '[.apps[] | {project: $pname, application: .name, run_env_variables: .run_env_variables}]')
            ALL_ENVVARS_JSON=$(jq -s 'add' <(echo "$ALL_ENVVARS_JSON") <(echo "$envvars"))

            # Public endpoints
            public_apps=$(echo "$apps_json" | jq --arg pname "$project_name" '[.apps[] | select(.managed_domain_mappings=="local_public") | {project: $pname, application: .name, managed_domain_mappings: .managed_domain_mappings, endpoint: .endpoint}]')
            public_count=$(echo "$public_apps" | jq 'length')
            if [[ $public_count -gt 0 ]]; then
                if [ "$DEBUG" = true ]; then
                    echo -e "${BOLD}[DEBUG]${RESET} Project \"$project_name\": Found $public_count public endpoint(s)"
                fi
                TOTAL_PUBLIC_APPS=$((TOTAL_PUBLIC_APPS + public_count))
                ALL_PUBLIC_APPS_JSON=$(jq -s 'add' <(echo "$ALL_PUBLIC_APPS_JSON") <(echo "$public_apps"))
            fi
        fi

        # Retrieve Functions
        if [ "$DEBUG" = true ]; then
            if [ "$DEBUG_FULL" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/functions\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
            else
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/functions\" -H \"Authorization: Bearer <redacted>\""
            fi
        fi
        functions_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/functions" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")

        if [[ -n "$functions_json" && "$functions_json" != "{}" ]]; then
            functions_obj=$(echo "$functions_json" | jq --arg pname "$project_name" '{project: $pname, functions: (.functions // [])}')
            functions_count=$(echo "$functions_obj" | jq '.functions | length')

            if [[ "$functions_count" -gt 0 ]]; then
                if [ "$DEBUG" = true ]; then
                    echo -e "${BOLD}[DEBUG]${RESET} Project \"$project_name\": Found $functions_count function(s)"
                fi
                TOTAL_FUNCTIONS=$((TOTAL_FUNCTIONS + functions_count))
                ALL_FUNCTIONS_JSON=$(jq -s 'add' <(echo "$ALL_FUNCTIONS_JSON") <(echo "[$functions_obj]"))
            fi
        fi

        # Retrieve Secrets
        if [ "$DEBUG" = true ]; then
            if [ "$DEBUG_FULL" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/secrets\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
            else
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/secrets\" -H \"Authorization: Bearer <redacted>\""
            fi
        fi
        secrets_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/secrets" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")
        if [[ -n "$secrets_json" && "$secrets_json" != "{}" ]]; then
            secrets_obj=$(echo "$secrets_json" | jq --arg pname "$project_name" '{project: $pname, secrets: (.secrets // [])}')
            secrets_count=$(echo "$secrets_obj" | jq '.secrets | length')

            if [[ "$secrets_count" -gt 0 ]]; then
                if [ "$DEBUG" = true ]; then
                    echo -e "${BOLD}[DEBUG]${RESET} Project \"$project_name\": Found $secrets_count secret(s)"
                fi
                TOTAL_SECRETS=$((TOTAL_SECRETS + secrets_count))
                ALL_SECRETS_JSON=$(jq -s 'add' <(echo "$ALL_SECRETS_JSON") <(echo "[$secrets_obj]"))
            fi
        fi

        # Retrieve ConfigMaps
        if [ "$DEBUG" = true ]; then
            if [ "$DEBUG_FULL" = true ]; then
                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/config_maps\" -H \"Authorization: Bearer $IBMCLOUD_ACCESS_TOKEN\""
            else
                                echo -e "${BOLD}[DEBUG]${RESET} Running: curl -X GET \"https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/config_maps\" -H \"Authorization: Bearer <redacted>\""
            fi
        fi
        configmaps_json=$(curl -s -X GET "https://api.${region_id}.codeengine.cloud.ibm.com/v2/projects/${project_id}/config_maps" -H "Authorization: Bearer ${IBMCLOUD_ACCESS_TOKEN}")

        if [[ -n "$configmaps_json" && "$configmaps_json" != "{}" ]]; then
            configmaps_obj=$(echo "$configmaps_json" | jq --arg pname "$project_name" '{project: $pname, configmaps: (.config_maps // [])}')
            configmaps_count=$(echo "$configmaps_obj" | jq '.configmaps | length')

            if [[ "$configmaps_count" -gt 0 ]]; then
                if [ "$DEBUG" = true ]; then
                    echo -e "${BOLD}[DEBUG]${RESET} Project \"$project_name\": Found $configmaps_count configmap(s)"
                fi
                TOTAL_CONFIGMAPS=$((TOTAL_CONFIGMAPS + configmaps_count))
                ALL_CONFIGMAPS_JSON=$(jq -s 'add' <(echo "$ALL_CONFIGMAPS_JSON") <(echo "[$configmaps_obj]"))
            fi
        fi

    done < <(echo "$PROJECTS" | jq -c '.[]')

fi

# Save Code Engine Projects
if [[ $(echo "$PROJECTS" | jq 'length') -gt 0 ]]; then
    : > "$PROJECTS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PROJECTS_OUTPUT_PATH${RESET}"
    echo "$PROJECTS" | jq '.' > "$PROJECTS_OUTPUT_PATH"
    echo -e "${BOLD}Total Projects: $TOTAL_PROJECTS${RESET}"
    echo -e "All Code Engine Projects saved to: ${BOLD}${PROJECTS_OUTPUT_PATH}${RESET}"
fi

# Save Code Engine Applications
if [[ $(echo "$ALL_APPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$APPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$APPS_OUTPUT_PATH${RESET}"
    echo "$ALL_APPS_JSON" | jq '.' > "$APPS_OUTPUT_PATH"
    echo -e "${BOLD}Total Applications: $TOTAL_APPS${RESET}"
    echo -e "Code Engine Applications saved to: ${BOLD}${APPS_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Total Applications: 0${RESET}"
fi

# Save Code Engine Apps Env Vars
if [[ $(echo "$ALL_ENVVARS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$ENVVARS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$ENVVARS_OUTPUT_PATH${RESET}"
    echo "$ALL_ENVVARS_JSON" | jq '.' > "$ENVVARS_OUTPUT_PATH"
    echo -e "Code Engine Applications Environment Variables saved to: ${BOLD}${ENVVARS_OUTPUT_PATH}${RESET}"
fi

# Save Code Engine Apps Public Endpoints
if [[ $(echo "$ALL_PUBLIC_APPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$PUBLIC_APPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$PUBLIC_APPS_OUTPUT_PATH${RESET}"
    echo "$ALL_PUBLIC_APPS_JSON" | jq '.' > "$PUBLIC_APPS_OUTPUT_PATH"
    echo -e "${BOLD}Applications with public endpoint: $TOTAL_PUBLIC_APPS${RESET}"
    echo -e "Code Engine Applications with public endpoint saved to: ${BOLD}${PUBLIC_APPS_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Applications with public endpoint: 0${RESET}"
fi

# Save Code Engine Functions
if [[ $(echo "$ALL_FUNCTIONS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$FUNCS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$FUNCS_OUTPUT_PATH${RESET}"
    echo "$ALL_FUNCTIONS_JSON" | jq '.' > "$FUNCS_OUTPUT_PATH"
    echo -e "${BOLD}Total Functions: $TOTAL_FUNCTIONS${RESET}"
    echo -e "Code Engine Functions saved to: ${BOLD}${FUNCS_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Total Functions: 0${RESET}"
fi

# Save Code Engine ConfigMaps
if [[ $(echo "$ALL_CONFIGMAPS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$CONFIGMAPS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$CONFIGMAPS_OUTPUT_PATH${RESET}"
    echo "$ALL_CONFIGMAPS_JSON" | jq '.' > "$CONFIGMAPS_OUTPUT_PATH"
    echo -e "${BOLD}Total ConfigMaps: $TOTAL_CONFIGMAPS${RESET}"
    echo -e "Code Engine ConfigMaps saved to: ${BOLD}${CONFIGMAPS_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Total ConfigMaps: 0${RESET}"
fi

# Save Code Engine Secrets
if [[ $(echo "$ALL_SECRETS_JSON" | jq 'length') -gt 0 ]]; then
    : > "$SECRETS_OUTPUT_PATH" || failure "Error while creating the output file: ${BOLD}$SECRETS_OUTPUT_PATH${RESET}"
    echo "$ALL_SECRETS_JSON" | jq '.' > "$SECRETS_OUTPUT_PATH"
    echo -e "${BOLD}Total Secrets: $TOTAL_SECRETS${RESET}"
    echo -e "Code Engine Secrets saved to: ${BOLD}${SECRETS_OUTPUT_PATH}${RESET}"
else
    echo -e "${BOLD}Total Secrets: 0${RESET}"
fi
if [ "$DEBUG" = true ]; then
    echo " "
    echo -e "${BOLD}[DEBUG]${RESET} Summary:"
    echo -e "${BOLD}[DEBUG]${RESET}   Projects: $TOTAL_PROJECTS"
    echo -e "${BOLD}[DEBUG]${RESET}   Applications: $TOTAL_APPS"
    echo -e "${BOLD}[DEBUG]${RESET}   Public Endpoints: $TOTAL_PUBLIC_APPS"
    echo -e "${BOLD}[DEBUG]${RESET}   Functions: $TOTAL_FUNCTIONS"
    echo -e "${BOLD}[DEBUG]${RESET}   ConfigMaps: $TOTAL_CONFIGMAPS"
    echo -e "${BOLD}[DEBUG]${RESET}   Secrets: $TOTAL_SECRETS"
fi

echo ""
echo -e "Review Env Vars and ConfigMaps for secrets using tools like TruffleHog/detect-secrets or manually."

ibmcloud target --unset-resource-group -q &>/dev/null
