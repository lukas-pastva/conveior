#!/bin/bash
source functions.inc.sh

# check whether we do have the google password
get_upload_credentials
if [ "${OAUTH2_TOKEN}" == "null" ]; then
  log_msg "OAUTH2_TOKEN is not present, not backing up"
else
  log_msg "Starting backup processes"
  bash backup-certificates.sh
  bash backup-mysql.sh
  bash backup-volumes.sh
  bash backup-pgsql.sh
  bash backup-files.sh
fi
