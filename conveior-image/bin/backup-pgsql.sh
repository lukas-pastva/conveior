#!/bin/bash
source functions.inc.sh

export IFS=","
for CONTAINER_NAME in ${CONTAINERS_PGSQL}; do
  echo_prom_helper "Backing up Postgres SQL ${CONTAINER_NAME}"

  export SERVER_DIR="/tmp/${CONTAINER_NAME}"
  export FILE="dump-${CONTAINER_NAME}-${DATE}.sql"
  export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"

  mkdir -p ${SERVER_DIR}
  find ${SERVER_DIR} -mindepth 1 -delete

  export SQL_PASS=$(docker exec -i ${CONTAINER_NAME} bash -c 'echo ${POSTGRES_PASSWORD}')
  export SQL_USER="root"

  docker exec -i ${CONTAINER_NAME} bash -c "pg_dumpall -U ${SQL_USER} > /tmp/${FILE}"

  docker cp ${CONTAINER_NAME}:/tmp/${FILE} ${SERVER_DIR}
  docker exec -i ${CONTAINER_NAME} bash -c "rm /tmp/${FILE}"

  export ZIP_FILE_ONLY="${FILE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"
  zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
  rm "/${SERVER_DIR}/${FILE}"

  upload_file "${ZIP_FILE}" "${CUSTOMER}-${BRANCH}" "backup-db/${DATE}/${ZIP_FILE_ONLY}"

  api_post_item "backup" "${CONTAINER_NAME}/${ZIP_FILE_ONLY}" $(ls -nl ${ZIP_FILE} | awk '{print $5}')

  rm "${ZIP_FILE}"

done