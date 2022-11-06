#!/bin/bash
source functions.inc.sh

if [ -z "${CONTAINER_SHORT+xxx}" ]; then
  if [ -z "${NAMESPACE+xxx}" ]; then
    read -p "Namespace " NAMESPACE
    export NAMESPACE="${NAMESPACE}"
  fi
  if [ -z "${POD+xxx}" ]; then
    read -p "Pod " POD
    export POD="${POD}"
  fi
  export CONTAINER_SHORT="${NAMESPACE}_${POD}"
fi

if [ -z "${FILE_ZIP+xxx}" ]; then
  read -p "Location of the zip file to be downloaded (example: bucket/dir/file.zip) " FILE_ZIP
  export FILE_ZIP="${FILE_ZIP}"
fi

if [ -z "${DROP_DBS+xxx}" ]; then
  read -p "Drop all existing DBs ? (except system ones) (values: yes/no) " DROP_DBS
  export DROP_DBS="${DROP_DBS}"
fi

get_container_name "${CONTAINER_SHORT}"
CONTAINER="${func_result}"
if [[ "${CONTAINER}" != "" ]]; then
  echo_prom_helper "Restoring: $FILE_ZIP"
  export MYSQL_ROOT_PASSWORD=$(docker exec -i "${CONTAINER}" bash -c 'echo $MYSQL_ROOT_PASSWORD')

  download_file "${FILE_ZIP}" "./restore/backup.zip"
  mkdir -p ./restore && cd ./restore && unzip -qq backup.zip && rm backup.zip

  if [[ "${DROP_DBS}" == "yes" ]]; then
    export DATABASE_LIST=$(echo 'show databases;' | docker exec -i "${CONTAINER}" bash -c "mysql -u root -p'${MYSQL_ROOT_PASSWORD}'" | grep -Fv -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys' )
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_LIST;
    do
      echo_prom_helper "Dropping database ${DATABASE_ITEM}"
      docker exec -i "${CONTAINER}" mysql -u root -p$MYSQL_ROOT_PASSWORD -e "drop database \`${DATABASE_ITEM}\`;"
    done
  fi

  cd ../
  for BACKUP_FILE in ./restore/*
  do
    echo_prom_helper "Importing $BACKUP_FILE SQL file"
    docker exec -i "${CONTAINER}" mysql -u root -p$MYSQL_ROOT_PASSWORD < "${BACKUP_FILE}"
  done
  rm -R "./restore"
fi


