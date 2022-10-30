#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

bash /action/action-hw.sh
bash /action/action-url.sh
bash /action/action-container.sh
bash /action/action-php.sh
bash /action/action-apache.sh
bash /action/action-mysql.sh
bash /action/action-mysql-query.sh
bash /action/action-pgsql-query.sh
