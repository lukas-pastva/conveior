#!/bin/bash
source functions.inc.sh

export IFS=","
for CONTAINER_NAME in ${CONTAINERS_MYSQL}; do
  echo_prom_helper "Backing up MySQL ${CONTAINER_NAME}"

  export DATABASES_STR=""
  export SERVER_DIR="/tmp/${CONTAINER_NAME}"
  export FILE="dump-${CONTAINER_NAME}-${DATE}.sql"
  export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"
  export SQL_USER="root"

  mkdir -p ${SERVER_DIR}
  find ${SERVER_DIR} -mindepth 1 -delete

  export SQL_PASS=$(docker exec -i ${CONTAINER_NAME} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')

  if [[ "secret,<Change-Me-On-Server>" == *"${SQL_PASS}"* ]]; then
  api_get_vault "${CUSTOMER}-${CONTAINER_NAME}-MYSQL_PASS"
    SQL_PASS=${func_result}
  fi

  export DATABASE_ITEMS=$(echo 'show databases;' | docker exec -i ${CONTAINER_NAME} bash -c "mysql -u ${SQL_USER} -p'${SQL_PASS}'" | grep -Fv -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys' )
  export IFS=$'\n'
  for DATABASE_ITEM in $DATABASE_ITEMS;
  do
    DATABASES_STR="${DATABASE_ITEM} ${DATABASES_STR}"
  done
  echo_prom_helper "Fount DBs: ${DATABASES_STR}"
  docker exec -i ${CONTAINER_NAME} bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE}"

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