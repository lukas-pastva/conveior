#!/bin/bash
source functions.inc.sh

export IFS=","
for CONTAINER_SHORT in ${CONTAINERS_MYSQL}; do
  get_container_name "${CONTAINER_SHORT}"
  CONTAINER="${func_result}"
  if [[ "${CONTAINER}" != "" ]]; then
    echo_prom_helper "Backing up MySQL ${CONTAINER}"
  
    export DATABASES_STR=""
    export SERVER_DIR="/tmp/${CONTAINER_SHORT}"
    export FILE="${CONTAINER_SHORT}-${DATE}.sql"
    export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"
    export SQL_USER="root"
    export SQL_PASS=$(docker exec -i ${CONTAINER} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    export DATABASE_ITEMS=$(echo 'show databases;' | docker exec -i ${CONTAINER} bash -c "mysql -u ${SQL_USER} -p'${SQL_PASS}'" 2>/dev/null | grep -Fv -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys' )
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_ITEMS;
    do
      DATABASES_STR="${DATABASE_ITEM} ${DATABASES_STR}"
    done
    echo_prom_helper "Fount DBs: ${DATABASES_STR}"
    docker exec -i ${CONTAINER} bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null"
  
    docker cp ${CONTAINER}:/tmp/${FILE} ${SERVER_DIR}
    docker exec -i ${CONTAINER} bash -c "rm /tmp/${FILE}"
  
    export ZIP_FILE_ONLY="${FILE}.zip"
    export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"
    zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
    rm "/${SERVER_DIR}/${FILE}"

    upload_file "${ZIP_FILE}" "${CUSTOMER}" "backup-mysql/${DATE}/${ZIP_FILE_ONLY}"

    rm "${ZIP_FILE}"
  fi
done