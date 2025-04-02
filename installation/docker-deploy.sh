#!/bin/bash

set -e
echo "Manually deploying Conveior into Docker."

. .env 2>/dev/null || true

export IMAGE="lukaspastva/conveior:latest"

docker stop conveior || true
docker container rm conveior || true
docker image rm ${IMAGE} || true
docker run --name conveior -d -v /var/run/docker.sock:/var/run/docker.sock  -v $(pwd)/:/home/ ${IMAGE} .