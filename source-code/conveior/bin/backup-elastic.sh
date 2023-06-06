#!/bin/bash
source functions.inc.sh

set -e

export PODS=$(yq e '.conveior-config.backups.elasticsearch.[].name' /home/conveior-config.yaml)
export IFS=$','
for POD in $PODS;
do

  export ELASTIC_USER=$(yq e ".conveior-config.backups.elasticsearch | with_entries(select(.value.name == \"$POD\")) | .[].username" /home/conveior-config.yaml)
  export ELASTIC_PASSWD=$(yq e ".conveior-config.backups.elasticsearch | with_entries(select(.value.name == \"$POD\")) | .[].password" /home/conveior-config.yaml)

  export VOLUME="/tmp/backup/"
  export SERVER_DIR="/tmp/${POD}"
  export FILE="backup"
  export ZIP_FILE="${SERVER_DIR}/${FILE}.zip"
  export DATA_SIZE=$(docker exec -i ${POD} du -s "/usr/share/elasticsearch/data/" | awk '{print $1}')
  export FREE_SIZE=$(docker exec -i ${POD} df -T | awk 'NR==2' | awk '{print $5}')
  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  echo_message "Creating backup repository"
  docker exec ${POD} bash -c 'curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX PUT "127.0.0.1:9200/_snapshot/backup_repository?pretty" -H "Content-Type: application/json" -d"{\"type\":\"fs\",\"settings\":{\"location\":\"/tmp/backup\"}}"'

  echo_message "Deleting old backup"
  docker exec -i ${POD} bash -c "curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX GET 127.0.0.1:9200/_cat/snapshots/backup_repository | awk '{print \$1}' | while read SNAPSHOT ; do curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX DELETE 127.0.0.1:9200/_snapshot/backup_repository/\${SNAPSHOT}; done"
  find "${SERVER_DIR}" -mindepth 1 -delete
  sleep 30

  echo_message "Backing up elasticsearch $POD"
  DATA_SIZE=$(echo "$DATA_SIZE * 1.8" | bc)
  if [ $(echo "$FREE_SIZE > $DATA_SIZE" | bc) -eq 1 ]; then
    export EPOCH=$(date +%s)
    echo_message "EPOCH: $EPOCH"
    docker exec ${POD} bash -c "curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX PUT 127.0.0.1:9200/_snapshot/backup_repository/snapshot-${EPOCH}"
    for i in {1..1000}
    do
      export STATE=$(docker exec ${POD} bash -c "curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX GET 127.0.0.1:9200/_snapshot/backup_repository/snapshot-${EPOCH}/_status?pretty | grep SUCCESS")

      if [[ "${STATE}" == *"SUCCESS"* ]]; then
        break
      else
        echo -n "."
        sleep 10
      fi
    done

    echo_message "Zipping-deleting-copying-deleting-splitting-deleting-uploading-deleting backups"

    echo_message "zipping"
    docker exec -i ${POD} zip -rqq ${VOLUME}/${FILE} ${VOLUME}

    echo_message "deleting"
    docker exec -i ${POD} bash -c "curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX GET 127.0.0.1:9200/_cat/snapshots/backup_repository | awk '{print \$1}' | while read SNAPSHOT ; do curl --user '${ELASTIC_USER}':'${ELASTIC_PASSWD}' -sX DELETE 127.0.0.1:9200/_snapshot/backup_repository/\${SNAPSHOT}; done"
    sleep 30

    echo_message "copying"
    docker cp ${POD}:${VOLUME}${FILE}.zip ${SERVER_DIR}

    echo_message "deleting"
    docker exec -i ${POD} rm ${VOLUME}/${FILE}.zip

    echo_message "splitting"
    split -a 1 -b 4096M -d "${ZIP_FILE}" "${ZIP_FILE}."

    echo_message "deleting"
    rm "${ZIP_FILE}"

    find "${SERVER_DIR}" -mindepth 1 -maxdepth 1 | while read SPLIT_FILE;
    do
      export SPLIT_FILE_ONLY=$(echo "${SPLIT_FILE}" | awk -F"/" '{print $(NF)}')
      upload_file "${SERVER_DIR}/${SPLIT_FILE_ONLY}" "backup-elasticsearch/$(( 10000000000 - $(date +%s) ))-${DATE}/${SPLIT_FILE_ONLY}"
      rm "${SERVER_DIR}/${SPLIT_FILE_ONLY}"
    done

    echo_message "deleting the backup from elasticsearch"
    find "${SERVER_DIR}" -mindepth 1 -delete

  else
    echo_message "Not enough free disk space $FREE_SIZE < $DATA_SIZE * 1.8, not backing up"
  fi
done

# MIGRATION:
#if grep -Fq "path.repo:" "/usr/share/elasticsearch/config/elasticsearch.yml"; then  echo "config already set"; else   echo "setting config";  mkdir -p /tmp/backup;  chown elasticsearch:elasticsearch /tmp/backup;  echo "path.repo: [\"/tmp/backup\"]" >> /usr/share/elasticsearch/config/elasticsearch.yml;  fi

# curl -sX GET "127.0.0.1:9200/_snapshot?pretty"

# OPTIONAL:
#  docker exec -it ${POD} bash -c 'curl -sX GET "127.0.0.1:9200/_cat/repositories"'
#  docker exec -it ${POD} bash -c 'curl -sX GET "127.0.0.1:9200/_cat/indices"'
#  docker exec -it ${POD} bash -c 'curl -sX GET "127.0.0.1:9200/_cat/snapshots"'