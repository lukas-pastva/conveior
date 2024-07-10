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

    # Execute the command with correctly expanded variables
    export JSON_DATA=$(docker exec -i ${POD} curl -s --user "${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}" "http://127.0.0.1:9200/_cat/indices?format=json&bytes=b")

    for row in $(echo "${JSON_DATA}" | jq -c '.[]'); do
      health=$(echo "${row}" | jq -r '.health')
      status=$(echo "${row}" | jq -r '.status')
      index=$(echo "${row}" | jq -r '.index')
      uuid=$(echo "${row}" | jq -r '.uuid')
      pri=$(echo "${row}" | jq -r '.pri')
      rep=$(echo "${row}" | jq -r '.rep')
      docs_count=$(echo "${row}" | jq -r '.["docs.count"]')
      docs_deleted=$(echo "${row}" | jq -r '.["docs.deleted"]')
      store_size=$(echo "${row}" | jq -r '.["store.size"]')
      pri_store_size=$(echo "${row}" | jq -r '.["pri.store.size"]')

      labels="health=\"${health}\",status=\"${status}\",index=\"${index}\",uuid=\"${uuid}\",pri=\"${pri}\",rep=\"${rep}\",docs_count=\"${docs_count}\",docs_deleted=\"${docs_deleted}\",pri_store_size=\"${pri_store_size}\""
      METRICS=$(echo -e "$METRICS\nconveior_elasticsearch_indices_store_size{${labels}} ${store_size}")
    done
  fi
done

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  echo -e "$METRICS"
else
  echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"
fi