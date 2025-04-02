#!/bin/bash
source functions.inc.sh
set -e
trap '/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-pgsql-k8s overall=0 0' ERR

export POD_SHORT_LIST=$(yq e '.config.backups.dbs_postgresql.[].name' ${CONFIG_FILE_DIR})
export IFS=$'\n'
for POD_SHORT in $POD_SHORT_LIST; do
  echo_message "Backing up ${POD_SHORT}"

  export POD_NAMESPACE=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].namespace" ${CONFIG_FILE_DIR})
  export POD_LIST=$(eval "kubectl -n ${POD_NAMESPACE} get pods --no-headers -o custom-columns=\":metadata.name\" | grep ${POD_SHORT}")

  for POD in $POD_LIST; do
    export DATABASES_STR=""
    export SERVER_DIR="/tmp/${POD_SHORT}"
    export FILE="${POD_SHORT}-${DATE}.sql"
    export DESTINATION_FILE="${SERVER_DIR}/${FILE}.gz"

    export SQL_USER=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].username" ${CONFIG_FILE_DIR})
    export SQL_PASS=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].password" ${CONFIG_FILE_DIR})
    echo "POD: $POD"

    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    export DATABASE_ITEMS=$(kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c "export PGPASSWORD='${SQL_PASS}' && psql -U '${SQL_USER}' -d postgres -c 'SELECT datname FROM pg_database;'" | tail -n +3 | head -n -2)
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_ITEMS; do
      DATABASE_ITEM=$(echo $DATABASE_ITEM | sed 's/^ *//')
      if [[ "template0,template1,postgres" == *"${DATABASE_ITEM}"* ]]; then
        echo " "
      else
        echo "Backing up DB: $DATABASE_ITEM"

        kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c "export PGPASSWORD=$SQL_PASS && pg_dump -U ${SQL_USER} -d ${DATABASE_ITEM} > /tmp/${FILE}"
        kubectl cp ${POD_NAMESPACE}/${POD}:/tmp/${FILE} ${SERVER_DIR}/${FILE}
        kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c "rm /tmp/${FILE}"

        export ZIP_FILE_ONLY="${FILE}.zip"
        export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

        ENCRYPT=$(yq e ".config.backups.dbs_postgresql | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].encrypt" ${CONFIG_FILE_DIR})
        if [ "${ENCRYPT}" == "true" ]; then
          zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${SERVER_DIR}/${FILE}"
        else
          zip -qq "${ZIP_FILE}" "/${SERVER_DIR}/${FILE}"
        fi

        rm "/${SERVER_DIR}/${FILE}"
        upload_file "${ZIP_FILE}" "backup-pgsql/${POD_SHORT}/${DATABASE_ITEM}/${ZIP_FILE_ONLY}"

        rm "${ZIP_FILE}"
      fi
    done
  done

  # <-- push success=1 metric (once per $POD_SHORT)
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-pgsql-k8s pod=$POD_SHORT 1

done
