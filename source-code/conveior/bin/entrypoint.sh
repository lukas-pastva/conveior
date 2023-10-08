#!/bin/bash

echo '  ___ ___  _ ____   _____(_) ___  _ __| |_ _ __ ___  _ __ (_) ___   ___| | __'
echo ' / __/ _ \| '"'"'_ \ \ / / _ \ |/ _ \| '"'"'__| __| '"'"'__/ _ \| '"'"'_ \| |/ __| / __| |/ /'
echo '| (_| (_) | | | \ V /  __/ | (_) | |_ | |_| | | (_) | | | | | (__ _\__ \   < '
echo ' \___\___/|_| |_|\_/ \___|_|\___/|_(_) \__|_|  \___/|_| |_|_|\___(_)___/_|\_\'
echo ''

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
