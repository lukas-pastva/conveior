#!/bin/bash
#set -e

function echo_message {
  echo -e "\n$(date -u +"%Y-%m-%dT%H:%M:%SZ") # $1"
}

function download_file {
  echo_message "Downloading ${1} into ${2}"

  if [ "${BUCKET_TYPE}" == "S3" ]; then
      download_file_s3 "$1" "$2"
  fi
  if [ "${BUCKET_TYPE}" == "GCP" ]; then
      download_file_gcp "$1" "$2"
  fi
}

function download_file_s3 {
  FILE_S3="${1}"
  FILENAME="${2}"
  contentType="application/x-zip-compressed"
  dateValue=`date -R`
  resource="/${BUCKET_NAME}/${FILE_S3}"
  stringToSign="GET\n\n${contentType}\n${dateValue}\n${resource}"
  signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${S3_SECRET} -binary | base64`
  curl -s -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${S3_KEY}:${signature}" "${S3_URL}/${BUCKET_NAME}/${FILE_S3}" -o "${FILENAME}"
}

function download_file_gcp {
  curl -s --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" "https://storage.googleapis.com/${1}" -o "${2}"
}

function upload_file () {
  echo_message "Uploading ${BUCKET_NAME}/${2}"

  if [ "${BUCKET_TYPE}" == "S3" ]; then
      upload_file_s3_v2 $1 $2
  fi
  if [ "${BUCKET_TYPE}" == "S3_V4" ]; then
      upload_file_s3_v4 $1 $2
  fi
  if [ "${BUCKET_TYPE}" == "S3_FS" ]; then
      upload_file_s3_fs $1 $2
  fi
  if [ "${BUCKET_TYPE}" == "S3_RCLONE" ]; then
      upload_file_s3_rclone $1 $2
  fi
  if [ "${BUCKET_TYPE}" == "GCP" ]; then
      upload_file_gcp $1 $2
  fi
}
function upload_file_gcp () {
    FILE_SIZE=$(ls -nl $1 | awk '{print $5}')

    curl -sX POST -T $1 \
      -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
      -H "Content-Type: application/x-gzip-compressed" \
      -H "Content-Length: ${FILE_SIZE}" \
      "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET_NAME/o?uploadType=media&name=$2" > /dev/null
}

function upload_file_s3_v2 () {
  ZIP_FILE="${1}"
  FILE_S3="${2}"
#  contentType="application/x-compressed-tar"
  contentType="application/x-zip-compressed"
  dateValue=$(date -R)
  resource="/${BUCKET_NAME}/${FILE_S3}"
  signature=$(echo -en "PUT

${contentType}
${dateValue}
${resource}" | openssl sha1 -hmac ${S3_SECRET} -binary | base64)

  curl -sX PUT -T "${ZIP_FILE}" -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${S3_KEY}:${signature}" "${S3_URL}${resource}"
}

upload_file_s3_fs () {
    local ZIP_FILE="${1}"
    local FILE_S3="${2}"
    mkdir -p "/tmp/s3/${FILE_S3%/*}"
    cp "${ZIP_FILE}" "/tmp/s3/${FILE_S3}"
}

upload_file_s3_rclone () {
    local ZIP_FILE="${1}"
    local FILE_S3="${2}"
    rclone copy "${ZIP_FILE}" "s3:${BUCKET_NAME}/${FILE_S3%/*}"
}

upload_file_s3_v4 () {
  local ZIP_FILE="${1}"
  local FILE_S3="${2}"
  local contentType="application/x-zip-compressed"
  local dateValue
  dateValue=$(date -u +'%Y%m%dT%H%M%SZ') || { echo "Error: Unable to get date." >&2; return 1; }
  local region="auto"
  local service="s3"

  #  echo "Debug: ZIP_FILE: $ZIP_FILE"
  #  echo "Debug: FILE_S3: $FILE_S3"
  #  echo "Debug: contentType: $contentType"
  #  echo "Debug: dateValue: $dateValue"
  #  echo "Debug: region: $region"
  #  echo "Debug: service: $service"

  # Calculate content SHA256
  local contentSha256
  contentSha256=$(openssl dgst -sha256 -hex < "${ZIP_FILE}" | cut -d ' ' -f 2)
  echo "Debug: contentSha256: $contentSha256"

  # Create a string to sign
  local stringToSign
  stringToSign=$(cat <<EOF
AWS4-HMAC-SHA256
${dateValue}
${dateValue:0:8}/${region}/${service}/aws4_request
$(echo -n "PUT\n/${BUCKET_NAME}/${FILE_S3}\n\ncontent-type:${contentType}\nhost:${S3_URL#https://}\n\ncontent-type;host\n${contentSha256}")
EOF
)
  echo "Debug: stringToSign:"
  echo "$stringToSign"

  # Calculate the signing key
  local kDate=$(printf "%s" "${dateValue:0:8}" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${S3_SECRET}" | cut -d ' ' -f 2)
  local kRegion=$(printf "%s" "${region}" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kDate}" | cut -d ' ' -f 2)
  local kService=$(printf "%s" "${service}" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kRegion}" | cut -d ' ' -f 2)
  local kSigning=$(printf "aws4_request" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kService}" | cut -d ' ' -f 2)

  #  echo "Debug: kDate: $kDate"
  #  echo "Debug: kRegion: $kRegion"
  #  echo "Debug: kService: $kService"
  #  echo "Debug: kSigning: $kSigning"

  # Calculate the signature
  local signature
  signature=$(printf "%s" "${stringToSign}" | openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kSigning}" | cut -d ' ' -f 2)
  echo "Debug: Calculated Signature: $signature"

  echo "Uploading into ${S3_URL}/${BUCKET_NAME}/${FILE_S3}"
  #
  #  # Debug: Print the curl command
  #  echo "Debug: Curl Command:"
  #  echo "curl -i -X PUT -T \"${ZIP_FILE}\" \
  #    -H \"Content-Type: ${contentType}\" \
  #    -H \"Host: ${S3_URL#https://}\" \
  #    -H \"X-Amz-Date: ${dateValue}\" \
  #    -H \"X-Amz-Content-SHA256: ${contentSha256}\" \
  #    -H \"Authorization: AWS4-HMAC-SHA256 Credential=${S3_KEY}/${dateValue:0:8}/${region}/${service}/aws4_request,SignedHeaders=content-type;host;x-amz-date;x-amz-content-sha256,Signature=${signature}\" \
  #    \"${S3_URL}/${BUCKET_NAME}/${FILE_S3}\""

  # Make the PUT request
  curl -i -X PUT -T "${ZIP_FILE}" \
    -H "Content-Type: ${contentType}" \
    -H "Host: ${S3_URL#https://}" \
    -H "X-Amz-Date: ${dateValue}" \
    -H "X-Amz-Content-SHA256: ${contentSha256}" \
    -H "Authorization: AWS4-HMAC-SHA256 Credential=${S3_KEY}/${dateValue:0:8}/${region}/${service}/aws4_request,SignedHeaders=content-type;host;x-amz-date;x-amz-content-sha256,Signature=${signature}" \
    "${S3_URL}/${BUCKET_NAME}/${FILE_S3}" || { echo "Error: Unable to upload file." >&2; return 1; }
}


# init
if [[ -z ${CONFIG_FILE_DIR} ]]; then
  export CONFIG_FILE_DIR="/home/config.yaml"
fi
export EPOCH=$(date +%s)
export DATE=$(date +"%Y-%m-%dT%H-%M-%SZ")
export ANTI_DATE=$(( 10000000000 - $(date +%s) ))
export BUCKET_TYPE=$(yq e '.config.bucket_type' ${CONFIG_FILE_DIR})
export BUCKET_NAME=$(yq e '.config.bucket_name' ${CONFIG_FILE_DIR})
export S3_URL=$(yq e '.config.s3_url' ${CONFIG_FILE_DIR}) || true
export S3_KEY=$(yq e '.config.s3_key' ${CONFIG_FILE_DIR}) || true
export S3_SECRET=$(yq e '.config.s3_secret' ${CONFIG_FILE_DIR}) || true
export CONTAINER_ORCHESTRATOR=$(yq e '.config.container_orchestrator' ${CONFIG_FILE_DIR})

