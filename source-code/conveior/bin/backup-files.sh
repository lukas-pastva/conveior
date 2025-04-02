#!/bin/bash
source functions.inc.sh
set -e

# Send metric if there's an error at any point
trap '/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-files overall=0 0' ERR

# Fetch the list of pods to back up
PODS=$(yq e '.config.backups.files.[].name' "${CONFIG_FILE_DIR}")

IFS=$'\n'
for POD in $PODS; do
  echo_message "Backing up $POD"

  # Fetch the paths associated with this POD
  POD_PATHS=$(yq -r ".config.backups.files[] | select(.name == \"$POD\") | .path[]" "${CONFIG_FILE_DIR}")

  for POD_PATH in $POD_PATHS; do
    SERVER_DIR="/tmp/${POD}"
    PATH_NAME=$(echo "${POD_PATH}" | sed 's|/|_|g')
    FILE="${ANTI_DATE}-${POD}-${PATH_NAME}-${DATE}"
    ZIP_FILE_ONLY="${FILE}.zip"
    ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    # Create/reset the local directory
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    # Check if there are files to back up
    if [[ $(docker exec -i "${POD}" bash -c "cd \"${POD_PATH}\" && ls | wc -l") != "0" ]]; then
      # Copy from container to host
      docker cp "${POD}:${POD_PATH}" "${SERVER_DIR}"

      # Determine the last directory name
      LAST_DIR=$(echo "${POD_PATH}" | awk -F"/" '{print $NF}')

      # Use a subshell to zip inside the directory
      (
        cd "${SERVER_DIR}/${LAST_DIR}" || exit 1
        zip -rqq "${ZIP_FILE}" .
      )

      # Upload the zip to your desired location
      upload_file "${ZIP_FILE}" "backup-file/${POD}/${ZIP_FILE_ONLY}"

      # Clean up after zipping
      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo "No files to backup in ${POD_PATH} for ${POD}"
    fi
  done

  # Send success=1 metric per pod
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-files pod="${POD}" 1

done
