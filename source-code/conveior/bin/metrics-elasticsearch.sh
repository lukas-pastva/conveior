#!/bin/bash
source functions.inc.sh

export PODS=$(yq e '.config.metrics.elasticsearch.[].name' ${CONFIG_FILE_DIR})
export METRICS=""
export IFS=$'\n'
for POD in $PODS;
do
  if [[ "${POD}" != "" ]]; then
    export ELASTICSEARCH_USERNAME=$(yq e ".config.metrics.elasticsearch | with_entries(select(.value.name == \"$POD\")) | .[].username" ${CONFIG_FILE_DIR})
    export ELASTICSEARCH_PASSWORD=$(yq e ".config.metrics.elasticsearch | with_entries(select(.value.name == \"$POD\")) | .[].password" ${CONFIG_FILE_DIR})

    export DATA=$(docker exec -i ${POD} curl -s --user "${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" http://127.0.0.1:9200/_cat/indices)

    export GREEN=$( echo -e "$DATA" | grep "green" | wc -l)
    export YELLOW=$( echo -e "$DATA" | grep "yellow" | wc -l)
    export RED=$( echo -e "$DATA" | grep "red" | wc -l)

    METRIC="conveior_elasticsearch{label_name=\"green\"} ${GREEN}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
    METRIC="conveior_elasticsearch{label_name=\"yellow\"} ${YELLOW}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
    METRIC="conveior_elasticsearch{label_name=\"red\"} ${RED}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi
done

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  echo -e "$METRICS"
else
  echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"
fi