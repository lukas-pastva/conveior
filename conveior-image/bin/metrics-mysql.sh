#!/bin/bash
source functions.inc.sh

while read POD_SHORT;
do
  get_pod_name "${POD_SHORT}"
  POD="${func_result}"
  if [[ "${POD}" != "" ]]; then
    echo_prom_helper "Sending queries from MySQL for ${POD_SHORT}"
    export SQL_PASS=$(docker exec -i ${POD} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    export SQL_USER="root"

    while read NAME;
    do
      QUERY=$(yq e ".metrics.pods_mysql | with_entries(select(.value.name == \"$POD_SHORT\"))" /home/conveior-config.yaml | yq e ".0.queries | with_entries(select(.value.name == \"$NAME\" ))" | yq e ".[].query")
      if [[ "${QUERY^^}" != *"DROP"* ]]; then
        if [[ "${QUERY^^}" != *"UPDATE"* ]]; then
          if [[ "${QUERY^^}" != *"TRUNCATE"* ]]; then
            if [[ "${QUERY^^}" != *"DELETE"* ]]; then
              if [[ "${QUERY^^}" != *"ALTER"* ]]; then
                if [[ "${QUERY^^}" != *"INSERT"* ]]; then
                  echo_prom_helper "executing query: ${QUERY}"

                  export QUERY_RESULT=$(echo ${QUERY} | docker exec -i "${POD}" mysql -u${SQL_USER} -p${SQL_PASS})
                  export PROMETHEUS_DATA=""
                  export i=0
                  export IFS=$'\n'
                  for QUERY_LINE in ${QUERY_RESULT}; do
                    if [[ "${i}" == "0" ]]; then
                      export QUERY_COLUMNS=${QUERY_LINE}
                    else
                      export API=$(echo ${QUERY_LINE} | awk -F'\t' '{print $1}')
                      export NAME=$(echo ${QUERY_LINE} | awk -F'\t' '{print $2}')
                      export VALUE=$(echo ${QUERY_LINE} | awk -F'\t' '{print $3}')

                      if [ -n "$VALUE" ]; then
                        if [[ "$VALUE" != "NULL" ]]; then
                          VALUE=$(echo ${VALUE} | jq '.|ceil')
                          if [[ $VALUE =~ ^-?[0-9]+$ ]]; then
                            # if [ "$VALUE" -gt 0 ]; then
                            PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"${API}\",\"name\":\"${NAME}\",\"value\":${VALUE}},";
                            # fi
                          fi
                        fi
                      fi
                    fi
                    i=$((i + 1))
                  done
                  echo "${PROMETHEUS_DATA}"
                fi
              fi
            fi
          fi
        fi
      fi
    done < <(yq e ".metrics.pods_mysql | with_entries(select(.value.name == \"$POD_SHORT\"))" /home/conveior-config.yaml | yq e '.0.queries.[].name')
  fi
done < <(yq e '.metrics.pods_mysql.[].name' /home/conveior-config.yaml)
