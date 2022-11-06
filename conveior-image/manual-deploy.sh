#!/bin/bash

set -e

echo "This is to be used for manually deploying Agnet without a GitLab runner"

. .env

if [ -z "${BACKUP+xxx}" ]; then
  read -p "Please input BACKUP (example: web:/data,web-2:/var/www/html) " BACKUP
  export BACKUP="${BACKUP}"
fi

if [ -z "${CONTAINERS_MYSQL+xxx}" ]; then
  read -p "Please input CONTAINERS_MYSQL (example: mysql,mysql-2) " CONTAINERS_MYSQL
  export CONTAINERS_MYSQL="${CONTAINERS_MYSQL}"
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

docker-compose -f compose-deploy-manual.yaml down || true
docker-compose -f compose-deploy-manual.yaml build
docker-compose -f compose-deploy-manual.yaml up -d
