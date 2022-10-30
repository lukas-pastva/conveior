#!/bin/bash
source /action/action-functions.inc.sh


export IFS=","
for CONTAINER_NAME in ${CONTAINERS_MYSQL}; do

  log_msg "Sending info about MySQL for ${CONTAINER_NAME}"

  export MYSQL_PASS=$(docker exec -i ${CONTAINER_NAME} bash -c 'echo ${MYSQL_ROOT_PASSWORD}')
  if [[ "${MYSQL_PASS}" == "secret" ]]; then
    api_get_vault "${CUSTOMER}-${CONTAINER_NAME}-MYSQL_PASS"
    MYSQL_PASS=${func_result}
  fi

  export MYSQL_USER="root"
  export QUERY='SHOW DATABASES WHERE `Database` <> "mysql" and `Database` <> "information_schema" and `Database` <> "performance_schema" and `Database` <> "sys"'
  export DATABASE_LIST=$(echo ${QUERY} | docker exec -i ${CONTAINER_NAME} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" | tail -n+2)

  export IFS=$'\n'
  for DATABASE in ${DATABASE_LIST}; do
   export QUERY2="SELECT TABLE_NAME AS name, (data_length + index_length) AS value FROM information_schema.TABLES WHERE information_schema.TABLES.table_schema = '${DATABASE}' and information_schema.TABLES.Table_Type = 'BASE TABLE'"
   export TABLE_SIZE_LIST=$(echo ${QUERY2} | docker exec -i ${CONTAINER_NAME} bash -c "mysql -u${MYSQL_USER} -p'${MYSQL_PASS}'" | tail -n+2)

    export IFS=$'\n'
    for TABLE_SIZE in ${TABLE_SIZE_LIST}; do
      export SIZE=$(echo ${TABLE_SIZE} | awk '{print $2}')
      export TABLE=$(echo ${TABLE_SIZE} | awk '{print $1}')
      JSON="${JSON}{\"chart\":\"dbSize\",\"name\":\"${CONTAINER_NAME}/${DATABASE}/${TABLE}\",\"value\":${SIZE}},"
    done
  done
done
api_post_list "${JSON}"