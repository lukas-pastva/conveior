#!/bin/bash
source functions.inc.sh


export IFS=","
for CONTAINER in ${CONTAINERS_WEB_SERVER}; do
  echo_prom_helper "Running apache logs monitor inside ${CONTAINER}"
  CODES=$(docker logs "${CONTAINER}" --since=5m | cut -d '"' -f3 | cut -d ' ' -f2 | sort | uniq -c | sort -rn)
  IFS=$'\n'
  for CODE_STR in $CODES;
  do
    export CODE=$(echo "${CODE_STR}" | awk -F" " '{print $1}')
    export COUNT=$(echo "${CODE_STR}" | awk -F" " '{print $2}')
    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"apacheCode\",\"name\":\"${CODE}\",\"value\":${COUNT}},"
  done

done

echo "${PROMETHEUS_DATA}"
