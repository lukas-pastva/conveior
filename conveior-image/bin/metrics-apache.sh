#!/bin/bash
source functions.inc.sh


export IFS=","
for CONTAINER in ${CONTAINERS_WEB_SERVER}; do
  log_msg "Running apache logs monitor inside ${CONTAINER}"
  CODES=$(docker logs "${CONTAINER}" --since=5m | cut -d '"' -f3 | cut -d ' ' -f2 | sort | uniq -c | sort -rn)
  IFS=$'\n'
  for CODE_STR in $CODES;
  do
    export CODE=$(echo "${CODE_STR}" | awk -F" " '{print $1}')
    export COUNT=$(echo "${CODE_STR}" | awk -F" " '{print $2}')
    JSON="${JSON}{\"chart\":\"apacheCode\",\"name\":\"${CODE}\",\"value\":${COUNT}},"
  done

done

api_post_list "${JSON}"
