#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

source functions.inc.sh

metrics-mysql.sh

if [[ "${CONTAINER_ORCHESTRATOR}" == "docker" ]]; then
  metrics-container.sh
  metrics-elasticsearch.sh
fi

ENABLE_HW_MONITORING=$(yq e ".conveior-config.enableHwMonitoring" /home/conveior-config.yaml)
if [[ "${ENABLE_HW_MONITORING}" == "true" ]]; then
  metrics-hw.sh
fi

