#!/bin/bash

echo '  ___ ___  _ ____   _____(_) ___  _ __| |_ _ __ ___  _ __ (_) ___   ___| | __'
echo ' / __/ _ \| '"'"'_ \ \ / / _ \ |/ _ \| '"'"'__| __| '"'"'__/ _ \| '"'"'_ \| |/ __| / __| |/ /'
echo '| (_| (_) | | | \ V /  __/ | (_) | |_ | |_| | | (_) | | | | | (__ _\__ \   < '
echo ' \___\___/|_| |_|\_/ \___|_|\___/|_(_) \__|_|  \___/|_| |_|_|\___(_)___/_|\_\'
echo ''

# creating config file
if [ "${CONFIG_FILE_CONTENTS}" != "" ]; then
    echo "${CONFIG_FILE_CONTENTS}" > /home/config.yaml
fi

# setting config file directory
if [[ -z ${CONFIG_FILE_DIR} ]]; then
  export CONFIG_FILE_DIR="/home/config.yaml"
fi

# mount s3
S3_KEY=$(yq e '.config.s3_key' ${CONFIG_FILE_DIR})
S3_SECRET=$(yq e '.config.s3_secret' ${CONFIG_FILE_DIR})
BUCKET_NAME=$(yq e '.config.bucket_name' ${CONFIG_FILE_DIR})
BUCKET_TYPE=$(yq e '.config.bucket_type' ${CONFIG_FILE_DIR})
S3_URL=$(yq e '.config.s3_url' ${CONFIG_FILE_DIR})

if [ "${BUCKET_TYPE}" == "S3_FS" ]; then
  mkdir -p /tmp/s3
  echo ${S3_KEY}:${S3_SECRET} > /etc/passwd-s3fs
  chmod 600 /etc/passwd-s3fs
  s3fs "${BUCKET_NAME}" /tmp/s3 -o url=${S3_URL}
fi

if [ "${BUCKET_TYPE}" == "S3_RCLONE" ]; then

  config="[s3]
type = s3
env_auth = false
provider = AWS
region = auto
access_key_id = ${S3_KEY}
secret_access_key = ${S3_SECRET}
endpoint = ${S3_URL}
"

  # Write configuration to file
  config_file="$HOME/.config/rclone/rclone.conf"
  mkdir -p "$(dirname "$config_file")"
  echo "$config" > "$config_file"
fi

# if set gateway, then stating go app
GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  /usr/local/bin/conveior
fi

# else start cron
service cron start & tail -f /var/log/cron.log