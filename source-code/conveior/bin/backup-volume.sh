#!/bin/bash

set -e
source functions.inc.sh

# Configuration variables
BACKUP_TEMP_DIR="/tmp/backup_volumes"
SPLIT_SIZE="5G"

# Create a temporary directory for backups
mkdir -p "${BACKUP_TEMP_DIR}"
find "${BACKUP_TEMP_DIR}" -mindepth 1 -delete

VOLUMES_OUTPUT=$(yq -r '.config.backups.volumes[] | "\(.name)"' "${CONFIG_FILE_DIR}")
echo "${VOLUMES_OUTPUT}" | while read -r NAME; do

    echo "Starting backup for volume: ${NAME}"

    # Define directories and files
    SERVER_DIR="${BACKUP_TEMP_DIR}/${NAME}"
    BACKUP_FILE="${SERVER_DIR}/backup.tar"
    ZIP_FILE="${SERVER_DIR}/backup.zip"
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    # Check disk space on the host
    echo "Checking disk space..."

    DATA_SIZE_KB=$(docker run --rm -v "${NAME}":/data busybox sh -c "du -sk /data | awk '{print \$1}'")
    DATA_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", ${DATA_SIZE_KB}/1048576}")
    FREE_SIZE_KB=$(df --output=avail "${BACKUP_TEMP_DIR}" | tail -1 | tr -d ' ')
    FREE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", ${FREE_SIZE_KB}/1048576}")
    echo "Data size: ${DATA_SIZE_GB} GB"
    echo "Free size: ${FREE_SIZE_GB} GB"
    if [ "${FREE_SIZE_KB}" -lt "${DATA_SIZE_KB}" ]; then
        echo "Not enough free disk space. Required: ${DATA_SIZE_GB} GB, Available: ${FREE_SIZE_GB} GB. Skipping backup for '${NAME}'."
        continue
    fi
    echo "Sufficient disk space available."

    TEMP_CONTAINER_NAME="temp-container-${NAME//[^a-zA-Z0-9]/-}"

    echo "Creating temporary container '${TEMP_CONTAINER_NAME}' for volume '${NAME}'..."
    docker run --rm -d --name "${TEMP_CONTAINER_NAME}" -v "${NAME}":/source busybox sleep infinity

    echo "Creating tar archive inside container '${TEMP_CONTAINER_NAME}'..."
    docker exec "${TEMP_CONTAINER_NAME}" sh -c "tar cvf /backup.tar -C /source ." > "${SERVER_DIR}/backup_stdout.log" 2> "${SERVER_DIR}/backup_errors.log"

    echo "Copying 'backup.tar' from container '${TEMP_CONTAINER_NAME}' to host..."
    docker cp "${TEMP_CONTAINER_NAME}":/backup.tar "${BACKUP_FILE}" > /dev/null 2>> "${SERVER_DIR}/backup_errors.log"

    echo "Stopping and removing temporary container '${TEMP_CONTAINER_NAME}'..."
    docker stop "${TEMP_CONTAINER_NAME}" > /dev/null 2>> "${SERVER_DIR}/backup_errors.log"

    echo "Splitting the backup tar file for volume '${NAME}'..."
    split -a 3 -b "${SPLIT_SIZE}" "${BACKUP_FILE}" "${BACKUP_FILE}."

    echo "Uploading split backup files for volume '${NAME}'..."
    find "${SERVER_DIR}" -name "backup.tar.*" | while read -r SPLIT_FILE; do
        SPLIT_FILE_NAME=$(basename "${SPLIT_FILE}")
        echo "Uploading '${SPLIT_FILE_NAME}'..."
        upload_file "${SPLIT_FILE}" "backup-volumes/${NAME}/${ANTI_DATE}-${DATE}/${SPLIT_FILE_NAME}"
        echo "Uploaded '${SPLIT_FILE_NAME}' to backup storage."
        rm -f "${SPLIT_FILE}"
    done
    find "${SERVER_DIR}" -mindepth 1 -delete
done

rm -rf "${BACKUP_TEMP_DIR}"
echo "Volume backup process completed successfully."

exit 0
