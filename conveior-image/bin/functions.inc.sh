#!/bin/bash
set -e

export EPOCH=$(date +%s)
export DATE=$(date +"%Y-%m-%dT%H:%M:%SZ")
export INFLUX_API_FULL_URL="${INFLUX_API_URL}/measurements?name=dashboard-${CUSTOMER}"
if [ -n "${BRANCH}" ]; then
    export INFLUX_API_FULL_URL="${INFLUX_API_FULL_URL}-${BRANCH}"
fi

function echo_prom_helper {
  echo "# HELP $1"
}

function api_post_item () {
  curl -sX POST "${INFLUX_API_FULL_URL}" -H "Content-Type: application/json" -u "admin:${API_PASS}" -d "[{\"chart\": \"$1\",\"name\": \"$2\",\"value\": $3}]"
}

#function api_post_list () {
#  export JSON=$1
#  JSON=$(echo "${JSON}" | rev | cut -c2- | rev)
#  curl -sLX POST "${INFLUX_API_FULL_URL}" -u "admin:${API_PASS}" -H 'Content-Type: application/json' -d "[${JSON}]"
#}

#function get_upload_credentials () {
#  if [ "${BUCKET_TYPE}" == "GCP" ]; then
#      api_get_vault "REGISTRY_OAUTH2_ACCESS_TOKEN"
#      export OAUTH2_TOKEN=${func_result}
#  fi
#  if [ "${BUCKET_TYPE}" == "S3" ]; then
#      api_get_vault "S3_KEY"
#      export S3_KEY=${func_result}
#
#      api_get_vault "S3_SECRET"
#      export S3_SECRET=${func_result}
#
#      api_get_vault "S3_URL"
#      export S3_URL=${func_result}
#  fi
#}

function upload_file () {
  echo_prom_helper "Uploading ${BUCKET_NAME}-${2}/${3}"

  if [ "${BUCKET_TYPE}" == "S3" ]; then
#      get_upload_credentials
      upload_file_s3 $1 $2 $3
  fi
  if [ "${BUCKET_TYPE}" == "GCP" ]; then
#      get_upload_credentials
      upload_file_gcp $1 $2 $3
  fi
}

function upload_file_gcp () {
    FILE_SIZE=$(ls -nl $1 | awk '{print $5}')

    curl -sX POST -T $1 \
      -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
      -H "Content-Type: application/x-gzip-compressed" \
      -H "Content-Length: ${FILE_SIZE}" \
      "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET_NAME-$2/o?uploadType=media&name=$3" > /dev/null
}

function upload_file_s3 () {
  FILENAME="${1}"
  CUSTOMER_BRANCH="${2}"
  FILE_S3="${3}"
#  contentType="application/x-compressed-tar"
  contentType="application/x-zip-compressed"
  dateValue=`date -R`
  resource="/${BUCKET_NAME}-${CUSTOMER_BRANCH}/${FILE_S3}"
  stringToSign="PUT\n\n${contentType}\n${dateValue}\n${resource}"
  signature=`echo -en ${stringToSign} | openssl sha1 -hmac ${S3_SECRET} -binary | base64`
  curl -X PUT -T "${FILENAME}" -H "Date: ${dateValue}" -H "Content-Type: ${contentType}" -H "Authorization: AWS ${S3_KEY}:${signature}" "${S3_URL}/${BUCKET_NAME}-${CUSTOMER_BRANCH}/${FILE_S3}"
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
        https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME-$CUSTOMER-$BRANCH/o \
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
        https://storage.googleapis.com/storage/v1/b/$BUCKET_NAME-$CUSTOMER-$BRANCH/o \
        | jq '.items' | jq '.[] | select(.size!="0")' | jq -r '.name' \
        | grep "$GCP_DIR/" | while read LINE_GCP_FILE ; do
        if [[ "$LINE_GCP_FILE" == *"$GCP_DIR/$DATE_DIR"* ]]; then
          # actually download the file
          export FILENAME=$(echo $LINE_GCP_FILE | awk -F "/" '{print $NF}')
          curl --noproxy '*' -H "Authorization: Bearer ${OAUTH2_TOKEN}" \
                "https://storage.googleapis.com/$BUCKET_NAME-$CUSTOMER-$BRANCH/$LINE_GCP_FILE" \
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
  export CONTAINER=$(docker ps -f status=running --format "{{.Names}}" | grep -v _POD_ | grep "${CONTAINER_SHORT}")
  if [[ "${CONTAINER}" == *"${CONTAINER_SHORT}"* ]]; then
    func_result="${CONTAINER}"
  else
    func_result=""
  fi
}