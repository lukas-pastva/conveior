#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

echo -ne "HTTP/1.0 200 OK\r\nContent-Length: 1024\r\n\r\n"

bash /action/action-hw.sh
bash /action/action-url.sh
bash /action/action-container.sh
bash /action/action-php.sh
bash /action/action-apache.sh
bash /action/action-mysql.sh
bash /action/action-mysql-query.sh
bash /action/action-pgsql-query.sh
