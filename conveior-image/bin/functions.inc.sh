#!/bin/bash
set -e

export EPOCH=$(date +%s)
export DATE=$(date +"%Y-%m-%dT%H:%M:%SZ")

function echo_prom_helper {
  echo "# HELP $1"
}

function upload_file () {
  echo_prom_helper "Uploading ${BUCKET_NAME}/${2}"

  if [ "${BUCKET_TYPE}" == "S3" ]; then
#      get_upload_credentials
      upload_file_s3 $1 $2
  fi
  if [ "${BUCKET_TYPE}" == "GCP" ]; then
#      get_upload_credentials
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
  FILENAME="${1}"
  FILE_S3="${2}"
#  contentType="application/x-compressed-tar"
  contentType="application/x-zip-compressed"
  dateValue=`date -R`
  resource="/${BUCKET_NAME}/${FILE_S3}"
  stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
  signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${S3_SECRET} -binary | base64`
  curl -X PUT -T "${FILENAME}" -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${S3_KEY}:${signature}" "${S3_URL}/${BUCKET_NAME}/${FILE_S3}"
}

function api_get_json () {
  func_result=$(curl -sX GET "$1" -u "admin:${API_PASS}" )
}

function api_get_vault () {
  func_result=$(curl -s ${MYSQL_API_URL}/devopsvault/list -u "admin:${API_PASS}" | jq -r ".[] | select(.name==\"$1\") | .value")
}

function restore_files() {
#  get_upload_credentials
  export GCP_DIR=$1
  export DATE=$2
  export CONTAINER=$3
  export DESTINATION=$4

  # we need to find the directory with latest date
  if [ ${DATE} == "latest" ]; then
    export DATE_DIR=$(curl -s --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
        https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o \
        |  jq '.items' | jq '.[] | select(.size!="0")' | jq -r '.name' \
        | grep "$GCP_DIR/" | sort -r | head -1 | awk -F "/" '{print $(NF-1)}' || true )
  else
      DATE_DIR=$DATE
  fi

  # now we actually will download the files
  mkdir -p ./restore
  mkdir -p ./restore-unzipped
  export IFS=$'\n'
  curl -s --noproxy '*' \
        -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
        https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME/o \
        | jq '.items' | jq '.[] | select(.size!="0")' | jq -r '.name' \
        | grep "$GCP_DIR/" | while read LINE_GCP_FILE ; do
        if [[ "$LINE_GCP_FILE" == *"$GCP_DIR/$DATE_DIR"* ]]; then
          # actually download the file
          export FILENAME=$(echo $LINE_GCP_FILE | awk -F "/" '{print $NF}')
          curl --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
                "https://storage.googleapis.com/$BUCKET_NAME/$LINE_GCP_FILE" \
                -o ./restore/${FILENAME}
        fi
  done

  # all files are downloaded, if more, lets concat, if none, lets exit
  if [ $(ls ./restore | wc -l) -eq 0 ]; then
    echo_prom_helper "There are no files on GCP bucket"
    export restore_files="false"
  else
    if [ $(ls ./restore | wc -l) -ge 2 ]; then
      echo_prom_helper "Multiple files concatenating"
      cat ./restore/* > ./restore/restore.zip
    else
      mv ./restore/$(ls ./restore) ./restore/restore.zip
    fi
    # now unzip the file
    unzip ./restore/restore.zip -d ./restore-unzipped

    echo_prom_helper "Files fount:"
    ls -lart ./restore-unzipped/*

    if [  $(ls ./restore-unzipped | wc -l) -ge 1 ]; then
        echo_prom_helper "Copying files into $CONTAINER:$DESTINATION"
        docker cp ./restore-unzipped/. $CONTAINER:$DESTINATION
    else
      echo_prom_helper "Was not able to restore certificates"
      export restore_files="false"
    fi

    rm -R "./restore"
    rm -R "./restore-unzipped"
  fi

}

function generate_password() {
  export generate_password=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 20; echo;)
}

function send_slack_message() {
  echo_prom_helper "${MESSAGE}"
  curl -sX POST "${SLACK_HOOK}" -H "Content-Type: application/json" -d "{\"text\": \"${MESSAGE}\"}"
}

function get_container_name {
  CONTAINER_SHORT=$1
  # here I am getting shortest name of container, that is because containers han be in format "web, web-sql, web-sql-pma"
  CONTAINER=$(docker ps -f status=running --format "{{.Names}}" | grep -v _POD_ | grep "${CONTAINER_SHORT}" | awk '
                     NR==1 || length<len {len=length; line=$0}
                     END {print line}
                   ')
  if [[ "${CONTAINER}" == *"${CONTAINER_SHORT}"* ]]; then
    func_result="${CONTAINER}"
  else
    func_result=""
  fi
}