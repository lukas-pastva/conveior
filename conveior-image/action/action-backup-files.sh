#!/bin/bash
source /action/action-functions.inc.sh

export IFS=","
for ITEM in ${BACKUP}; do
  log_msg "Backing up files $ITEM"

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

    upload_file "${ZIP_FILE}" "${CUSTOMER}-${BRANCH}" "backup-file/${DATE}/${ZIP_FILE_ONLY}"
    api_post_item "backup" "${CONTAINER_NAME}/${ZIP_FILE_ONLY}" $(ls -nl "${ZIP_FILE}" | awk '{print $5}')
    rm "${ZIP_FILE}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  else
    log_msg "Empty directory ${VOLUME}, nothing to backup"
  fi
done