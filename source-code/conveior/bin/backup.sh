#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

sleep $(shuf -i 10-30 -n1)

source functions.inc.sh
set -e

if [[ "${CONTAINER_ORCHESTRATOR}" == "docker" ]]; then
  backup-mysql.sh
  backup-pgsql.sh
  backup-files.sh
  backup-volume.sh

elif [[ "${CONTAINER_ORCHESTRATOR}" == "kubernetes" ]]; then
  backup-mysql-k8s.sh
  backup-pgsql-k8s.sh
  backup-files-k8s.sh
fi

# If we reached here without error, push a “success=1” for the entire backup script:
/usr/local/bin/metrics-receiver.sh send_metric conveior_backup_status script=backup overall=1 1
