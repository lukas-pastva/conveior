#!/bin/bash
source functions.inc.sh

export IFS=","
for CONTAINER_SHORT in ${CONTAINERS_MYSQL}; do
  get_container_name "${CONTAINER_SHORT}"
  CONTAINER="${func_result}"
  if [[ "${CONTAINER}" != "" ]]; then
    echo_prom_helper "Sending info about MySQL for ${CONTAINER}"

    export MYSQL_PASS=$(docker exec -i "${CONTAINER}" bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
    export MYSQL_USER="root"
    export QUERY='SHOW DATABASES WHERE `Database` <> "mysql" and `Database` <> "information_schema" and `Database` <> "performance_schema" and `Database` <> "sys"'
    export DATABASE_LIST=$(echo ${QUERY} | docker exec -i ${CONTAINER} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" 2> /dev/null | tail -n+2 )

    export IFS=$'\n'
    for DATABASE in ${DATABASE_LIST}; do
     export QUERY2="SELECT TABLE_NAME AS name, (data_length + index_length) AS value FROM information_schema.TABLES WHERE information_schema.TABLES.table_schema = '${DATABASE}' and information_schema.TABLES.Table_Type = 'BASE TABLE'"
     export TABLE_SIZE_LIST=$(echo ${QUERY2} | docker exec -i ${CONTAINER} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" 2> /dev/null | tail -n+2 )

      export IFS=$'\n'
      for TABLE_SIZE in ${TABLE_SIZE_LIST}; do
        export SIZE=$(echo ${TABLE_SIZE} | awk '{print $2}')
        export TABLE=$(echo ${TABLE_SIZE} | awk '{print $1}')
        PROMETHEUS_DATA+=$'\n'"conveior_mysql_table_size{name=${CONTAINER_SHORT}/${DATABASE}/${TABLE}} ${SIZE}"
      done
    done
  fi
done

echo "${PROMETHEUS_DATA}"