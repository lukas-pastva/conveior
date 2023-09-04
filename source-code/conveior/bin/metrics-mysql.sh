#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.config.metrics.pods_mysql.[].name' ${CONFIG_FILE_DIR})
export METRICS=""
export IFS=$'\n'
for POD in $PODS;
do
  if [[ "${POD}" != "" ]]; then
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

    while read QUERY_NAME;
    do
      QUERY=$(yq e ".config.metrics.pods_mysql | with_entries(select(.value.name == \"$POD\")) | .[].queries | with_entries(select(.value.name == \"$QUERY_NAME\" )) | .[].query" ${CONFIG_FILE_DIR})
      if [[ "${QUERY^^}" != *"DROP"* ]]; then
        if [[ "${QUERY^^}" != *"UPDATE"* ]]; then
          if [[ "${QUERY^^}" != *"TRUNCATE"* ]]; then
            if [[ "${QUERY^^}" != *"DELETE"* ]]; then
              if [[ "${QUERY^^}" != *"ALTER"* ]]; then
                if [[ "${QUERY^^}" != *"INSERT"* ]]; then
                  echo ""
                  echo ""
                  echo ""
                  export QUERY_RESULT=$(echo "${QUERY}" | docker exec -i "${POD}" mysql -u${SQL_USER} -p${SQL_PASS} 2>/dev/null)
                  export IFS=$'\n'
                  for QUERY_LINE in ${QUERY_RESULT}; do
                    export RESULT_NAME=$(echo "${QUERY_LINE}" | awk -F'\t' '{print $1}')
                    export RESULT_VALUE=$(echo "${QUERY_LINE}" | awk -F'\t' '{print $2}')

                    if [ "$RESULT_VALUE" != "value" ]; then
                      if [ "$RESULT_VALUE" != "NULL" ]; then
                        METRIC="conveior_sql_query{pod=\"${POD}\",query_name=\"${QUERY_NAME}\",label_name=\"${RESULT_NAME}\"} ${RESULT_VALUE}"
                        METRICS=$(echo -e "$METRICS\n$METRIC")
                      fi
                    fi
                  done
                fi
              fi
            fi
          fi
        fi
      fi
    done < <(yq e ".config.metrics.pods_mysql | with_entries(select(.value.name == \"$POD\")) | .[].queries.[].name" ${CONFIG_FILE_DIR})
  fi
done

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  echo -e "$METRICS"
else
  echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"
fi

