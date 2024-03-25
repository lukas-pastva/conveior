#!/bin/bash
#set -e

function echo_message {
  echo -e "\n$(date -u +"%Y-%m-%dT%H:%M:%SZ") # $1"
}

function download_file {
  echo "# TODO this should be via s3fs"
}

# init
if [[ -z ${CONFIG_FILE_DIR} ]]; then
  export CONFIG_FILE_DIR="/home/config.yaml"
fi
export EPOCH=$(date +%s)
export DATE=$(date +"%Y-%m-%dT%H-%M-%SZ")
export ANTI_DATE=$(( 10000000000 - $(date +%s) ))
export BUCKET_NAME=$(yq e '.config.bucket_name' ${CONFIG_FILE_DIR})
export S3_URL=$(yq e '.config.s3_url' ${CONFIG_FILE_DIR}) || true
export S3_KEY=$(yq e '.config.s3_key' ${CONFIG_FILE_DIR}) || true
export S3_SECRET=$(yq e '.config.s3_secret' ${CONFIG_FILE_DIR}) || true
export CONTAINER_ORCHESTRATOR=$(yq e '.config.container_orchestrator' ${CONFIG_FILE_DIR})
