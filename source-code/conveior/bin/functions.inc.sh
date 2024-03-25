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
export BUCKET_TYPE=$(yq e '.config.bucket_type' ${CONFIG_FILE_DIR})
export BUCKET_NAME=$(yq e '.config.bucket_name' ${CONFIG_FILE_DIR})
export S3_URL=$(yq e '.config.s3_url' ${CONFIG_FILE_DIR}) || true
export S3_KEY=$(yq e '.config.s3_key' ${CONFIG_FILE_DIR}) || true
export S3_SECRET=$(yq e '.config.s3_secret' ${CONFIG_FILE_DIR}) || true
export CONTAINER_ORCHESTRATOR=$(yq e '.config.container_orchestrator' ${CONFIG_FILE_DIR})

# mount s3
mkdir -p /tmp/s3
echo ${S3_KEY}:${S3_SECRET} > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs
s3fs "${BUCKET_NAME}" /tmp/s3 -o allow_other -o use_path_request_style -o url=https://${S3_URL}
