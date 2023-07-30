#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

sleep $(shuf -i 10-30 -n1)

source functions.inc.sh

if [[ "${CONTAINER_ORCHESTRATOR}" == "docker" ]]; then
  backup-mysql.sh
  backup-pgsql.sh
  backup-files.sh
fi

if [[ "${CONTAINER_ORCHESTRATOR}" == "kubernetes" ]]; then
  backup-mysql-k8s.sh
  backup-files-k8s.sh
fi