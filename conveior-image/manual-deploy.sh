#!/bin/bash

set -e

echo "This is to be used for manually deploying Agnet without a GitLab runner"

. .env

if [ -z "${LOKI_URL+xxx}" ]; then
  read -p "Please input LOKI_URL  (example: loki.domain.com) " LOKI_URL
  export LOKI_URL="${LOKI_URL}"
fi

if [ -z "${INFLUX_API_URL+xxx}" ]; then
  read -p "Please input INFLUX_API_URL  (example: influx-api.domain.com/api/v1) " INFLUX_API_URL
  export INFLUX_API_URL="${INFLUX_API_URL}"
fi

if [ -z "${MYSQL_API_URL+xxx}" ]; then
  read -p "Please input MYSQL_API_URL  (example: mysql-api.domain.com/api/v1) " MYSQL_API_URL
  export MYSQL_API_URL="${MYSQL_API_URL}"
fi

if [ -z "${API_PASS+xxx}" ]; then
  read -p "Please input API_PASS (example: secret) " API_PASS
  export API_PASS="${API_PASS}"
fi

if [ -z "${BACKUP+xxx}" ]; then
  read -p "Please input BACKUP (example: web:/data,web-2:/var/www/html) " BACKUP
  export BACKUP="${BACKUP}"
fi

if [ -z "${BACKUP_CERTIFICATES+xxx}" ]; then
  read -p "Please input BACKUP_CERTIFICATES (example: web:/etc/letsencrypt,web-2:/etc/letsencrypt) " BACKUP_CERTIFICATES
  export BACKUP_CERTIFICATES="${BACKUP_CERTIFICATES}"
fi

if [ -z "${BACKUP_VOLUMES+xxx}" ]; then
  read -p "Please input BACKUP_VOLUMES (example: volume-name-1,volume-name-2) " BACKUP_VOLUMES
  export BACKUP_VOLUMES="${BACKUP_VOLUMES}"
fi

if [ -z "${BRANCH+xxx}" ]; then
  read -p "Please input BRANCH (example: main) " BRANCH
  export BRANCH="${BRANCH}"
fi

if [ -z "${CONTAINERS_WEB_SERVER+xxx}" ]; then
  read -p "Please input CONTAINERS_WEB_SERVER (example: web,web-2) " CONTAINERS_WEB_SERVER
  export CONTAINERS_WEB_SERVER="${CONTAINERS_WEB_SERVER}"
fi

if [ -z "${CONTAINERS_MONITOR+xxx}" ]; then
  read -p "Please input CONTAINERS_MONITOR (example: conveior:info,grafana:alert) " CONTAINERS_MONITOR
  export CONTAINERS_MONITOR="${CONTAINERS_MONITOR}"
fi

if [ -z "${CONTAINERS_MYSQL+xxx}" ]; then
  read -p "Please input CONTAINERS_MYSQL (example: mysql,mysql-2) " CONTAINERS_MYSQL
  export CONTAINERS_MYSQL="${CONTAINERS_MYSQL}"
fi

if [ -z "${CONTAINERS_PHP+xxx}" ]; then
  read -p "Please input CONTAINERS_PHP (example: web,web-2) " CONTAINERS_PHP
  export CONTAINERS_PHP="${CONTAINERS_PHP}"
fi

if [ -z "${CUSTOMER+xxx}" ]; then
  read -p "Please input CUSTOMER (example: google) " CUSTOMER
  export CUSTOMER="${CUSTOMER}"
fi

if [ -z "${DOMAINS+xxx}" ]; then
  read -p "Please input DOMAINS (example: https://domain.com,http://domain.net) " DOMAINS
  export DOMAINS="${DOMAINS}"
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

if [ -z "${SLACK_HOOK+xxx}" ]; then
  read -p "Please input SLACK_HOOK (example: https://slack.com/...) " SLACK_HOOK
  export SLACK_HOOK="${SLACK_HOOK}"
fi

docker-compose -f compose-deploy-manual.yaml down || true
docker-compose -f compose-deploy-manual.yaml build
docker-compose -f compose-deploy-manual.yaml up -d
