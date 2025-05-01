#!/bin/bash

echo '  ___ ___  _ ____   _____(_) ___  _ __| |_ _ __ ___  _ __ (_) ___   ___| | __'
echo ' / __/ _ \| '\''_ \ \ / / _ \ |/ _ \| '\''__| __| '\''__/ _ \| '\''_\| |/ __| / __| |/ /'
echo '| (_| (_) | | | \ V /  __/ | (_) | |_ | |_| | | (_) | | | | | (__ _\__ \   < '
echo ' \___\___/|_| |_|\_/ \___|_|\___/|_(_) \__|_|  \___/|_| |_|_|\___(_)___/_|\_\' 
echo ''

# write the full config YAML into a file
if [ -n "${CONFIG_FILE_CONTENTS}" ]; then
  echo "${CONFIG_FILE_CONTENTS}" > /home/config.yaml
fi

# where to read it from
if [[ -z ${CONFIG_FILE_DIR} ]]; then
  export CONFIG_FILE_DIR="/home/config.yaml"
fi

# load S3 settings
S3_KEY=$(yq e '.config.s3_key'    ${CONFIG_FILE_DIR})
S3_SECRET=$(yq e '.config.s3_secret' ${CONFIG_FILE_DIR})
BUCKET_NAME=$(yq e '.config.bucket_name' ${CONFIG_FILE_DIR})
BUCKET_TYPE=$(yq e '.config.bucket_type' ${CONFIG_FILE_DIR})
S3_URL=$(yq e '.config.s3_url'       ${CONFIG_FILE_DIR})
# ensure https://
if [[ $S3_URL != https://* ]]; then
  S3_URL="https://${S3_URL}"
fi

# read the new toggle (defaults to "false" if missing)
USE_PATH_STYLE=$(yq e '.config.use_path_style // false' ${CONFIG_FILE_DIR})

# if using rclone, generate its config
if [ "${BUCKET_TYPE}" == "S3_RCLONE" ]; then

  # base rclone conf
  cat > /tmp/rclone.conf <<EOF
[s3]
type = s3
env_auth = false
provider = AWS
region = auto
access_key_id = ${S3_KEY}
secret_access_key = ${S3_SECRET}
endpoint = ${S3_URL}
EOF

  # append the toggle if requested
  if [ "${USE_PATH_STYLE}" = "true" ]; then
    echo "force_path_style = true" >> /tmp/rclone.conf
  fi
fi

# decide event-driven vs cron
if [ -z "${EVENT_DRIVEN+x}" ]; then
  GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
  if [ -z "$GW_URL" ]; then
    exec /usr/local/bin/conveior
  fi

  service cron start
  tail -f /var/log/cron.log
else
  echo "EVENT_DRIVEN defined—skipping cron/gateway startup."
fi
