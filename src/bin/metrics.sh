#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

source functions.inc.sh

metrics-mysql.sh

metrics-forwarder.sh

if [[ "${CONTAINER_ORCHESTRATOR}" == "docker" ]]; then
  metrics-container.sh
  metrics-elasticsearch.sh
fi

ENABLE_HW_MONITORING=$(yq e ".config.enableHwMonitoring" ${CONFIG_FILE_DIR})
if [[ "${ENABLE_HW_MONITORING}" == "true" ]]; then
  metrics-hw.sh
fi
