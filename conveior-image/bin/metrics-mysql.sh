#!/bin/bash
source functions.inc.sh

while read POD_SHORT;
do
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Queries for ${POD_SHORT}"
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    export SQL_USER="root"

    while read QUERY_NAME;
    do
      QUERY=$(yq e ".conveior-config.metrics.pods_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .0.queries | with_entries(select(.value.name == \"$QUERY_NAME\" )) | .[].query" /home/conveior-config.yaml)
      if [[ "${QUERY^^}" != *"DROP"* ]]; then
        if [[ "${QUERY^^}" != *"UPDATE"* ]]; then
          if [[ "${QUERY^^}" != *"TRUNCATE"* ]]; then
            if [[ "${QUERY^^}" != *"DELETE"* ]]; then
              if [[ "${QUERY^^}" != *"ALTER"* ]]; then
                if [[ "${QUERY^^}" != *"INSERT"* ]]; then
                  echo_prom_helper "executing query: ${QUERY}"

                  export QUERY_RESULT=$(echo "${QUERY}" | docker exec -i "${POD}" mysql -u${SQL_USER} -p${SQL_PASS} 2>/dev/null)
                  export IFS=$'\n'
                  for QUERY_LINE in ${QUERY_RESULT}; do
                    export RESULT_NAME=$(echo "${QUERY_LINE}" | awk -F'\t' '{print $1}')
                    export RESULT_VALUE=$(echo "${QUERY_LINE}" | awk -F'\t' '{print $2}')

                    if [ "$RESULT_VALUE" != "value" ]; then
                        echo "conveior_sql_query{pod=\"${POD_SHORT}\",query_name:\"${QUERY_NAME}\",result_name:\"${RESULT_NAME}\"} ${RESULT_VALUE}"
                    fi
                  done
                fi
              fi
            fi
          fi
        fi
      fi
    done < <(yq e ".conveior-config.metrics.pods_mysql | with_entries(select(.value.name == \"$POD_SHORT\")) | .0.queries.[].name" /home/conveior-config.yaml)
  fi
done < <(yq e '.conveior-config.metrics.pods_mysql.[].name' /home/conveior-config.yaml)
