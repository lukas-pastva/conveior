#!/bin/bash
source /action/action-functions.inc.sh

export PROJECT_NAME=$1
export PROJECT_ACTION=$2
cp /action/action-functions.inc.sh /action/DevOps/${PROJECT_NAME}/${PROJECT_ACTION}
cp -r /action/sys-backupper /action/DevOps/${PROJECT_NAME}/${PROJECT_ACTION}

cd /action/DevOps/${PROJECT_NAME}/${PROJECT_ACTION} && zip -rqq "data.zip" *
rm /action/DevOps/${PROJECT_NAME}/${PROJECT_ACTION}/action-functions.inc.sh
cat "data.zip"
