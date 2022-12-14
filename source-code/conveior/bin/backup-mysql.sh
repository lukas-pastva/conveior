#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.conveior-config.backups.dbs_mysql.[].name' /home/conveior-config.yaml)
export IFS=$'\n'
for POD_SHORT in $PODS;
do
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Backing up ${POD}"

    export DATABASES_STR=""
    export SERVER_DIR="/tmp/${POD_SHORT}"
    export FILE="${POD_SHORT}-${DATE}.sql"
    export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"

    # try to get username from config
    export SQL_USER=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].username" /home/conveior-config.yaml)
    if [[ "${SQL_USER}" == "null" ]]; then
      export SQL_USER="root"
    fi

    # try to get password from config
    export SQL_PASS=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].password" /home/conveior-config.yaml)
    if [[ "${SQL_PASS}" == "null" ]]; then
      export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    fi

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

      ENCRYPT=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].encrypt" /home/conveior-config.yaml)
      if [ "${ENCRYPT}" == "true" ]; then
        zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
      else
        zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
      fi

      rm "/${SERVER_DIR}/${FILE}"
      upload_file "${ZIP_FILE}" "backup-mysql/${POD_SHORT}/${ZIP_FILE_ONLY}"

      rm "${ZIP_FILE}"
    fi
  fi
done
