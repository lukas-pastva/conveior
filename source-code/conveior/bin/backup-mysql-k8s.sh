#!/bin/bash
source functions.inc.sh

POD_SHORT_LIST=$(yq e '.config.backups.dbs_mysql.[].name' "${CONFIG_FILE_DIR}")
IFS=$'\n'
for POD_SHORT in $POD_SHORT_LIST;
do
  echo_message "Backing up ${POD_SHORT}"

  POD_NAMESPACE=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].namespace" "${CONFIG_FILE_DIR}")
  
  POD_REGEX="^${POD_SHORT}-([a-z0-9]+-[a-z0-9]+|[0-9]+)$"
  POD_LIST=$(kubectl -n "${POD_NAMESPACE}" get pods --no-headers -o custom-columns=":metadata.name" | grep -E "${POD_REGEX}" | head -n 1)
  for POD in $POD_LIST;
  do
    DATABASES_STR=""
    SERVER_DIR="/tmp/${POD_SHORT}"
    FILE="${POD_SHORT}-${DATE}.sql"
    DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"

    # try to get username from config
    SQL_USER=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].username" "${CONFIG_FILE_DIR}")
    if [[ "${SQL_USER}" == "null" ]]; then
      SQL_USER="root"
    fi

    # try to get password from config
    SQL_PASS=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].password" "${CONFIG_FILE_DIR}")
    if [[ "${SQL_PASS}" == "null" ]]; then
      SQL_PASS=$(kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    fi

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    DATABASE_ITEMS=$(kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- bash -c "mysql -u '${SQL_USER}' -p'${SQL_PASS}' -e 'show databases;' 2>/dev/null")
    IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_ITEMS;
    do
      if [[ "${DATABASE_ITEM}" != "Database" ]] && \
         [[ "${DATABASE_ITEM}" != "information_schema" ]] && \
         [[ "${DATABASE_ITEM}" != "mysql" ]] && \
         [[ "${DATABASE_ITEM}" != "performance_schema" ]] && \
         [[ "${DATABASE_ITEM}" != "sys" ]]; then
        DATABASES_STR="${DATABASE_ITEM} ${DATABASES_STR}"
      fi
    done
    echo_message "Found DBs: ${DATABASES_STR}"
    if [[ "${DATABASES_STR}" != "" ]]; then
      kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --single-transaction --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null"
      kubectl cp "${POD_NAMESPACE}/${POD}:/tmp/${FILE}" "${SERVER_DIR}/${FILE}" >/dev/null
      kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- bash -c "rm /tmp/${FILE}"

      ZIP_FILE_ONLY="${FILE}.zip"
      ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

      ENCRYPT=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].encrypt" "${CONFIG_FILE_DIR}")
      if [ "${ENCRYPT}" == "true" ]; then
        zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
      else
        zip -qq "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
      fi

      rm "${SERVER_DIR}/${FILE}"
      upload_file "${ZIP_FILE}" "backup-mysql/${POD_SHORT}/${ZIP_FILE_ONLY}"

      rm "${ZIP_FILE}"
    fi
  done
done
