#!/bin/bash
source functions.inc.sh

export CONTAINERS_MYSQL="web-portal-sql,web-lzk-sql"

export IFS=","
for CONTAINER_NAME_SHORT in ${CONTAINERS_MYSQL}; do
#  CONTAINER_NAME_SHORT="k8s_${CONTAINER_NAME_SHORT}"
  export CONTAINER_NAME=$(docker ps -f status=running --format "{{.Names}}" | grep -v POD | grep "${CONTAINER_NAME_SHORT}")
  if [[ "${CONTAINER_NAME}" == *"${CONTAINER_NAME_SHORT}"* ]]; then
    echo_prom_helper "Sending info about MySQL for ${CONTAINER_NAME}"

    export MYSQL_PASS=$(docker exec -i "${CONTAINER_NAME}" bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    export MYSQL_USER="root"
    export QUERY='SHOW DATABASES WHERE `Database` <> "mysql" and `Database` <> "information_schema" and `Database` <> "performance_schema" and `Database` <> "sys"'
    export DATABASE_LIST=$(echo ${QUERY} | docker exec -i ${CONTAINER_NAME} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" 2> /dev/null | tail -n+2 )

    export IFS=$'\n'
    for DATABASE in ${DATABASE_LIST}; do
     export QUERY2="SELECT TABLE_NAME AS name, (data_length + index_length) AS value FROM information_schema.TABLES WHERE information_schema.TABLES.table_schema = '${DATABASE}' and information_schema.TABLES.Table_Type = 'BASE TABLE'"
     export TABLE_SIZE_LIST=$(echo ${QUERY2} | docker exec -i ${CONTAINER_NAME} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" 2> /dev/null | tail -n+2 )

      export IFS=$'\n'
      for TABLE_SIZE in ${TABLE_SIZE_LIST}; do
        export SIZE=$(echo ${TABLE_SIZE} | awk '{print $2}')
        export TABLE=$(echo ${TABLE_SIZE} | awk '{print $1}')
        PROMETHEUS_DATA+=$'\n'"conveior_mysql_table_size{name=${CONTAINER_NAME_SHORT}/${DATABASE}/${TABLE}} ${SIZE}"
      done
    done
  fi
done

echo "${PROMETHEUS_DATA}"