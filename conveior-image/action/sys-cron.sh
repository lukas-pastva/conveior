#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

echo "# conveior.io return data"
bash /action/action-hw.sh
#return=$(bash /action/action-hw.sh)
#echo -e "\r\nContent-type: text/html\r\n\r\n${return}"

#echo -e "HTTP/1.0 200 OK\r\n$(date)\r\nContent-type: text/html\r\n\r\n${return}"

#bash /action/action-url.sh
#bash /action/action-container.sh
#bash /action/action-php.sh
#bash /action/action-apache.sh
#bash /action/action-mysql.sh
#bash /action/action-mysql-query.sh
#bash /action/action-pgsql-query.sh
