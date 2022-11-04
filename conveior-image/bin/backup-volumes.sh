#!/bin/bash
source functions.inc.sh

export IFS=","
for VOLUME in ${BACKUP_VOLUMES}; do
  # only if volume exists
  if [[ $(docker volume ls | grep "${VOLUME}") != "" ]]; then
    
      echo_prom_helper "Backing up volume $VOLUME and starting Backupper to do the job"
      cp sys-backupper/template-docker-compose.yaml sys-backupper/${VOLUME}-docker-compose.yaml
      sed -i -e "s/{VOLUME}/${VOLUME}/g" sys-backupper/${VOLUME}-docker-compose.yaml
      docker-compose -f sys-backupper/${VOLUME}-docker-compose.yaml up --build -d
      sleep 5

      export ZIP_FILE="${VOLUME}-${DATE}.zip"
      if [[ $(docker exec -i sys-backupper-${VOLUME} bash -c "cd /tmp/${VOLUME} && ls | wc -l") != "0" ]]; then

          # echo_prom_helper "Zipping directory inside the container"
          docker exec -i sys-backupper-${VOLUME} bash -c "cd /tmp/${VOLUME} && zip -rqq ${ZIP_FILE} ."

          # echo_prom_helper "Copying directory outside and cleaning up"
          docker cp sys-backupper-${VOLUME}:/tmp/${VOLUME}/${ZIP_FILE} /tmp
          docker exec -i sys-backupper-${VOLUME} bash -c "rm /tmp/${VOLUME}/${ZIP_FILE}"

          upload_file "/tmp/${ZIP_FILE}" "${CUSTOMER}" "backup-volume/${DATE}/${ZIP_FILE}"

          echo_prom_helper "Cleaning up"
          rm "/tmp/${ZIP_FILE}"
          docker-compose -f sys-backupper/${VOLUME}-docker-compose.yaml down || true
          rm sys-backupper/${VOLUME}-docker-compose.yaml
      else
        echo_prom_helper "Empty volume ${VOLUME}, nothing to backup"
      fi

  fi
done