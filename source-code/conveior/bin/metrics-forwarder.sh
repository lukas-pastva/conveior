#!/bin/bash
source functions.inc.sh

while read CONTAINER;
do
  export PUSH_GW_URL=$(yq e ".config.forwarder | with_entries(select(.value.name == \"$CONTAINER\")) | .[].pushGw" ${CONFIG_FILE_DIR})

  # export DATA=$(curl -ik CONTAINER)
  # METRIC="conveior_dockerContainer{label_name=\"${CONTAINER}\"} ${VALUE}"
  # METRICS=$(echo -e "$METRICS\n$METRIC")
  # echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"

done < <(yq e ".config.forwarder | .[].name" ${CONFIG_FILE_DIR})

