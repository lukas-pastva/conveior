#!/bin/bash
# source common functions
source functions.inc.sh

# fail on anything unexpected, undefined vars, and enable pipefail
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# DEBUG: turn on command tracing with timestamps
PS4='+$(date -u "+%Y-%m-%dT%H:%M:%SZ") # [TRACE] '
set -x
# trap to push failure metric
trap '/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status instance=backup-mysql-k8s overall=0 0' ERR
# ─────────────────────────────────────────────────────────────────────────────

# show PATH and verify kubectl again
echo_message "DEBUG: PATH=$PATH"
if command -v kubectl &>/dev/null; then
  echo_message "DEBUG: kubectl at $(command -v kubectl)"
  kubectl version --client || true
else
  echo_message "DEBUG: kubectl NOT found"
fi

# get list of pods to back up from config
POD_SHORT_LIST=$(yq e '.config.backups.dbs_mysql.[].name' "${CONFIG_FILE_DIR}")
echo_message "DEBUG: POD_SHORT_LIST=${POD_SHORT_LIST}"
IFS=$'\n'
for POD_SHORT in $POD_SHORT_LIST; do
  echo_message "Backing up ${POD_SHORT}"

  # find namespace & pod name
  POD_NAMESPACE=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].namespace" "${CONFIG_FILE_DIR}")
  echo_message "DEBUG: POD_NAMESPACE=${POD_NAMESPACE}"

  POD_REGEX="^${POD_SHORT}-([a-z0-9]+-[a-z0-9]+|[0-9]+)$"
  echo_message "DEBUG: POD_REGEX=${POD_REGEX}"

  POD_LIST=$(kubectl -n "${POD_NAMESPACE}" get pods --no-headers -o custom-columns=":metadata.name" | grep -E "${POD_REGEX}" || true)
  echo_message "DEBUG: POD_LIST=${POD_LIST}"

  for POD in $POD_LIST; do
    echo_message "DEBUG: selected POD=${POD}"
    SERVER_DIR="/tmp/${POD_SHORT}"
    DATE=$(date +"%Y-%m-%dT%H-%M-%SZ")
    FILE="${POD_SHORT}-${DATE}.sql"
    echo_message "DEBUG: SERVER_DIR=${SERVER_DIR}, FILE=${FILE}"

    # grab credentials from config or pod
    SQL_USER=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].username" "${CONFIG_FILE_DIR}")
    [[ "$SQL_USER" == "null" ]] && SQL_USER="root"
    echo_message "DEBUG: SQL_USER=${SQL_USER}"

    SQL_PASS=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].password" "${CONFIG_FILE_DIR}")
    if [[ "$SQL_PASS" == "null" ]]; then
      echo_message "DEBUG: fetching MYSQL_ROOT_PASSWORD from pod"
      SQL_PASS=$(kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- sh -c 'echo "${MYSQL_ROOT_PASSWORD}"')
    fi
    echo_message "DEBUG: SQL_PASS=${SQL_PASS:+(non-empty)}"

    # prepare local directory
    mkdir -p "${SERVER_DIR}"
    find "${SERVER_DIR}" -mindepth 1 -delete
    echo_message "DEBUG: emptied ${SERVER_DIR}"

    # list databases
    echo_message "DEBUG: listing databases via kubectl exec"
    DATABASE_ITEMS=$(kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- sh -c "mysql -u'${SQL_USER}' -p'${SQL_PASS}' -e 'show databases;'" 2>&1)
    echo_message "DEBUG: raw DATABASE_ITEMS=\n${DATABASE_ITEMS}"

    # filter out system DBs
    DATABASES_STR=""
    while read -r DB; do
      case "$DB" in
        Database|information_schema|mysql|performance_schema|sys) continue ;;
        *) DATABASES_STR+="$DB " ;;
      esac
    done <<< "$DATABASE_ITEMS"
    echo_message "DEBUG: USER DB list=($DATABASES_STR)"

    if [[ -n "${DATABASES_STR// }" ]]; then
      echo_message "DEBUG: dumping databases"
      kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- sh -c \
        "mysqldump --user='${SQL_USER}' --password='${SQL_PASS}' --single-transaction --extended-insert --databases ${DATABASES_STR} > /tmp/${FILE}"
      echo_message "DEBUG: copied dump into pod /tmp/${FILE}"

      echo_message "DEBUG: copying SQL file locally"
      kubectl cp "${POD_NAMESPACE}/${POD}:/tmp/${FILE}" "${SERVER_DIR}/${FILE}"
      ls -l "${SERVER_DIR}"
      kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- sh -c "rm /tmp/${FILE}"

      ZIP="${SERVER_DIR}/${FILE}.zip"
      ENCRYPT=$(yq e ".config.backups.dbs_mysql | with_entries(select(.value.name==\"$POD_SHORT\")) | .[].encrypt" "${CONFIG_FILE_DIR}")
      if [[ "$ENCRYPT" == "true" ]]; then
        echo_message "DEBUG: encrypting zip"
        zip -qq --password "${SQL_PASS}" "$ZIP" "${SERVER_DIR}/${FILE}"
      else
        echo_message "DEBUG: zipping without password"
        zip -qq "$ZIP" "${SERVER_DIR}/${FILE}"
      fi
      ls -l "${SERVER_DIR}"
      rm "${SERVER_DIR}/${FILE}"

      echo_message "DEBUG: uploading zip"
      upload_file "$ZIP" "backup-mysql/${POD_SHORT}/$(basename "$ZIP")"
      rm "$ZIP"
    else
      echo_message "DEBUG: no user DBs to dump, skipping"
    fi
  done

  echo_message "DEBUG: sending success metric for $POD_SHORT"
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status instance=backup-mysql-k8s pod="${POD_SHORT}" 1
done
