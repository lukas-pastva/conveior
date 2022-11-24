#!/bin/bash

set -e
echo "Manually deploying Conveior into Docker."

. .env 2>/dev/null || true

if [ -z "${CONVEIOR_S3_KEY+xxx}" ]; then
  read -p "Please input CONVEIOR_S3_KEY (example: *****) " CONVEIOR_S3_KEY
  export CONVEIOR_S3_KEY="${CONVEIOR_S3_KEY}"
fi

if [ -z "${CONVEIOR_S3_SECRET+xxx}" ]; then
  read -p "Please input CONVEIOR_S3_SECRET (example: *****) " CONVEIOR_S3_SECRET
  export CONVEIOR_S3_SECRET="${CONVEIOR_S3_SECRET}"
fi

if [ -z "${CONVEIOR_S3_URL+xxx}" ]; then
  read -p "Please input CONVEIOR_S3_URL (example: https://eu2.contabostorage.com) " CONVEIOR_S3_URL
  export CONVEIOR_S3_URL="${CONVEIOR_S3_URL}"
fi

docker-compose -f compose-deploy.yaml up -d
