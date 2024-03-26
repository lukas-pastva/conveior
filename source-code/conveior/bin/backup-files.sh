#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.config.backups.files.[].name' ${CONFIG_FILE_DIR})
export IFS=$'\n'
for POD in $PODS;
do
  echo_message "Backing up $POD"

  export POD_PATH=$(yq e ".config.backups.files | with_entries(select(.value.name == \"$POD\")) | .[].path" ${CONFIG_FILE_DIR})

  export SERVER_DIR="/tmp/${POD}"
  export FILE="${ANTI_DATE}-${POD}-${DATE}"
  export ZIP_FILE_ONLY="${FILE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  if [[ $(docker exec -i "${POD}" bash -c "cd ${POD_PATH} && ls | wc -l") != "0" ]]; then
    docker cp ${POD}:${POD_PATH} ${SERVER_DIR}
    export LAST_DIR=$(echo ${POD_PATH} | awk -F"/" '{print $NF}')
    cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

    upload_file "${ZIP_FILE}" "backup-file/${POD}/${ZIP_FILE_ONLY}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  fi
done
