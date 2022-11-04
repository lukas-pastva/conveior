#!/bin/bash
source functions.inc.sh

IFS=$','
for CONTAINER in $CONTAINERS_PHP;
do
  echo_prom_helper "Running PHP monitor ${CONTAINER}"

  export MEMORY_LIMIT=$(docker exec -i ${CONTAINER} bash -c "php -i | grep memory_limit" | awk '{print $5}' | numfmt --from=iec)
  PROMETHEUS_DATA="{\"chart\":\"phpMemoryLimit\",\"name\":\"${CONTAINER}\",\"value\":${MEMORY_LIMIT}},"

  echo "${PROMETHEUS_DATA}"
done


