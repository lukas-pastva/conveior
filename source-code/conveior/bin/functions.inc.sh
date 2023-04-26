#!/bin/bash
#set -e

function echo_message {
  echo -e "\n# $1"
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
  signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${CONVEIOR_S3_SECRET} -binary | base64`
  curl -s -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${CONVEIOR_S3_KEY}:${signature}" "${CONVEIOR_S3_URL}/${BUCKET_NAME}/${FILE_S3}" -o "${FILENAME}"
}

function download_file_gcp {
  curl -s --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" "https://storage.googleapis.com/${1}" -o "${2}"
}

function upload_file () {
  echo_message "Uploading ${BUCKET_NAME}/${2}"

  if [ "${BUCKET_TYPE}" == "S3" ]; then
      upload_file_s3 $1 $2
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

function upload_file_s3 () {
  ZIP_FILE="${1}"
  FILE_S3="${2}"
#  contentType="application/x-compressed-tar"
  contentType="application/x-zip-compressed"
  dateValue=$(date -R)
  resource="/${BUCKET_NAME}/${FILE_S3}"
  signature=$(echo -en "PUT

${contentType}
${dateValue}
${resource}" | openssl sha1 -hmac ${CONVEIOR_S3_SECRET} -binary | base64)

  curl -sX PUT -T "${ZIP_FILE}" -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${CONVEIOR_S3_KEY}:${signature}" "${CONVEIOR_S3_URL}${resource}"
}

export EPOCH=$(date +%s)
export DATE=$(date +"%Y-%m-%dT%H-%M-%SZ")
export BUCKET_TYPE=$(yq e '.conveior-config.bucket_type' /home/conveior-config.yaml)
export BUCKET_NAME=$(yq e '.conveior-config.bucket_name' /home/conveior-config.yaml)
export CONTAINER_ORCHESTRATOR=$(yq e '.conveior-config.container_orchestrator' /home/conveior-config.yaml)
