#!/bin/bash
source functions.inc.sh

if [[ "${1}" != "" ]]; then
  export BACKUP_FILES="${1}"
fi

export IFS=","
for ITEM in ${BACKUP_FILES}; do
  export POD=$(echo ${ITEM} | awk -F":" '{print $1}')
  get_container_name "${POD}"
  CONTAINER="${func_result}"
  if [[ "${CONTAINER}" != "" ]]; then
    echo_prom_helper "Backing up $ITEM"

    export VOLUME=$(echo ${ITEM} | awk -F":" '{print $2}')
    export SERVER_DIR="/tmp/${POD}"
    export FILE="${POD}-${DATE}"
    export ZIP_FILE_ONLY="${FILE}.zip"
    export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    if [[ $(docker exec -i "${CONTAINER}" bash -c "cd ${VOLUME} && ls | wc -l") != "0" ]]; then
      docker cp ${CONTAINER}:${VOLUME} ${SERVER_DIR}
      export LAST_DIR=$(echo ${VOLUME} | awk -F"/" '{print $NF}')
      cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

      upload_file "${ZIP_FILE}" "backup-file/${POD}/${ZIP_FILE_ONLY}"
#      find "${SERVER_DIR}" -mindepth 1 -delete
    else
      echo_prom_helper "Empty directory ${VOLUME}, nothing to backup"
    fi
  fi
done