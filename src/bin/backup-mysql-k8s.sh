#!/bin/bash
set -euo pipefail
source functions.inc.sh

# failure trap
trap '/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status instance=backup-mysql-k8s overall=0 0' ERR

# enable tracing if you like:
# PS4='+[$LINENO] ' && set -x

# load list of logical backup targets
POD_SHORT_LIST=$(yq e '.config.backups.dbs_mysql.[].name' "${CONFIG_FILE_DIR}")
IFS=$'\n'
for POD_SHORT in $POD_SHORT_LIST; do
  echo_message "Backing up ${POD_SHORT}"

  # read namespace from config
  POD_NAMESPACE=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].namespace" "${CONFIG_FILE_DIR}")

  # resolve the Kubernetes DNS name for the pod service
  # assumes a headless service named exactly as the StatefulSet/Deployment
  DB_HOST="${POD_SHORT}.${POD_NAMESPACE}.svc.cluster.local"
  DB_PORT=3306

  # credentials
  SQL_USER=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].username" "${CONFIG_FILE_DIR}")
  [[ "$SQL_USER" == "null" ]] && SQL_USER="root"

  SQL_PASS=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].password" "${CONFIG_FILE_DIR}")
  if [[ "$SQL_PASS" == "null" ]]; then
    echo_message "ERROR: no password configured for ${POD_SHORT}"
    exit 1
  fi

  # local staging
  SERVER_DIR="/tmp/${POD_SHORT}"
  mkdir -p "${SERVER_DIR}" && find "${SERVER_DIR}" -mindepth 1 -delete

  DATE=$(date +"%Y-%m-%dT%H-%M-%SZ")
  DUMP_FILE="${POD_SHORT}-${DATE}.sql"
  DUMP_PATH="${SERVER_DIR}/${DUMP_FILE}"

  # list databases, filter out system schemas
  DATABASE_ITEMS=$(
    mysql \
      -h "${DB_HOST}" -P "${DB_PORT}" \
      -u "${SQL_USER}" -p"${SQL_PASS}" \
      -e "SHOW DATABASES;" 2>&1 \
    | grep -Ev '^(Database|information_schema|mysql|performance_schema|sys)$'
  )

  # if no user DBs, skip
  if [[ -z "${DATABASE_ITEMS// }" ]]; then
    echo_message "No user databases found on ${DB_HOST}; skipping."
    /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status instance=backup-mysql-k8s pod="${POD_SHORT}" 1
    continue
  fi

  echo_message "Found DBs: ${DATABASE_ITEMS}"

  # perform the dump
  mysqldump \
    -h "${DB_HOST}" -P "${DB_PORT}" \
    -u "${SQL_USER}" -p"${SQL_PASS}" \
    --single-transaction --extended-insert \
    --databases ${DATABASE_ITEMS} \
    > "${DUMP_PATH}"

  # zip it (encrypted if requested)
  ZIP_FILE="${DUMP_PATH}.zip"
  ENCRYPT=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].encrypt" "${CONFIG_FILE_DIR}")
  if [[ "${ENCRYPT}" == "true" ]]; then
    zip -qq --password "${SQL_PASS}" "${ZIP_FILE}" "${DUMP_PATH}"
  else
    zip -qq "${ZIP_FILE}" "${DUMP_PATH}"
  fi
  rm "${DUMP_PATH}"

  # upload and clean up
  upload_file "${ZIP_FILE}" "backup-mysql/${POD_SHORT}/$(basename "${ZIP_FILE}")"
  rm "${ZIP_FILE}"

  # success metric
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status instance=backup-mysql-k8s pod="${POD_SHORT}" 1
done
