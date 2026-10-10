#!/bin/bash

function vault_secret_get_item() {
  local secretPath="$1"
  local key="$2"
  local RETURN_VALUE="false"

  local response=$(curl -s --header "X-Vault-Token: $GLOBAL_VAULT_TOKEN" "$VAULT_ADDR/v1/kv/data/$secretPath")
  local value=$(echo "$response" | jq -r ".data.data[\"$key\"]")

  if [[ "$value" != "null" ]] && [[ -n "$value" ]]; then
    RETURN_VALUE="$value"
  fi
  echo "${RETURN_VALUE}"
}

function vault_secret_item_check_if_exists(){
  local secretPath="$1"
  local key="$2"

  local response=$(curl -s --header "X-Vault-Token: $GLOBAL_VAULT_TOKEN" "$VAULT_ADDR/v1/kv/data/$secretPath")

  # Check if there was an error in the response indicating the secret does not exist
  if echo "$response" | grep -q "errors"; then
    echo "The secret at path '$secretPath' does not exist or there was an error retrieving it."
    return 1
  fi

  # Check if the key exists in the response
  echo "$response" | grep -q "\"$key\""
  if [ $? -eq 0 ]; then
    # "Key '$key' exists in the secret at path '$secretPath'."
    return 0
  else
    # "Key '$key' does not exist in the secret at path '$secretPath'."
    return 1
  fi
}

function vault_secret_add_item() {
  local secretPath=$1
  local newKey=$2
  local newValue=$3
  local currentSecret=$(curl -s -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" "${VAULT_ADDR}/v1/kv/data/${secretPath}" | jq '.data.data')
  local updatedSecret=$(echo ${currentSecret} | jq --arg key "${newKey}" --arg value "$newValue" '. + {($key): $value}')
  curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" -H "Content-Type: application/json" --data "{\"data\": ${updatedSecret}}" "${VAULT_ADDR}/v1/kv/data/${secretPath}"
}
function vault_secret_item_add_line() {
  local secretPath=$1
  local targetKey=$2
  local newLineValue=$3

  # Fetch the current secret from Vault
  local currentSecretData=$(curl -s -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" "${VAULT_ADDR}/v1/kv/data/${secretPath}" | jq -r ".data.data")

  # Extract the current value of the target key
  local currentSecret=$(echo "$currentSecretData" | jq -r ".\"$targetKey\"")

  # Append the new line to the existing value
  local updatedValue="${currentSecret}
${newLineValue}"

  # Update the target key with the new value
  local updatedSecret=$(echo "$currentSecretData" | jq --arg key "$targetKey" --arg value "$updatedValue" '.[$key] = $value')

  # Prepare the updated secret payload
  local updatedSecretPayload=$(jq -n --argjson data "$updatedSecret" '{data: $data}')

  # Update the secret in Vault
  local statusCode=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "X-Vault-Token: ${GLOBAL_VAULT_TOKEN}" \
    -H "Content-Type: application/json" --data "$updatedSecretPayload" \
    "${VAULT_ADDR}/v1/kv/data/${secretPath}")

  # Optional: Check if the operation was successful
  if [[ "$statusCode" != "200" ]]; then
    echo_with_time "Failed to update the secret. Status code: $statusCode"
  fi
}


function vault_secrets_delete_with_test_prefix() {
    # Prompt for Vault token
    echo -n "Enter Vault Token: "
    read -rs VAULT_TOKEN
    echo "" # Move to a new line

    # Set Vault address
    local VAULT_ADDR="http://localhost:8200"

    # List groups with the 'test-' prefix
    local GROUPS_LIST=$(curl -s -X LIST --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp" | jq -r '.data.keys[]' | grep ^test-)

    if [ -z "$GROUPS_LIST" ]; then
        echo "No groups matching 'test-' prefix found."
        kill $PF_PID
        return
    fi

    # Save and change IFS to only split on newlines
    OLD_IFS=$IFS
    IFS=$'\n'

    while read -r group; do
        group="${group%/}/" # Ensure group ends with a slash

        local SECRETS_LIST=$(curl -s -X LIST --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp/$group" | jq -r '.data.keys[]')

        if [ -z "$SECRETS_LIST" ] || [ "$SECRETS_LIST" == "null" ]; then
            echo "No secrets found in group $group"
            continue
        fi

        echo "The following secrets will be deleted in group $group:"
        echo "$SECRETS_LIST"

        echo -n "Secrets from group $group above, will be now deleted, you have 10 seconds to cancel... "
        sleep 10

        echo "$SECRETS_LIST" | while read -r secret; do
            echo "Deleting secret: $group$secret"
            curl --request DELETE --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/metadata/remp/$group$secret"
        done
    done < <(echo "$GROUPS_LIST")

    IFS=$OLD_IFS
}

function vault_backup() {

    function _fetch_secrets_recursively() {
        local vault_path="$1"
        # Remove leading and trailing slashes for consistency
        vault_path="${vault_path#/}"  # Removes leading slash
        vault_path="${vault_path%/}"  # Removes trailing slash

        # Perform the API call to list directories or secrets
        local metadata_response=$(curl -s --header "X-Vault-Token: $VAULT_TOKEN" --request LIST "$VAULT_ADDR/v1/kv/metadata/$vault_path")
        # Check for errors in the metadata response
        if echo "$metadata_response" | jq -e '.errors | length > 0' >/dev/null; then
            echo "Error fetching metadata from path: $vault_path"
            echo "Response was: $metadata_response"
            return 1
        fi

        # Extract the list of keys; check first if there are any keys
        local keys_exist=$(echo "$metadata_response" | jq -e '.data.keys != null' >/dev/null)
        if [ "$keys_exist" = false ]; then
            echo "No directories or secrets found at path: $vault_path"
            return 1
        fi

        echo "$metadata_response" | jq -r '.data.keys[]' | while IFS= read -r key; do
            local new_path="$vault_path/$key"
            if [[ "$key" == */ ]]; then
                # It's a directory, recurse into it
                _fetch_secrets_recursively "$new_path"
            else
              # It's a secret key, fetch the secret data
              local secret_data=$(curl -s --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/kv/data/$new_path" | jq -e '.data.data')
              # Assuming data is always present, directly append it to your file
              echo "\"$new_path\": $secret_data," >> ./"$FILENAME_SECRETS"
            fi
        done
    }

    function _fetch_and_save_policies() {
        # Retrieve list of policies
        curl --silent --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/policy" | \
        jq -r '.data.keys[]' | while IFS= read -r policy; do
            # Fetch individual policy data
            local policy_data=$(curl --silent --header "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/policy/$policy" | jq -c '.data.rules')
            echo "\"$policy\": $policy_data" >> "$FILENAME_POLICIES"
        done
    }

    # Helper function to backup Kubernetes tokens
    function _vault_backup_tokens_k8s() {
        local TIMESTAMP=$(date +%Y-%m-%d_T%H-%M-%S)
        echo "Backing up Kubernetes secrets with names ending in '-token' into $FILENAME_TOKENS..."

        IFS=$' ' # Change the Internal Field Separator to newline
        local namespaces=($(kubectl get ns -o jsonpath="{.items[*].metadata.name}"))

        for ns in "${namespaces[@]}"; do
            kubectl get secrets -n "$ns" -o json | jq -r '.items[] | select(.metadata.name | endswith("-token")) | .metadata.name' | while read secret; do
                # Append secret data to the backup file in YAML format, separated by ---
                kubectl get secret "$secret" -n "$ns" -o yaml >> "$FILENAME_TOKENS"
                echo "---" >> "$FILENAME_TOKENS"
            done
        done
    }

    echo -n "Enter Vault Token (will be hidden): "
    read -rs VAULT_TOKEN
    echo ""

    local VAULT_ADDR="http://localhost:8200"
    local TIMESTAMP=$(date +%Y-%m-%d_T%H-%M-%S)
    local FILENAME_SECRETS="vault_secrets_backup_${TIMESTAMP}.json"
    local FILENAME_POLICIES="vault_policies_backup_${TIMESTAMP}.json"
    local FILENAME_TOKENS="k8s_tokens_backup_${TIMESTAMP}.yaml"

    echo "Starting backup, this will take time..."

    _fetch_secrets_recursively ""
    _fetch_and_save_policies
    _vault_backup_tokens_k8s

    # Optional: Uncomment to sync with LastPass (if configured)
    # lpass add --non-interactive --sync=now "Vault Backup/${TIMESTAMP}" --note-type="Generic Note" < ./"$FILENAME"

    echo "Backup completed."
}