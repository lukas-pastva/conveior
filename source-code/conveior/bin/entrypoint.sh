#!/bin/bash

echo ""
echo " ██████  ██████  ███    ██ ██    ██ ███████ ██  ██████  ██████     ██  ██████"
echo "██      ██    ██ ████   ██ ██    ██ ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo "██      ██    ██ ██ ██  ██ ██    ██ █████   ██ ██    ██ ██████     ██ ██    ██"
echo "██      ██    ██ ██  ██ ██  ██  ██  ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo " ██████  ██████  ██   ████   ████   ███████ ██  ██████  ██   ██ ██ ██  ██████"
echo ""

# in case config is via variable
if [ "${CONVEIOR_CONFIG_FILE}" != "" ]; then
    echo "${CONVEIOR_CONFIG_FILE}" > /home/conveior-config.yaml
    export CONVEIOR_CONFIG_FILE=""
fi

GW_URL=$(yq e ".conveior-config.prometheus_pushgateway" /home/conveior-config.yaml)
if [ -z "$GW_URL" ]; then
  /usr/local/bin/conveior
fi

service cron start & tail -f /var/log/cron.log