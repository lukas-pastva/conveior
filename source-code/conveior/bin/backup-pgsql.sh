#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.conveior-config.backups.dbs_pgsql.[].name' /home/conveior-config.yaml)
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
    export SQL_USER=$(yq e ".conveior-config.backups.dbs_pgsql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].username" /home/conveior-config.yaml)
    if [[ "${SQL_USER}" == "null" ]]; then
      export SQL_USER=$(docker exec -i ${POD} bash -c 'echo ${POSTGRES_USER}')
    fi

    # try to get passowrd from config
    export SQL_PASS=$(yq e ".conveior-config.backups.dbs_pgsql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].password" /home/conveior-config.yaml)
    if [[ "${SQL_PASS}" == "null" ]]; then
      export SQL_PASS=$(docker exec -i ${POD} bash -c 'cat ${POSTGRES_PASSWORD_FILE}')
    fi

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    export DATABASE_ITEMS=$(docker exec -i ${POD} bash -c 'PGPASSWORD=$(cat $POSTGRES_PASSWORD_FILE) psql -U gitlab -d postgres -c "SELECT datname FROM pg_database;" | awk '"'"'NR>3 {print last} {last=$0}'"'"' | awk -F " " '"'"'{print $1}'"'"' | head -n -1')
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_ITEMS;
    do
      if [[ "template0,template1,postgres" == *"${DATABASE_ITEM}"* ]]; then
        echo "Skipping $DATABASE_ITEM"
      else
        echo "Backing up DB: $DATABASE_ITEM"
        docker exec -i "${POD}" bash -c "PGPASSWORD=$(echo $SQL_PASS) pg_dump -U ${SQL_USER} -d ${DATABASE_ITEM} > /tmp/${FILE}"

        docker cp "${POD}":/tmp/${FILE} ${SERVER_DIR}
        docker exec -i "${POD}" bash -c "rm /tmp/${FILE}"

        export ZIP_FILE_ONLY="${FILE}.zip"
        export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

        ENCRYPT=$(yq e ".conveior-config.backups.dbs_pgsql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].encrypt" /home/conveior-config.yaml)
        if [ "${ENCRYPT}" == "true" ]; then
          zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
        else
          zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
        fi

        rm "/${SERVER_DIR}/${FILE}"
        upload_file "${ZIP_FILE}" "backup-pgsql/${POD_SHORT}/${ZIP_FILE_ONLY}"

        rm "${ZIP_FILE}"
      fi
    done
  fi
done