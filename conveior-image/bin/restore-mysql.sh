#!/bin/bash
source functions.inc.sh

if [ -z "${POD_SHORT+xxx}" ]; then
  read -p "Pod: " POD_SHORT
  export POD_SHORT=${POD_SHORT}
fi
if [ -z "${FILE_ZIP+xxx}" ]; then
  read -p "Location of the zip file to be downloaded (example: dir/file.zip): " FILE_ZIP
  export FILE_ZIP=${FILE_ZIP}
fi
if [ -z "${DROP_DBS+xxx}" ]; then
  read -p "Drop all existing DBs ? (except system ones) (values: yes/no): " DROP_DBS
  export DROP_DBS=${DROP_DBS}
fi

get_pod_name "${POD_SHORT}"
POD="${func_result}"
if [[ "${POD}" != "" ]]; then

  # perform backup, in case sth is horrifyingly wrong
  bash backup-mysql.sh "${POD}"

  mkdir -p /tmp/restore
  download_file "${FILE_ZIP}" "/tmp/restore/backup.zip"
  cd /tmp/restore && unzip -qq backup.zip && rm backup.zip

  MYSQL_ROOT_PASSWORD=$(docker exec -i "${POD}" bash -c 'echo $MYSQL_ROOT_PASSWORD' 2>/dev/null)

  if [[ "${DROP_DBS}" == "yes" ]]; then
    export DATABASE_LIST=$(echo 'show databases;' | docker exec -i "${POD}" bash -c "mysql -u root -p'${MYSQL_ROOT_PASSWORD}' 2>/dev/null" | grep -Fv -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys' )
    export IFS=$'\n'
    for DATABASE_ITEM in $DATABASE_LIST;
    do
      echo_prom_helper "Dropping database ${DATABASE_ITEM}"
      docker exec -i "${POD}" mysql -u root -p$MYSQL_ROOT_PASSWORD -e "drop database \`${DATABASE_ITEM}\`;" 2>/dev/null
    done
  fi

  for BACKUP_FILE in /tmp/restore/*
  do
    echo_prom_helper "Importing $BACKUP_FILE SQL file"
    docker exec -i "${POD}" mysql -u root -p$MYSQL_ROOT_PASSWORD < "${BACKUP_FILE}" 2>/dev/null
  done
  rm -R "/tmp/restore"
  echo_prom_helper "DONE"
fi