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

# Verify that CONFIG_FILE_DIR points to a file, not a directory
if [ -d "${CONFIG_FILE_DIR}" ]; then
    echo "Error: CONFIG_FILE_DIR points to a directory. It should point to the YAML configuration file."
    exit 1
fi

if [ ! -f "${CONFIG_FILE_DIR}" ]; then
    echo "Error: Configuration file '${CONFIG_FILE_DIR}' does not exist."
    exit 1
fi

echo "Using configuration file: ${CONFIG_FILE_DIR}"

# Extract volume configurations from the configuration file and iterate over them
VOLUMES_OUTPUT=$(yq -r '.config.backups.volumes[] | "\(.name)|\(.volumeName)"' "${CONFIG_FILE_DIR}")

# Iterate over each volume
echo "${VOLUMES_OUTPUT}" | while IFS='|' read -r NAME VOLUME_NAME; do

    # Validate that both NAME and VOLUME_NAME are not empty
    if [ -z "${NAME}" ] || [ -z "${VOLUME_NAME}" ]; then
        echo "Error: Either NAME or VOLUME_NAME is empty. Skipping this entry."
        continue
    fi

    echo "Starting backup for volume: ${NAME} (Docker Volume: ${VOLUME_NAME})"

    # Define directories and files
    SERVER_DIR="${BACKUP_TEMP_DIR}/${NAME}"
    ZIP_FILE="${SERVER_DIR}/backup.zip"
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete

    # Check disk space on the host (optional, adjust as needed)
    echo "Checking disk space..."
    DATA_SIZE=$(docker run --rm -v "${VOLUME_NAME}":/data alpine sh -c "du -s /data | awk '{print \$1}'")
    DATA_SIZE_BYTES=$((DATA_SIZE * 1024))
    FREE_SIZE=$(df --output=avail "${BACKUP_TEMP_DIR}" | tail -1)
    echo "Data size: ${DATA_SIZE} blocks (${DATA_SIZE_BYTES} KB)"
    echo "Free size: ${FREE_SIZE} KB"
    if [ "${FREE_SIZE}" -lt "${DATA_SIZE_BYTES}" ]; then
        echo "Not enough free disk space. Required: ${DATA_SIZE_BYTES} KB, Available: ${FREE_SIZE} KB. Skipping backup for '${NAME}'."
        continue
    fi
    echo "Sufficient disk space available."

    # Run the backup container to zip the Docker volume
    echo "Running backup container for volume '${NAME}'..."

    # Temporarily disable 'set -e' to allow zip to fail without exiting the script
    set +e

    docker run --rm \
        -u 0 \
        -v "${VOLUME_NAME}":/data:ro \
        -v "${SERVER_DIR}":/backup \
        alpine:latest \
        sh -c "apk add --no-cache zip && zip -r /backup/backup.zip /data" \
        2> "${SERVER_DIR}/backup_errors.log"

    ZIP_EXIT_CODE=$?

    # Re-enable 'set -e'
    set -e

    if [ ${ZIP_EXIT_CODE} -ne 0 ]; then
        echo "Warnings encountered during zipping for volume '${NAME}'. Check '${SERVER_DIR}/backup_errors.log' for details."
        # Optionally, you can process the log file here or notify
    else
        echo "Backup container completed successfully for volume '${NAME}'."
    fi

    # Split the zip file into manageable chunks
    echo "Splitting the backup zip file for volume '${NAME}'..."
    split -a 3 -b "${SPLIT_SIZE}" "${ZIP_FILE}" "${ZIP_FILE}."

    echo "Backup zip file split into chunks for volume '${NAME}'."

    # Upload each split file
    echo "Uploading split backup files for volume '${NAME}'..."
    find "${SERVER_DIR}" -name "backup.zip.*" | while read -r SPLIT_FILE; do
        SPLIT_FILE_NAME=$(basename "${SPLIT_FILE}")
        echo "Uploading '${SPLIT_FILE_NAME}'..."
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

set +x  # Stop tracing

exit 0
