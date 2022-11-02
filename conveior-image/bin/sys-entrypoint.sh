#!/bin/sh

echo ""
echo ""
echo " ██████  ██████  ███    ██ ██    ██ ███████ ██  ██████  ██████     ██  ██████"
echo "██      ██    ██ ████   ██ ██    ██ ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo "██      ██    ██ ██ ██  ██ ██    ██ █████   ██ ██    ██ ██████     ██ ██    ██"
echo "██      ██    ██ ██  ██ ██  ██  ██  ██      ██ ██    ██ ██   ██    ██ ██    ██"
echo " ██████  ██████  ██   ████   ████   ███████ ██  ██████  ██   ██ ██ ██  ██████"
echo ""
echo ""


#nginx -g "daemon off;"

#  do echo -e "HTTP/1.1 200 OK\r\n$(date)\r\nContent-type: text/html\r\n\r\n$(bash /usr/local/bin/sys-cron.sh)" | nc -l -k -q 5 -p 8080 -q 1;

echo "Starting NetCat server..."
while true; do { \
  echo "HTTP/1.1 200 OK"; echo ""; bash /usr/local/bin/sys-cron.sh; } | nc -l -k -q 2 8080; \
done

#echo -e "HTTP/1.1 200 OK\r\n$(date)\r\n\r\n$(bash /usr/local/bin/sys-cron.sh)" |  nc -vl 8080

#service cron start & tail -f /var/log/cron.log
