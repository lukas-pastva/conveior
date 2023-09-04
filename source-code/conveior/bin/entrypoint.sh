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
fi

if [[ -z ${CONFIG_FILE_DIR} ]]; then
  export CONFIG_FILE_DIR="/home/config.yaml"
fi

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  /usr/local/bin/conveior
fi

service cron start & tail -f /var/log/cron.log
