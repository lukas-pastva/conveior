#!/bin/bash

echo ""
echo " ██████  ██████  ███    ██ ██    ██ ███████ ██  ██████  ██████     ██  ██████"
echo "██      ██    ██ ████   ██ ██    ██ ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo "██      ██    ██ ██ ██  ██ ██    ██ █████   ██ ██    ██ ██████     ██ ██    ██"
echo "██      ██    ██ ██  ██ ██  ██  ██  ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo " ██████  ██████  ██   ████   ████   ███████ ██  ██████  ██   ██ ██ ██  ██████"
echo ""

if [ "${CONFIG_FILE_CONTENTS}" != "" ]; then
    echo "${CONFIG_FILE_CONTENTS}" > /home/config.yaml
else
  if [[ -z ${CONFIG_FILE_DIR} ]]; then
    export CONFIG_FILE_DIR="/home/config.yaml"
  fi
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

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  /usr/local/bin/conveior
fi

service cron start & tail -f /var/log/cron.log