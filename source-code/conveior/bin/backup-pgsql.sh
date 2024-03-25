#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.config.backups.dbs_postgresql.[].name' ${CONFIG_FILE_DIR})
export IFS=$'\n'
for POD in $PODS;
do
  echo_message "Backing up ${POD}"

  export DATABASES_STR=""
  export SERVER_DIR="/tmp/${POD}"
  export FILE="${POD}-${DATE}.sql"
  export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"

  # try to get username from config
  export SQL_USER=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD\")) | .[].username" ${CONFIG_FILE_DIR})
  if [[ "${SQL_USER}" == "null" ]]; then
    export SQL_USER=$(docker exec -i ${POD} bash -c 'echo ${POSTGRES_USER}')
  fi

  # try to get password from config
  export SQL_PASS=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD\")) | .[].password" ${CONFIG_FILE_DIR})
  if [[ "${SQL_PASS}" == "null" ]]; then
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${POSTGRES_PASSWORD}')
  fi
  if [[ "${SQL_PASS}" == "" ]]; then
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'cat ${POSTGRES_PASSWORD_FILE}')
  fi

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  export DATABASE_ITEMS=$(docker exec -i ${POD} bash -c 'PGPASSWORD='${SQL_PASS}' psql -U '${SQL_USER}' -d postgres -c "SELECT datname FROM pg_database;" | awk '"'"'NR>3 {print last} {last=$0}'"'"' | awk -F " " '"'"'{print $1}'"'"' | head -n -1')
  export IFS=$'\n'
  for DATABASE_ITEM in $DATABASE_ITEMS;
  do
    if [[ "template0,template1,postgres" == *"${DATABASE_ITEM}"* ]]; then
      # echo "Skipping $DATABASE_ITEM"
      echo " "
    else
      echo "Backing up DB: $DATABASE_ITEM"
      docker exec -i "${POD}" bash -c "PGPASSWORD=$(echo $SQL_PASS) pg_dump -U ${SQL_USER} -d ${DATABASE_ITEM} > /tmp/${FILE}"

      docker cp "${POD}":/tmp/${FILE} ${SERVER_DIR}
      docker exec -i "${POD}" bash -c "rm /tmp/${FILE}"

      export ZIP_FILE_ONLY="${FILE}.zip"
      export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

      ENCRYPT=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD\")) | .[].encrypt" ${CONFIG_FILE_DIR})
      if [ "${ENCRYPT}" == "true" ]; then
        zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
      else
        zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
      fi

      rm "/${SERVER_DIR}/${FILE}"

      # upload file
      mkdir -p /tmp/s3/backup-pgsql/${POD}/${DATABASE_ITEM}/
      cp "${ZIP_FILE}" /tmp/s3/backup-pgsql/${POD}/${DATABASE_ITEM}/${ZIP_FILE_ONLY}
      rm "${ZIP_FILE}"
    fi
  done

done