#!/bin/bash
source functions.inc.sh
set -e

PODS=$(yq e '.config.backups.files.[].name' "${CONFIG_FILE_DIR}")
IFS=$'\n'
for POD_SHORT in $PODS; do
  echo_message "Backing up $POD_SHORT"

  POD_NAMESPACE=$(yq e ".config.backups.files | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].namespace" "${CONFIG_FILE_DIR}")
  POD_REGEX="^${POD_SHORT}(-[a-z0-9]{10}-[a-z0-9]{5})?|${POD_SHORT}-[0-9]+$"
  POD=$(kubectl -n "${POD_NAMESPACE}" get pods --no-headers -o custom-columns=":metadata.name" | grep -E "${POD_REGEX}" | head -n 1)
  POD_PATH=$(yq e ".config.backups.files | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].path" "${CONFIG_FILE_DIR}")

  SERVER_DIR="/tmp/${POD_SHORT}"
  ZIP_FILE_ONLY="${POD_SHORT}-${DATE}.zip"

  mkdir -p "${SERVER_DIR}" && find "${SERVER_DIR}" -mindepth 1 -delete

  if [[ $(kubectl -n "${POD_NAMESPACE}" exec -i "${POD}" -- sh -c "cd ${POD_PATH} && ls | wc -l") != "0" ]]; then
    kubectl -n "${POD_NAMESPACE}" cp "${POD}:${POD_PATH}" "${SERVER_DIR}" >/dev/null
    cd "${SERVER_DIR}"
    zip -rqq "${ZIP_FILE_ONLY}" "."

    upload_file "${SERVER_DIR}/${ZIP_FILE_ONLY}" "backup-file/${POD_SHORT}/${ZIP_FILE_ONLY}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  fi

  # <-- push success=1 metric
  /usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup-files-k8s pod=$POD_SHORT 1

done
