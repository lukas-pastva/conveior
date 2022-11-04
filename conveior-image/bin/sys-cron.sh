#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

echo "# conveior.io return data"
bash metrics-mysql.sh

#return=$(bash metrics-hw.sh)
#echo -e "\r\nContent-type: text/html\r\n\r\n${return}"

#echo -e "HTTP/1.0 200 OK\r\n$(date)\r\nContent-type: text/html\r\n\r\n${return}"
