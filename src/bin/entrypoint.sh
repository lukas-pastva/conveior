#!/bin/bash


# Write the inbound configuration YAML to file
if [ -n "${CONFIG_FILE_CONTENTS:-}" ]; then
    echo "${CONFIG_FILE_CONTENTS}" > /home/config.yaml
fi

# Ensure CONFIG_FILE_DIR is set
if [ -z "${CONFIG_FILE_DIR:-}" ]; then
    export CONFIG_FILE_DIR="/home/config.yaml"
fi

# Load S3 settings
S3_KEY=$(yq e '.config.s3_key'    "${CONFIG_FILE_DIR}")
S3_SECRET=$(yq e '.config.s3_secret' "${CONFIG_FILE_DIR}")
BUCKET_NAME=$(yq e '.config.bucket_name' "${CONFIG_FILE_DIR}")
BUCKET_TYPE=$(yq e '.config.bucket_type' "${CONFIG_FILE_DIR}")
S3_URL=$(yq e '.config.s3_url'       "${CONFIG_FILE_DIR}")
if [[ $S3_URL != https://* ]]; then
    S3_URL="https://${S3_URL}"
fi

# If using s3fs mount
if [ "${BUCKET_TYPE}" == "S3_FS" ]; then
    mkdir -p /tmp/s3
    echo "${S3_KEY}:${S3_SECRET}" > /etc/passwd-s3fs
    chmod 600 /etc/passwd-s3fs
    s3fs "${BUCKET_NAME}" /tmp/s3 -o url="${S3_URL}"
fi

# If using rclone for S3 uploads
if [ "${BUCKET_TYPE}" == "S3_RCLONE" ]; then
    # Read region (fallback to "auto")
    S3_REGION=$(yq e '.config.s3_region // "auto"' "${CONFIG_FILE_DIR}")

    # Generate rclone.conf
    cat > /tmp/rclone.conf <<EOF
[s3]
type = s3
env_auth = false
provider = AWS
region = ${S3_REGION}
access_key_id = ${S3_KEY}
secret_access_key = ${S3_SECRET}
endpoint = ${S3_URL}
EOF

    # Optionally force path-style addressing
    if [ "$(yq e '.config.use_path_style // false' "${CONFIG_FILE_DIR}")" == "true" ]; then
        echo "force_path_style = true" >> /tmp/rclone.conf
    fi
fi

# Decide between event-driven gateway and cron-based execution
if [ -z "${EVENT_DRIVEN+x}" ]; then
    GW_URL=$(yq e '.config.prometheus_pushgateway' "${CONFIG_FILE_DIR}")
    if [ -z "${GW_URL}" ]; then
        exec /usr/local/bin/conveior
    fi

    service cron start
    tail -f /var/log/cron.log
else
    echo "EVENT_DRIVEN defined. Scheduling and/or gateway push execution skipped."
fi
