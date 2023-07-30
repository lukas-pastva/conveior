#!/bin/bash
source functions.inc.sh

export POD_SHORT_LIST=$(yq e '.conveior-config.backups.dbs_mysql.[].name' /home/conveior-config.yaml)
export IFS=$'\n'
for POD_SHORT in $POD_SHORT_LIST;
do
  echo_message "Backing up ${POD_SHORT}"

  export POD_NAMESPACE=$(yq e ".conveior-config.backups.dbs_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].namespace" /home/conveior-config.yaml)
  export POD_LIST=$(eval "kubectl -n ${POD_NAMESPACE} get pods --no-headers -o custom-columns=\":metadata.name\" | grep ${POD_SHORT}")

  # workaround if fount more pods
  for POD in $POD_LIST;
  do
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
      export SQL_PASS=$(eval "kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c 'echo \${MYSQL_ROOT_PASSWORD}'")
    fi
    echo "POD: $POD"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    export DATABASE_ITEMS=$(eval "kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- mysql -u ${SQL_USER} -p'${SQL_PASS}' -e \"show databases;\" 2>/dev/null" )
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
      eval "kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c \"mysqldump --user=${SQL_USER} --password='${SQL_PASS}' --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE} 2>/dev/null\""
      eval "kubectl cp ${POD_NAMESPACE}/${POD}:/tmp/${FILE} ${SERVER_DIR}/${FILE}"
      eval "kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c \"rm /tmp/${FILE}\""

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
  done
done
