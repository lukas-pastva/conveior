#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

echo "# conveior.io return data"
bash metrics-hw.sh
#return=$(bash metrics-hw.sh)
#echo -e "\r\nContent-type: text/html\r\n\r\n${return}"

#echo -e "HTTP/1.0 200 OK\r\n$(date)\r\nContent-type: text/html\r\n\r\n${return}"

#bash metrics-url.sh
#bash metrics-container.sh
#bash metrics-php.sh
#bash metrics-apache.sh
#bash metrics-mysql.sh
#bash metrics-mysql-query.sh
#bash metrics-pgsql-query.sh
