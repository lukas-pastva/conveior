#!/bin/bash
source functions.inc.sh

if [[ "${1}" != "" ]]; then
  export PODS_MYSQL="${1}"
fi

export IFS=","
for POD_SHORT in ${PODS_MYSQL}; do
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Backing up ${POD}"
  
    export DATABASES_STR=""
    export SERVER_DIR="/tmp/${POD_SHORT}"
    export FILE="${POD_SHORT}-${DATE}.sql"
    export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"
    export SQL_USER="root"
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    export DATABASE_ITEMS=$(echo 'show databases;' | docker exec -i "${POD}" bash -c "mysql -u ${SQL_USER} -p'${SQL_PASS}'" 2>/dev/null | grep -Fv -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys' )
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_ITEMS;
    do
      DATABASES_STR="${DATABASE_ITEM} ${DATABASES_STR}"
    done
    echo_prom_helper "Fount DBs: ${DATABASES_STR}"
    if [[ "${DATABASES_STR}" != "" ]]; then
      docker exec -i "${POD}" bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null"

      docker cp "${POD}":/tmp/${FILE} ${SERVER_DIR}
      docker exec -i "${POD}" bash -c "rm /tmp/${FILE}"

      export ZIP_FILE_ONLY="${FILE}.zip"
      export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"
      zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
      rm "/${SERVER_DIR}/${FILE}"

      upload_file "${ZIP_FILE}" "backup-mysql/${POD_SHORT}/${ZIP_FILE_ONLY}"

      rm "${ZIP_FILE}"
    fi
  fi
done