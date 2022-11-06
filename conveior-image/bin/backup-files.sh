#!/bin/bash
source functions.inc.sh

if [[ "${1}" != "" ]]; then
  export BACKUP_FILES="${1}"
fi

export IFS=","
for ITEM in ${BACKUP_FILES}; do
  export POD_SHORT=$(echo ${ITEM} | awk -F":" '{print $1}')
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Backing up $ITEM"

    export VOLUME=$(echo ${ITEM} | awk -F":" '{print $2}')
    export SERVER_DIR="/tmp/${POD_SHORT}"
    export FILE="${POD_SHORT}-${DATE}"
    export ZIP_FILE_ONLY="${FILE}.zip"
    export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    if [[ $(docker exec -i "${POD}" bash -c "cd ${VOLUME} && ls | wc -l") != "0" ]]; then
      docker cp ${POD}:${VOLUME} ${SERVER_DIR}
      export LAST_DIR=$(echo ${VOLUME} | awk -F"/" '{print $NF}')
      cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

      upload_file "${ZIP_FILE}" "backup-file/${POD_SHORT}/${ZIP_FILE_ONLY}"
      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo_prom_helper "Empty directory ${VOLUME}, nothing to backup"
    fi
  fi
done