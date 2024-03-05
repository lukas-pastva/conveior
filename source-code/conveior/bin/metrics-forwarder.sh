#!/bin/bash
source functions.inc.sh

while read CONTAINER; do
  PUSH_GW_URL=$(yq e ".config.forwarder | with_entries(select(.value.name == \"$CONTAINER\")) | .[].pushGw" ${CONFIG_FILE_DIR})

  TEMP_METRICS_FILE=$(mktemp)
  curl -sk "$CONTAINER" > "$TEMP_METRICS_FILE"
  echo "conveior_hwHeartbeat{container=\"$CONTAINER\"} $(date +%s)" >> "$TEMP_METRICS_FILE"
  curl --data-binary @"$TEMP_METRICS_FILE" "${PUSH_GW_URL}"
  rm "$TEMP_METRICS_FILE"

done < <(yq e ".config.forwarder | .[].name" ${CONFIG_FILE_DIR})
