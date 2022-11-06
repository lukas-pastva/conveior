#!/bin/bash
source functions.inc.sh

#export SQL_QUERIES_JSON=${func_result}
export IFS=","
for POD_NAME in ${PODS_MYSQL}; do

  echo_prom_helper "Sending queries from MySQL for ${POD_NAME}"

  export SQL_PASS=$(docker exec -i ${POD_NAME} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')

  export SQL_USER="root"
  export QUERY_LIST=$(echo "${SQL_QUERIES_JSON}" | jq -r ".[] | select(.container==\"${POD_NAME}\") | .query")
  export IFS=$';'
  for QUERY in ${QUERY_LIST}; do
    QUERY=$(echo "${QUERY}" | tr '\r' ' ' | tr '\n' ' ')
    if [[ "${QUERY^^}" != *"DROP"* ]]; then
      if [[ "${QUERY^^}" != *"UPDATE"* ]]; then
        if [[ "${QUERY^^}" != *"TRUNCATE"* ]]; then
          if [[ "${QUERY^^}" != *"DELETE"* ]]; then
            if [[ "${QUERY^^}" != *"ALTER"* ]]; then
              if [[ "${QUERY^^}" != *"INSERT"* ]]; then
                echo_prom_helper "executing query: ${QUERY}"

                export QUERY_RESULT=$(echo ${QUERY} | docker exec -i "${POD_NAME}" mysql -u${SQL_USER} -p${SQL_PASS})
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
  done
done