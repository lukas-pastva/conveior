#!/bin/bash
source functions.inc.sh

export VOLUME=$1
export FILENAME="${VOLUME}-restore.zip"
mkdir -p "./restore"
mkdir -p "./restore-unzipped"

echo_prom_helper "Downloading backup file $GCP_FILE"
get_upload_credentials
curl -s --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" "https://storage.googleapis.com/$GCP_FILE" -o "./restore/${FILENAME}"

echo_prom_helper "Unzipping file"
unzip -qq ./restore/${FILENAME} -d ./restore-unzipped
rm ./restore/${FILENAME}

echo_prom_helper "Starting backupper"
cp DevOps/sys-backupper/template-docker-compose.yaml DevOps/sys-backupper/${VOLUME}-docker-compose.yaml
sed -i -e "s/{VOLUME}/${VOLUME}/g" DevOps/sys-backupper/${VOLUME}-docker-compose.yaml
docker-compose -f DevOps/sys-backupper/${VOLUME}-docker-compose.yaml up --build -d
sleep 5


if [ -n "$CLEANUP" ]; then
  echo_prom_helper "Deleting files flag is set, so cleaning up volume directory"
  # docker exec -i sys-backupper-${VOLUME} bash -c "ls -la /tmp/${VOLUME}/*"
  docker exec -i sys-backupper-${VOLUME} bash -c "rm -R /tmp/${VOLUME}/*"
  # docker exec -i sys-backupper-${VOLUME} bash -c "ls -la /tmp/${VOLUME}/*"
fi

echo_prom_helper "Copying files into volume"
docker cp ./restore-unzipped/ sys-backupper-${VOLUME}:/tmp/${VOLUME}
docker exec -i sys-backupper-${VOLUME} bash -c "mv /tmp/${VOLUME}/restore-unzipped/* /tmp/${VOLUME}"
docker exec -i sys-backupper-${VOLUME} bash -c "rm -R /tmp/${VOLUME}/restore-unzipped/"

# killer feature of replacing!
if [ -n "$SEARCH" ]; then
  if [ -n "$REPLACE" ]; then
    echo_prom_helper "Replacing strings in all files SEARCH: $SEARCH, REPLACE: $REPLACE"
    docker exec -i sys-backupper-${VOLUME} bash -c "find /tmp/${VOLUME} -type f -exec sed -i \"s|$SEARCH|$REPLACE|g\" {} +"
  fi
fi

if [ -n "$SEARCH2" ]; then
  if [ -n "$REPLACE2" ]; then
    echo_prom_helper "Replacing strings in all files SEARCH: $SEARCH2, REPLACE: $REPLACE2"
#    docker exec -i sys-backupper-${VOLUME} bash -c "sed -i -e \"s|$SEARCH2|$REPLACE2|g\" /tmp/${VOLUME}/*"
    docker exec -i sys-backupper-${VOLUME} bash -c "find /tmp/${VOLUME} -type f -exec sed -i \"s|$SEARCH2|$REPLACE2|g\" {} +"
  fi
fi

if [ -n "$SEARCH3" ]; then
  if [ -n "$REPLACE3" ]; then
    echo_prom_helper "Replacing strings in all files SEARCH: $SEARCH3, REPLACE: $REPLACE3"
    docker exec -i sys-backupper-${VOLUME} bash -c "find /tmp/${VOLUME} -type f -exec sed -i \"s|$SEARCH3|$REPLACE3|g\" {} +"
  fi
fi

echo_prom_helper "Changing groups and owners to all files"
docker exec -i sys-backupper-${VOLUME} bash -c "chgrp -R www-data /tmp/${VOLUME}/*"
docker exec -i sys-backupper-${VOLUME} bash -c "chown -R www-data /tmp/${VOLUME}/*"


echo_prom_helper "Stopping backupper and cleaning up"
docker-compose -f DevOps/sys-backupper/${VOLUME}-docker-compose.yaml down
rm DevOps/sys-backupper/${VOLUME}-docker-compose.yaml

rm -R "./restore"
rm -R "./restore-unzipped"