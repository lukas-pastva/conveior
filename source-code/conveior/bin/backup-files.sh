#!/bin/bash
source functions.inc.sh
set -e
trap '/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-files overall=0 0' ERR

# Fetch the list of pods to backup
PODS=$(yq e '.config.backups.files.[].name' ${CONFIG_FILE_DIR})

IFS=$'\n'
for POD in $PODS; do
  echo_message "Backing up $POD"

  # Fetching paths associated with this POD
  POD_PATHS=$(yq e ".config.backups.files[] | select(.name == \"$POD\") | .path" ${CONFIG_FILE_DIR})

  for POD_PATH in $POD_PATHS; do
    SERVER_DIR="/tmp/${POD}"
    PATH_NAME=$(echo ${POD_PATH} | sed 's|/|_|g')
    FILE="${ANTI_DATE}-${POD}-${PATH_NAME}-${DATE}"
    ZIP_FILE_ONLY="${FILE}.zip"
    ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    if [[ $(docker exec -i "${POD}" bash -c "cd ${POD_PATH} && ls | wc -l") != "0" ]]; then
      docker cp "${POD}:${POD_PATH}" "${SERVER_DIR}"
      LAST_DIR=$(echo ${POD_PATH} | awk -F"/" '{print $NF}')
      cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

      upload_file "${ZIP_FILE}" "backup-file/${POD}/${ZIP_FILE_ONLY}"
      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo "No files to backup in ${POD_PATH} for ${POD}"
    fi
  done

  # <-- push success=1 metric
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-files pod=$POD 1

done
