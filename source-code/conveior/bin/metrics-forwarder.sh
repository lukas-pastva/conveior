#!/bin/bash
source functions.inc.sh

while read CONTAINER;
do
  export PUSH_GW_URL=$(yq e ".config.forwarder | with_entries(select(.value.name == \"$CONTAINER\")) | .[].pushGw" ${CONFIG_FILE_DIR})
  export METRICS=$(curl -sk $CONTAINER)
  METRICS="${METRICS}
conveior_hwHeartbeat{container=\"$CONTAINER\"} $(date +%s)"

  echo -e "$METRICS" | curl --data-binary @- "${PUSH_GW_URL}"

done < <(yq e ".config.forwarder | .[].name" ${CONFIG_FILE_DIR})