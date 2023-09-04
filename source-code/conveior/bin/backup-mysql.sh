#!/bin/bash
source functions.inc.sh

set -e

export PODS=$(yq e '.config.backups.dbs_mysql.[].name' ${CONFIG_FILE_DIR})
export IFS=$'\n'
for POD in $PODS;
do
  echo_message "Backing up ${POD}"

  export SERVER_DIR="/tmp/${POD}"
  export FILE="backup.sql"
  export DATABASES_STR=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].databases" ${CONFIG_FILE_DIR})

  # try to get username from config
  export SQL_USER=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].username" ${CONFIG_FILE_DIR})
  if [[ "${SQL_USER}" == "null" ]]; then
    export SQL_USER="root"
  fi

  # try to get password from config
  export SQL_PASS=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].password" ${CONFIG_FILE_DIR})
  if [[ "${SQL_PASS}" == "null" ]]; then
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
  fi

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  docker exec -i "${POD}" bash -c "mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null"
  docker cp "${POD}":/tmp/${FILE} ${SERVER_DIR}
  docker exec -i "${POD}" bash -c "rm /tmp/${FILE}"

  export ZIP_FILE_ONLY="${FILE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

  ENCRYPT=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD\")) | .[].encrypt" ${CONFIG_FILE_DIR})
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
    upload_file "${SERVER_DIR}/${SPLIT_FILE_ONLY}" "backup-mysql/${POD}/${ANTI_DATE}-${DATE}/${SPLIT_FILE_ONLY}"
    rm "${SERVER_DIR}/${SPLIT_FILE_ONLY}"
  done

done