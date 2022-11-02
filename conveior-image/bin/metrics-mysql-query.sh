#!/bin/bash
source functions.inc.sh

api_get_json "https://${MYSQL_API_URL}/devopssql/list"
export SQL_QUERIES_JSON=${func_result}
export IFS=","
for CONTAINER_NAME in ${CONTAINERS_MYSQL}; do

  log_msg "Sending queries from MySQL for ${CONTAINER_NAME}"

  export SQL_PASS=$(docker exec -i ${CONTAINER_NAME} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
  if [[ "${SQL_PASS}" == "secret" ]]; then
    api_get_vault "${CUSTOMER}-${CONTAINER_NAME}-MYSQL_PASS"
    SQL_PASS=${func_result}
  fi

  export SQL_USER="root"
  export QUERY_LIST=$(echo "${SQL_QUERIES_JSON}" | jq -r ".[] | select(.container==\"${CONTAINER_NAME}\") | .query")
  export IFS=$';'
  for QUERY in ${QUERY_LIST}; do
    QUERY=$(echo "${QUERY}" | tr '\r' ' ' | tr '\n' ' ')
    if [[ "${QUERY^^}" != *"DROP"* ]]; then
      if [[ "${QUERY^^}" != *"UPDATE"* ]]; then
        if [[ "${QUERY^^}" != *"TRUNCATE"* ]]; then
          if [[ "${QUERY^^}" != *"DELETE"* ]]; then
            if [[ "${QUERY^^}" != *"ALTER"* ]]; then
              if [[ "${QUERY^^}" != *"INSERT"* ]]; then
                log_msg "executing query: ${QUERY}"

                export QUERY_RESULT=$(echo ${QUERY} | docker exec -i ${CONTAINER_NAME} mysql -u${SQL_USER} -p${SQL_PASS})
                export JSON=""
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
                          JSON="${JSON}{\"chart\":\"${API}\",\"name\":\"${NAME}\",\"value\":${VALUE}},";
                          # fi
                        fi
                      fi
                    fi
                  fi
                  i=$((i + 1))
                done
                api_post_list "${JSON}"
              fi
            fi
          fi
        fi
      fi
    fi
  done
done