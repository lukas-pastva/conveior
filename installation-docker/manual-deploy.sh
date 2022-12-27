#!/bin/bash

set -e
echo "Manually deploying Conveior into Docker."

. .env 2>/dev/null || true

if [ -z "${S3_KEY+xxx}" ]; then
  read -p "Please input S3_KEY (example: *****) " S3_KEY
  export S3_KEY="${S3_KEY}"
fi

if [ -z "${S3_SECRET+xxx}" ]; then
  read -p "Please input S3_SECRET (example: *****) " S3_SECRET
  export S3_SECRET="${S3_SECRET}"
fi

if [ -z "${S3_URL+xxx}" ]; then
  read -p "Please input S3_URL (example: https://eu2.contabostorage.com) " S3_URL
  export S3_URL="${S3_URL}"
fi

export IMAGE="lukaspastva/conveior:latest"

docker stop conveior || true
docker container rm conveior || true
docker image rm ${IMAGE} || true
docker run --name conveior -e "CONVEIOR_S3_KEY=${S3_KEY}" -e "CONVEIOR_S3_SECRET=${S3_SECRET}" -e "CONVEIOR_S3_URL=${S3_URL}" -d -v /var/run/docker.sock:/var/run/docker.sock  -v $(pwd)/:/home/ ${IMAGE} .