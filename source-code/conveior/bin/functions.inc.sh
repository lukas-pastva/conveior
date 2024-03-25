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

upload_file_s3_v4 () {
  local ZIP_FILE="${1}"
  local FILE_S3="${2}"
  local contentType="application/x-zip-compressed"
  local dateValue
  dateValue=$(date -u +'%Y%m%dT%H%M%SZ') || { echo "Error: Unable to get date." >&2; return 1; }
  local region="auto"
  local service="s3"
  local awsKey="${S3_KEY}"
  local awsSecret="${S3_SECRET}"

  # Create a string to sign
  stringToSign=$(cat <<EOF
AWS4-HMAC-SHA256
${dateValue}
${dateValue:0:8}/${region}/${service}/aws4_request
$(echo -n -e "PUT\n/${BUCKET_NAME}/${FILE_S3}\n\ncontent-type:${contentType}\nhost:${S3_URL}\n\ncontent-type;host\n$(echo -n -e "${contentType}\n${dateValue}\nhost\n" | openssl sha256 -hex)\n$(echo -n -e "UNSIGNED-PAYLOAD" | openssl sha256 -hex)")
EOF
)

  # Calculate the signature
  local signature
  signature=$(printf "${stringToSign}" | openssl sha256 -hex -mac HMAC -macopt "hexkey:${awsSecret}" | sed 's/^.* //') || { echo "Error: Unable to calculate signature." >&2; return 1; }

  echo "Uploading into ${S3_URL}/${BUCKET_NAME}/${FILE_S3}"

  curl -v -X PUT -T "${ZIP_FILE}" \
    -H "Content-Type: ${contentType}" \
    -H "Host: ${S3_URL#https://}" \
    -H "X-Amz-Date: ${dateValue}" \
    -H "Authorization: AWS4-HMAC-SHA256 Credential=${awsKey}/${dateValue:0:8}/${region}/${service}/aws4_request,SignedHeaders=content-type;host;x-amz-date,Signature=${signature}" \
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