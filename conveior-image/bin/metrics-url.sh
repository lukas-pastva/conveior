#!/bin/bash
source functions.inc.sh

echo_prom_helper "Running URL monitor"

ENV_LIST=$(printenv | grep DOMAIN)
IFS=$'\n'
for ENV in $ENV_LIST;
do
  export NAME=$( echo ${ENV} | awk -F"=" '{print $1}')
  export VALUE=$( echo ${ENV} | awk -F"=" '{print $2}')
  if [[  ${VALUE} ]]; then
    echo_prom_helper "Testing URL: ${VALUE}"

    export STATUS=$(curl -is "https://${VALUE}" | awk 'NR==1{print $2}')
    if [[ -z ${STATUS} ]]; then
      STATUS="0"
    fi

    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"url\",\"name\":\"${VALUE}\",\"value\":${STATUS}},"
  fi

done

echo "${PROMETHEUS_DATA}"
