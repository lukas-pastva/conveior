#!/bin/bash
source /action/action-functions.inc.sh

export IFS=","
for ITEM in ${BACKUP_CERTIFICATES}; do
  export CONTAINER_NAME=$(echo ${ITEM} | awk -F":" '{print $1}')
  export VOLUME=$(echo ${ITEM} | awk -F":" '{print $2}')
  export SERVER_DIR="/tmp/${CONTAINER_NAME}"
  export FILE="${CONTAINER_NAME}-${DATE}"
  export ZIP_FILE_ONLY="${FILE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

  export RUNNING=$(docker ps -f status=running --format "{{.Names}}" | grep -x "${CONTAINER_NAME}")
  if [[ "${RUNNING}" == *"${CONTAINER_NAME}"* ]]; then
    log_msg "Backing up certificates $ITEM"
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    docker cp ${CONTAINER_NAME}:${VOLUME} ${SERVER_DIR}
    cd "${SERVER_DIR}" && zip -rqq "${ZIP_FILE}" "."

    upload_file "${ZIP_FILE}" "${CUSTOMER}-${BRANCH}" "backup-certificate/${DATE}/${ZIP_FILE_ONLY}"
    api_post_item "backup-certificate" "${CONTAINER_NAME}/${ZIP_FILE_ONLY}" $(ls -nl "${ZIP_FILE}" | awk '{print $5}')
    rm "${ZIP_FILE}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  fi
done
