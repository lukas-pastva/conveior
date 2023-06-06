#!/bin/bash
source functions.inc.sh

set -e

export PODS=$(yq e '.conveior-config.backups.dbs_mysql.[].name' /home/conveior-config.yaml)
export IFS=$'\n'
for POD in $PODS;
do
  echo_message "Backing up ${POD}"

  export DATABASES_STR=""
  export SERVER_DIR="/tmp/${POD}"
  export FILE="${POD}-${DATE}.sql"

  # try to get username from config
  export SQL_USER=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].username" /home/conveior-config.yaml)
  if [[ "${SQL_USER}" == "null" ]]; then
    export SQL_USER="root"
  fi

  # try to get password from config
  export SQL_PASS=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].password" /home/conveior-config.yaml)
  if [[ "${SQL_PASS}" == "null" ]]; then
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
  fi

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  export DATABASE_ITEMS=$(echo 'show databases;' | docker exec -i "${POD}" bash -c "mysql -u ${SQL_USER} -p'${SQL_PASS}'" 2>/dev/null )
  export IFS=$'\n'
  for DATABASE_ITEM in $DATABASE_ITEMS;
  do
    if [[ "${DATABASE_ITEM}" != "Database" ]]; then
      if [[ "${DATABASE_ITEM}" != "information_schema" ]]; then
        if [[ "${DATABASE_ITEM}" != "mysql" ]]; then
          if [[ "${DATABASE_ITEM}" != "performance_schema" ]]; then
            if [[ "${DATABASE_ITEM}" != "sys" ]]; then
              DATABASES_STR="${DATABASE_ITEM} ${DATABASES_STR}"
            fi
          fi
        fi
      fi
    fi
  done
  echo_message "Fount DBs: ${DATABASES_STR}"
  if [[ "${DATABASES_STR}" != "" ]]; then
    docker exec -i "${POD}" bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null"
    docker cp "${POD}":/tmp/${FILE} ${SERVER_DIR}
    docker exec -i "${POD}" bash -c "rm /tmp/${FILE}"

    export ZIP_FILE_ONLY="${FILE}.zip"
    export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

    ENCRYPT=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].encrypt" /home/conveior-config.yaml)
    if [ "${ENCRYPT}" == "true" ]; then
      zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
    else
      zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
    fi

    rm "/${SERVER_DIR}/${FILE}"

    echo_message "splitting"
    split -a 1 -b 4096M -d "${ZIP_FILE}" "${ZIP_FILE}."

    echo_message "deleting"
    rm "${ZIP_FILE}"

    find "${SERVER_DIR}" -mindepth 1 -maxdepth 1 | while read SPLIT_FILE;
    do
      export SPLIT_FILE_ONLY=$(echo "${SPLIT_FILE}" | awk -F"/" '{print $(NF)}')
      upload_file "${SERVER_DIR}/${SPLIT_FILE_ONLY}" "backup-mysql/${POD}/$(( 10000000000 - $(date +%s) ))-${DATE}/${SPLIT_FILE_ONLY}"
      rm "${SERVER_DIR}/${SPLIT_FILE_ONLY}"
    done

  fi

done