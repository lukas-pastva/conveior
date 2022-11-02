#!/bin/bash
source functions.inc.sh

CONTAINER_LIST=$(docker ps -f status=running --format "{{.Names}}")
export JSON=""
export IFS=","
for CONTAINER_MONITOR in ${CONTAINERS_MONITOR}; do

  export CONTAINER=$(echo ${CONTAINER_MONITOR} | awk -F ":" '{print $1}')
  export TYPE=$(echo ${CONTAINER_MONITOR} | awk -F ":" '{print $2}')

  export RUNNING=$(echo ${CONTAINER_LIST} | grep ${CONTAINER})
  if [[ "${RUNNING}" == *"${CONTAINER}"* ]]; then
    VALUE=1
  else
    if [ "$TYPE" == "info" ]; then
      VALUE=2
    else
      VALUE=3
    fi
  fi
  JSON="${JSON}{\"chart\":\"dockerContainer\",\"name\":\"${CONTAINER}\",\"value\":${VALUE}},"
done

api_post_list "${JSON}"
