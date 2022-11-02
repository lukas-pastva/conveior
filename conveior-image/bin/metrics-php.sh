#!/bin/bash
source functions.inc.sh

IFS=$','
for CONTAINER in $CONTAINERS_PHP;
do
  log_msg "Running PHP monitor ${CONTAINER}"

  export MEMORY_LIMIT=$(docker exec -i ${CONTAINER} bash -c "php -i | grep memory_limit" | awk '{print $5}' | numfmt --from=iec)
  JSON="{\"chart\":\"phpMemoryLimit\",\"name\":\"${CONTAINER}\",\"value\":${MEMORY_LIMIT}},"

  api_post_list "${JSON}"
done


