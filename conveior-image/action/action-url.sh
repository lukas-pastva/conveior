#!/bin/bash
source /action/action-functions.inc.sh

log_msg "Running URL monitor"

ENV_LIST=$(printenv | grep DOMAIN)
IFS=$'\n'
for ENV in $ENV_LIST;
do
  export NAME=$( echo ${ENV} | awk -F"=" '{print $1}')
  export VALUE=$( echo ${ENV} | awk -F"=" '{print $2}')
  if [[  ${VALUE} ]]; then
    log_msg "Testing URL: ${VALUE}"

    export STATUS=$(curl -is "https://${VALUE}" | awk 'NR==1{print $2}')
    if [[ -z ${STATUS} ]]; then
      STATUS="0"
    fi

    JSON="${JSON}{\"chart\":\"url\",\"name\":\"${VALUE}\",\"value\":${STATUS}},"
  fi

done

api_post_list "${JSON}"
