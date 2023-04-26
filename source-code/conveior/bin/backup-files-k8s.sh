#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.conveior-config.backups.files.[].name' /home/conveior-config.yaml)
export IFS=$'\n'
for POD_SHORT in $PODS;
do
  echo_message "Backing up $ITEM"

  export POD_NAMESPACE=$(yq e ".conveior-config.backups.files | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].namespace" /home/conveior-config.yaml)
  export POD=$(eval "kubectl -n ${POD_NAMESPACE} get pods --no-headers -o custom-columns=\":metadata.name\" | grep ${POD_SHORT}")
  export POD_PATH=$(yq e ".conveior-config.backups.files | with_entries(select(.value.name == \"$POD_SHORT\")) | .[].path" /home/conveior-config.yaml)

  export SERVER_DIR="/tmp/${POD_SHORT}"
  export ZIP_FILE_ONLY="${POD_SHORT}-${DATE}.zip"
  export ZIP_FILE="${SERVER_DIR}/${ZIP_FILE_ONLY}"

  mkdir -p "${SERVER_DIR}"
  find "${SERVER_DIR}" -mindepth 1 -delete

  if [[ $(eval "kubectl -n ${POD_NAMESPACE} exec -i ${POD} -- bash -c \"cd ${POD_PATH} && ls | wc -l\"") != "0" ]]; then
    eval "kubectl -n ${POD_NAMESPACE} cp ${POD}:${POD_PATH} ${SERVER_DIR}"
    cd "${SERVER_DIR}" && zip -rqq "${ZIP_FILE}" "."

    upload_file "${ZIP_FILE}" "backup-file/${POD_SHORT}/${ZIP_FILE_ONLY}"
    find "${SERVER_DIR}" -mindepth 1 -delete
  fi

done
