#!/bin/bash

source functions.inc.sh

# Initialize EPOCH time and metrics
EPOCH=$(date +%s)
METRICS="conveior_hwHeartbeat ${EPOCH}"

# Calculate boot time in milliseconds
boot_time_secs=$(cut -d. -f1 /proc/uptime)
bootTime=$(( (EPOCH - boot_time_secs) * 1000 ))
METRICS="${METRICS}\nconveior_hwBoot{label_name=\"boot\"} ${bootTime}"

# Gather RAM metrics
totalRam=$(free | awk '/Mem:/ {print $2 * 1024}')
usedRam=$(free | awk '/Mem:/ {print $3 * 1024}')
METRICS="${METRICS}\nconveior_hwRam{label_name=\"total\"} ${totalRam}\nconveior_hwRam{label_name=\"used\"} ${usedRam}"

# Gather Swap metrics
totalSwap=$(free | awk '/Swap:/ {print $2 * 1024}')
usedSwap=$(free | awk '/Swap:/ {print $3 * 1024}')
METRICS="${METRICS}\nconveior_hwSwap{label_name=\"total\"} ${totalSwap}\nconveior_hwSwap{label_name=\"used\"} ${usedSwap}"

# Gather CPU usage
cpu=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
METRICS="${METRICS}\nconveior_hwCpu{label_name=\"used\"} ${cpu}"

# Gather Disk usage
while read -r DISK; do
  DISK_NAME=$(echo "${DISK}" | awk '{print $1}')
  DISK_VALUE=$(echo "${DISK}" | awk '{print $5}' | tr -d '%')
  METRICS="${METRICS}\nconveior_hwDisk{label_name=\"${DISK_NAME}\"} ${DISK_VALUE}"
done < <(df -h | grep -E '^/dev/')

# Gather Docker metrics
CONTAINER_LIST=$(docker ps -f status=running --format="{{.Names}};{{.Size}}")
for CONTAINER in ${CONTAINER_LIST}; do
  CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  CONTAINER_SIZE=$(echo "${CONTAINER}" | awk -F";" '{print $2}' | awk -F" " '{print $1}' | numfmt --from=iec 2>/dev/null)

  if [ -n "${CONTAINER_SIZE}" ]; then
    # Docker size
    METRICS="${METRICS}\nconveior_hwDockerSize{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_SIZE}"
  fi

  # Network usage
  networkRx1=$(docker exec -i "${CONTAINER_NAME}" cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null)
  networkTx1=$(docker exec -i "${CONTAINER_NAME}" cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null)
  sleep 1
  networkRx2=$(docker exec -i "${CONTAINER_NAME}" cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null)
  networkTx2=$(docker exec -i "${CONTAINER_NAME}" cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null)
  
  if [ -n "${networkRx1}" ] && [ -n "${networkTx1}" ] && [ -n "${networkRx2}" ] && [ -n "${networkTx2}" ]; then
    RX=$((networkRx2 - networkRx1))
    TX=$((networkTx2 - networkTx1))
    METRICS="${METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"rx\"} ${RX}"
    METRICS="${METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"tx\"} ${TX}"
  fi

  # Docker volume size
  VOLUME_MOUNTS=$(docker inspect -f '{{ json .Mounts }}' "${CONTAINER_NAME}" | jq -r '.[] | select(.Type=="volume") | .Destination')
  for VOLUME in ${VOLUME_MOUNTS}; do
    VOLUME_SIZE=$(docker exec -i "${CONTAINER_NAME}" du -sb "${VOLUME}" | awk '{print $1}' 2>/dev/null)
    if [ -n "${VOLUME_SIZE}" ]; then
      METRICS="${METRICS}\nconveior_hwDockerVolumeSize{label_name=\"${CONTAINER_NAME}\",volume_path=\"${VOLUME}\"} ${VOLUME_SIZE}"
    fi
  done

  # Process metrics
  THREAD_COUNT=0
  PIDS=$(docker exec -i "${CONTAINER_NAME}" ps -e -o pid | tail -n +2)
  for PID in ${PIDS}; do
    THREADS=$(docker exec -i "${CONTAINER_NAME}" cat /proc/"${PID}"/status 2>/dev/null | awk '/Threads:/ {print $2}')
    if [ -n "${THREADS}" ]; then
      THREAD_COUNT=$((THREAD_COUNT + THREADS))
    fi
  done
  METRICS="${METRICS}\nconveior_hwProcess{label_name=\"${CONTAINER_NAME}\"} ${THREAD_COUNT}"

  # RAM usage by processes > 10%
  PROCESS_LIST=$(docker exec -i "${CONTAINER_NAME}" top -bn1 | awk '$10 > 10 {print $1, $2, $6, $12}')
  for PROCESS in ${PROCESS_LIST}; do
    USER=$(echo "${PROCESS}" | awk '{print $2}')
    VALUE=$(echo "${PROCESS}" | awk '{print $3}')
    QUERY=$(echo "${PROCESS}" | awk '{print $4}' | cut -c1-50)
    PID=$(echo "${PROCESS}" | awk '{print $1}')
    METRICS="${METRICS}\nconveior_hwRamProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${VALUE}"
  done

  # CPU usage by processes > 10%
  PROCESS_LIST=$(docker exec -i "${CONTAINER_NAME}" top -bn1 | awk '$9 > 10 {print $1, $2, $9, $12}')
  for PROCESS in ${PROCESS_LIST}; do
    USER=$(echo "${PROCESS}" | awk '{print $2}')
    VALUE=$(echo "${PROCESS}" | awk '{print $3}')
    QUERY=$(echo "${PROCESS}" | awk '{print $4}' | cut -c1-50)
    PID=$(echo "${PROCESS}" | awk '{print $1}')
    METRICS="${METRICS}\nconveior_hwCpuProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${VALUE}"
  done
done

# Gather Docker container start times
while read -r CONTAINER; do
  CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  CONTAINER_DATE_STR=$(echo "${CONTAINER}" | awk -F";" '{print $2}')
  CONTAINER_DATE=$(date -d "${CONTAINER_DATE_STR}" +"%s")
  METRICS="${METRICS}\nconveior_hwDockerLs{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_DATE}"
done < <(docker container ls --format="{{.Names}}" | xargs -n1 docker container inspect --format='{{.Name}};{{.State.StartedAt}}' | awk -F"/" '{print $2}')

# Push metrics to Prometheus Pushgateway
GW_URL=$(yq e ".config.prometheus_pushgateway" "${CONFIG_FILE_DIR}")
if [ -z "${GW_URL}" ]; then
  echo -e "${METRICS}"
else
  echo -e "${METRICS}" | curl --data-binary @- "${GW_URL}"
fi
