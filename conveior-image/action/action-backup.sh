#!/bin/bash
source /action/action-functions.inc.sh

# check whether we do have the google password
get_upload_credentials
if [ "${OAUTH2_TOKEN}" == "null" ]; then
  log_msg "OAUTH2_TOKEN is not present, not backing up"
else
  log_msg "Starting backup processes"
  bash /action/action-backup-certificates.sh
  bash /action/action-backup-mysql.sh
  bash /action/action-backup-volumes.sh
  bash /action/action-backup-pgsql.sh
  bash /action/action-backup-files.sh
fi
