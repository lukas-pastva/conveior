#!/bin/bash
source functions.inc.sh

export IFS=","
for ITEM in ${BACKUP}; do
  echo_prom_helper "Backing up files $ITEM"

  export CONTAINER_NAME=$(echo ${ITEM} | awk -F":" '{print $1}')
  export VOLUME=$(echo ${ITEM} | awk -F":" '{print $2}')
  export SERVER_DIR="/tmp/${CONTAINER_NAME}"
  export FILE="${CONTAINER_NAME}-${DATE}"
  export ZIP_FILE_ONLY="${FILE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  if [[ $(docker exec -i ${CONTAINER_NAME} bash -c "cd ${VOLUME} && ls | wc -l") != "0" ]]; then

    docker cp ${CONTAINER_NAME}:${VOLUME} ${SERVER_DIR}
    export LAST_DIR=$(echo ${VOLUME} | awk -F"/" '{print $NF}')
    cd "${SERVER_DIR}/${LAST_DIR}" && zip -rqq "${ZIP_FILE}" "."

    upload_file "${ZIP_FILE}" "${CUSTOMER}" "backup-file/${DATE}/${ZIP_FILE_ONLY}"
    rm "${ZIP_FILE}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  else
    echo_prom_helper "Empty directory ${VOLUME}, nothing to backup"
  fi
done