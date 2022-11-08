#!/bin/bash

set -e

echo "Manually deploying Conveior into Docker."

. .env || true 2>/dev/null

if [ -z "${BACKUP_FILES+xxx}" ]; then
  read -p "Please input BACKUP_FILES (example: web:/data,web-2:/var/www/html) " BACKUP_FILES
  export BACKUP_FILES="${BACKUP_FILES}"
fi

if [ -z "${PODS_MYSQL+xxx}" ]; then
  read -p "Please input PODS_MYSQL (example: mysql,mysql-2) " PODS_MYSQL
  export PODS_MYSQL="${PODS_MYSQL}"
fi

if [ -z "${BUCKET_TYPE+xxx}" ]; then
  read -p "Please input BUCKET_TYPE (example: S3, GCP) " BUCKET_TYPE
  export BUCKET_TYPE="${BUCKET_TYPE}"
fi

if [ -z "${BUCKET_NAME+xxx}" ]; then
  read -p "Please input BUCKET_NAME (example: tronic) " BUCKET_NAME
  export BUCKET_NAME="${BUCKET_NAME}"
fi

if [ -z "${S3_KEY+xxx}" ]; then
  read -p "Please input S3_KEY (example: *****) " S3_KEY
  export S3_KEY="${S3_KEY}"
fi

if [ -z "${S3_SECRET+xxx}" ]; then
  read -p "Please input S3_SECRET (example: *****) " S3_SECRET
  export S3_SECRET="${S3_SECRET}"
fi

if [ -z "${S3_URL+xxx}" ]; then
  read -p "Please input S3_URL (example: *****) " S3_URL
  export S3_URL="${S3_URL}"
fi

if [ -z "${CONVEIOR_CONFIG+xxx}" ]; then
  read -p "Please input CONVEIOR_CONFIG (example: yaml contents) " CONVEIOR_CONFIG
  export CONVEIOR_CONFIG="${CONVEIOR_CONFIG}"
fi

docker-compose -f compose-deploy.yaml up -d
