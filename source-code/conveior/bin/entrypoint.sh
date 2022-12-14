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

# in case config is via variable
if [ "${CONVEIOR_CONFIG_FILE}" != "" ]; then
    echo "${CONVEIOR_CONFIG_FILE}" > /home/conveior-config.yaml
    export CONVEIOR_CONFIG_FILE=""
fi

#nginx -g "daemon off;"
#  do echo -e "HTTP/1.1 200 OK\r\n$(date)\r\nContent-type: text/html\r\n\r\n$(bash /usr/local/bin/metrics.sh)" | nc -l -k -q 5 -p 8080 -q 1;
service cron start & tail -f /var/log/cron.log
echo "Starting NetCat server..."
while true; do { \
  echo "HTTP/1.1 200 OK"; echo ""; bash /usr/local/bin/metrics.sh; } | nc -l -k -q 2 8080; \
done
#echo -e "HTTP/1.1 200 OK\r\n$(date)\r\n\r\n$(bash /usr/local/bin/metrics.sh)" |  nc -vl 8080
