#!/bin/bash
source functions.inc.sh

# Fetch the list of pods to backup
PODS=$(yq e '.config.backups.files.[].name' ${CONFIG_FILE_DIR})

IFS=$'\n'
for POD in $PODS; do
  echo_message "Backing up $POD"

  # Fetching paths associated with this POD
  POD_PATHS=$(yq e ".config.backups.files[] | select(.name == \"$POD\") | .path" ${CONFIG_FILE_DIR})

  for POD_PATH in $POD_PATHS; do
    SERVER_DIR="/tmp/${POD}"
    FILE="${ANTI_DATE}-${POD}-${DATE}"
    ZIP_FILE_ONLY="${FILE}.zip"
    ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    if [[ $(docker exec -i "${POD}" bash -c "cd ${POD_PATH} && ls | wc -l") != "0" ]]; then
      echo "docker cp ${POD}:${POD_PATH} ${SERVER_DIR}"
      docker cp "${POD}:${POD_PATH}" "${SERVER_DIR}"
      LAST_DIR=$(echo ${POD_PATH} | awk -F"/" '{print $NF}')
      cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

      upload_file "${ZIP_FILE}" "backup-file/${POD}/${ZIP_FILE_ONLY}"
      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo "No files to backup in ${POD_PATH} for ${POD}"
    fi
  done
done
