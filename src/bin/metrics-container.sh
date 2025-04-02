#!/bin/bash
source functions.inc.sh

CONTAINER_LIST=$(docker ps -f status=running --format "{{.Names}}")
export METRICS=""
export IFS=","
while read POD;
do
  export TYPE=$(yq e ".config.metrics.containers | with_entries(select(.value.name == \"$POD\")) | .[].type" ${CONFIG_FILE_DIR})

  export RUNNING=$(echo ${CONTAINER_LIST} | grep ${POD})
  if [[ "${RUNNING}" == *"${POD}"* ]]; then
    VALUE=1
  else
    if [ "$TYPE" == "info" ]; then
      VALUE=2
    else
      VALUE=3
    fi
  fi
  METRIC="conveior_dockerContainer{label_name=\"${POD}\"} ${VALUE}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
done < <(yq e ".config.metrics.containers | .[].name" ${CONFIG_FILE_DIR})

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  echo -e "$METRICS"
else
  echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"
fi