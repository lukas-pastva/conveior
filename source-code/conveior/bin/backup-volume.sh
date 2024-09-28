#!/bin/bash

set -e

# Source the existing functions and configuration
source functions.inc.sh

# Configuration variables
BACKUP_TEMP_DIR="/tmp/backup_volumes"
SPLIT_SIZE="5G"  # Size for split files

# Create a temporary directory for backups
mkdir -p "${BACKUP_TEMP_DIR}"
find "${BACKUP_TEMP_DIR}" -mindepth 1 -delete

# Extract volume configurations from the configuration file and iterate over them
yq e '.config.backups.volumes[] | "\(.name)\t\(.volumeName)"' "${CONFIG_FILE_DIR}" | while IFS=$'\t' read -r NAME VOLUME_NAME; do
    echo "Starting backup for volume: ${NAME} (Docker Volume: ${VOLUME_NAME})"

    # Define directories and files
    SERVER_DIR="${BACKUP_TEMP_DIR}/${NAME}"
    ZIP_FILE="${SERVER_DIR}/backup.zip"
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    # Check if the Docker volume exists
    if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
        echo "Docker volume '${VOLUME_NAME}' not found. Skipping backup for '${NAME}'."
        continue
    fi

    # Check disk space on the host (optional, adjust as needed)
    DATA_SIZE=$(docker run --rm -v "${VOLUME_NAME}":/data alpine sh -c "du -s /data | awk '{print \$1}'")
    DATA_SIZE_BYTES=$((DATA_SIZE * 1024))
    FREE_SIZE=$(df --output=avail "${BACKUP_TEMP_DIR}" | tail -1)
    if [ "${FREE_SIZE}" -lt "${DATA_SIZE_BYTES}" ]; then
        echo "Not enough free disk space. Required: ${DATA_SIZE_BYTES} KB, Available: ${FREE_SIZE} KB. Skipping backup for '${NAME}'."
        continue
    fi

    # Run the backup container to zip the Docker volume
    echo "Running backup container for volume '${NAME}'..."
    docker run --rm \
        -v "${VOLUME_NAME}":/data \
        -v "${SERVER_DIR}":/backup \
        alpine:latest \
        sh -c "apk add --no-cache zip && zip -r /backup/backup.zip /data"

    echo "Backup container completed for volume '${NAME}'."

    # Split the zip file into manageable chunks
    echo "Splitting the backup zip file for volume '${NAME}'..."
    split -a 3 -b "${SPLIT_SIZE}" "${ZIP_FILE}" "${ZIP_FILE}."

    echo "Backup zip file split into chunks for volume '${NAME}'."

    # Upload each split file
    echo "Uploading split backup files for volume '${NAME}'..."
    find "${SERVER_DIR}" -name "backup.zip.*" | while read -r SPLIT_FILE; do
        SPLIT_FILE_NAME=$(basename "${SPLIT_FILE}")
        upload_file "${SPLIT_FILE}" "backup-volumes/${ANTI_DATE}-${DATE}/${SPLIT_FILE_NAME}"
        echo "Uploaded '${SPLIT_FILE_NAME}' to backup storage."
        rm -f "${SPLIT_FILE}"
    done

    echo "All split files uploaded for volume '${NAME}'."

    # Clean up the server directory
    find "${SERVER_DIR}" -mindepth 1 -delete
    echo "Cleaned up temporary backup files for volume '${NAME}'."

done

# Final cleanup
rm -rf "${BACKUP_TEMP_DIR}"
echo "Volume backup process completed successfully."

exit 0
