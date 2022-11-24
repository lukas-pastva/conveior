#!/bin/bash
source functions.inc.sh

while read POD_SHORT;
do
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Backing up $ITEM"

    export POD_PATH=$(yq e ".backups.files | with_entries(select(.value.name == \"$POD_SHORT\")) | .0.path" /home/conveior-config.yaml)
    export SERVER_DIR="/tmp/${POD_SHORT}"
    export FILE="${POD_SHORT}-${DATE}"
    export ZIP_FILE_ONLY="${FILE}.zip"
    export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    if [[ $(docker exec -i "${POD}" bash -c "cd ${POD_PATH} && ls | wc -l") != "0" ]]; then
      docker cp ${POD}:${POD_PATH} ${SERVER_DIR}
      export LAST_DIR=$(echo ${POD_PATH} | awk -F"/" '{print $NF}')
      cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

      upload_file "${ZIP_FILE}" "backup-file/${POD_SHORT}/${ZIP_FILE_ONLY}"
      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo_prom_helper "Empty directory ${POD_PATH}, nothing to backup"
    fi
  fi
done < <(yq e '.backups.files.[].name' /home/conveior-config.yaml)
