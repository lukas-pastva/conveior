#!/bin/bash
source functions.inc.sh

api_get_json "https://${MYSQL_API_URL}/devopssql/list"
export SQL_QUERIES_JSON=${func_result}
export IFS=","
for CONTAINER_NAME in ${CONTAINERS_PGSQL}; do

  log_msg "Sending queries from PostreSQL for ${CONTAINER_NAME}"

  # export SQL_PASS=$(docker exec -i ${CONTAINER_NAME} bash -c 'echo ${POSTGRES_PASSWORD}')
  # export SQL_USER="root"
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

#"SELECT 'dbSize' as api, CONCAT(schema_name, '/',relname) as name, table_size as value FROM (SELECT pg_catalog.pg_namespace.nspname AS schema_name, relname, pg_relation_size(pg_catalog.pg_class.oid) AS table_size FROM pg_catalog.pg_class JOIN pg_catalog.pg_namespace ON relnamespace = pg_catalog.pg_namespace.oid) t WHERE schema_name NOT LIKE 'pg_%' AND table_size > 81920 ORDER BY table_size DESC;"

                export QUERY_RESULT=$(echo ${QUERY} | docker exec -i ${CONTAINER_NAME} psql telegram_connector)
                export JSON=""
                export i=0
                export IFS=$'\n'
                for QUERY_LINE in ${QUERY_RESULT}; do
                  if [[ "${i}" == "1" ]]; then
                    echo " "
                  else
                    export API=$(echo ${QUERY_LINE} | awk -F'|' '{print $1}' | awk '{$1=$1;print}')
                    export NAME=$(echo ${QUERY_LINE} | awk -F'|' '{print $2}' | awk '{$1=$1;print}')
                    export VALUE=$(echo ${QUERY_LINE} | awk -F'|' '{print $3}' | awk '{$1=$1;print}')

                    if [ -n "$VALUE" ]; then
                      if [[ "$VALUE" != "NULL" ]]; then
                        # VALUE=$(echo ${VALUE} | jq '.|ceil')
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