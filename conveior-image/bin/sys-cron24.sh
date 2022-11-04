#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")
source functions.inc.sh

export SLEEP_TIME=$(shuf -i 10-200 -n1)
echo_prom_helper "running cron24.sh, but sleeping first for ${SLEEP_TIME} seconds"
sleep "${SLEEP_TIME}"

backup.sh