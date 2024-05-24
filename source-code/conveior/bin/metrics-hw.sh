#!/bin/bash

source functions.inc.sh

# Initialize EPOCH time and metrics
EPOCH=$(date +%s)
METRICS="conveior_hwHeartbeat ${EPOCH}"

# Calculate boot time in milliseconds
boot_time_secs=$(cut -d. -f1 /proc/uptime)
bootTime=$(( (EPOCH - boot_time_secs) * 1000 ))
METRICS="${METRICS}\nconveior_hwBoot{label_name=\"boot\"} ${bootTime}"

# Gather RAM and Swap metrics in one go
read totalRam usedRam totalSwap usedSwap <<< $(free | awk '/Mem:/ {totalRam=$2*1024; usedRam=$3*1024} /Swap:/ {totalSwap=$2*1024; usedSwap=$3*1024} END {print totalRam, usedRam, totalSwap, usedSwap}')
METRICS="${METRICS}\nconveior_hwRam{label_name=\"total\"} ${totalRam}\nconveior_hwRam{label_name=\"used\"} ${usedRam}\nconveior_hwSwap{label_name=\"total\"} ${totalSwap}\nconveior_hwSwap{label_name=\"used\"} ${usedSwap}"

# Gather CPU usage
cpu=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')
METRICS="${METRICS}\nconveior_hwCpu{label_name=\"used\"} ${cpu}"

# Gather Disk usage
df -h | grep -E '^/dev/' | awk '{print $1, $5}' | tr -d '%' | while read -r DISK_NAME DISK_VALUE; do
  METRICS="${METRICS}\nconveior_hwDisk{label_name=\"${DISK_NAME}\"} ${DISK_VALUE}"
done

# Gather Docker metrics
CONTAINER_LIST=$(docker ps -f status=running --format="{{.Names}};{{.Size}}")
IFS=$'\n'

# Function to process each container
process_container() {
  local CONTAINER=$1
  local CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  local CONTAINER_SIZE_RAW=$(echo "${CONTAINER}" | awk -F";" '{print $2}' | awk '{print $1}')
  local CONTAINER_SIZE=$(numfmt --from=iec <<< "${CONTAINER_SIZE_RAW}" 2>/dev/null)

  if [[ -n "${CONTAINER_SIZE}" ]]; then
    METRICS="${METRICS}\nconveior_hwDockerSize{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_SIZE}"
  fi

  # Network usage
  read networkRx1 networkTx1 < <(docker exec -i "${CONTAINER_NAME}" sh -c 'cat /sys/class/net/eth0/statistics/rx_bytes /sys/class/net/eth0/statistics/tx_bytes')
  sleep 1
  read networkRx2 networkTx2 < <(docker exec -i "${CONTAINER_NAME}" sh -c 'cat /sys/class/net/eth0/statistics/rx_bytes /sys/class/net/eth0/statistics/tx_bytes')

  if [[ -n "${networkRx1}" && -n "${networkTx1}" && -n "${networkRx2}" && -n "${networkTx2}" ]]; then
    local RX=$((networkRx2 - networkRx1))
    local TX=$((networkTx2 - networkTx1))
    METRICS="${METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"rx\"} ${RX}"
    METRICS="${METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"tx\"} ${TX}"
  fi

  # Docker volume size
  VOLUME_MOUNTS=$(docker inspect -f '{{ json .Mounts }}' "${CONTAINER_NAME}" | jq -r '.[] | select(.Type=="volume") | .Destination')
  for VOLUME in ${VOLUME_MOUNTS}; do
    local VOLUME_SIZE=$(docker exec -i "${CONTAINER_NAME}" du -sb "${VOLUME}" | awk '{print $1}' 2>/dev/null)
    if [[ -n "${VOLUME_SIZE}" ]]; then
      METRICS="${METRICS}\nconveior_hwDockerVolumeSize{label_name=\"${CONTAINER_NAME}\",volume_path=\"${VOLUME}\"} ${VOLUME_SIZE}"
    fi
  done

  # Process metrics
  local THREAD_COUNT=0
  local PIDS=$(docker exec -i "${CONTAINER_NAME}" ps -e -o pid | tail -n +2)
  for PID in ${PIDS}; do
    local THREADS=$(docker exec -i "${CONTAINER_NAME}" cat /proc/"${PID}"/status 2>/dev/null | awk '/Threads:/ {print $2}')
    if [[ -n "${THREADS}" ]]; then
      THREAD_COUNT=$((THREAD_COUNT + THREADS))
    fi
  done
  METRICS="${METRICS}\nconveior_hwProcess{label_name=\"${CONTAINER_NAME}\"} ${THREAD_COUNT}"

  # RAM and CPU usage by processes > 10%
  local PROCESS_LIST=$(docker exec -i "${CONTAINER_NAME}" top -bn1 | awk '$9 > 10 || $10 > 10 {print $1, $2, $6, $9, $10, $12}')
  for PROCESS in ${PROCESS_LIST}; do
    local USER=$(echo "${PROCESS}" | awk '{print $2}')
    local RAM_VALUE=$(echo "${PROCESS}" | awk '{print $3}')
    local CPU_VALUE=$(echo "${PROCESS}" | awk '{print $4}')
    local QUERY=$(echo "${PROCESS}" | awk '{print $6}' | cut -c1-50)
    local PID=$(echo "${PROCESS}" | awk '{print $1}')
    if [[ "${RAM_VALUE}" =~ ^[0-9]+(\.[0-9]+)?$ && $(echo "${RAM_VALUE} > 10" | bc -l) -eq 1 ]]; then
      METRICS="${METRICS}\nconveior_hwRamProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${RAM_VALUE}"
    fi
    if [[ "${CPU_VALUE}" =~ ^[0-9]+(\.[0-9]+)?$ && $(echo "${CPU_VALUE} > 10" | bc -l) -eq 1 ]]; then
      METRICS="${METRICS}\nconveior_hwCpuProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${CPU_VALUE}"
    fi
  done
}

# Process each container sequentially
for CONTAINER in ${CONTAINER_LIST}; do
  process_container "${CONTAINER}"
done

# Gather Docker container start times
docker container ls --format="{{.Names}}" | xargs -n1 docker container inspect --format='{{.Name}};{{.State.StartedAt}}' | awk -F"/" '{print $2}' | while read -r CONTAINER; do
  CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  CONTAINER_DATE_STR=$(echo "${CONTAINER}" | awk -F";" '{print $2}')
  CONTAINER_DATE=$(date -d "${CONTAINER_DATE_STR}" +"%s" 2>/dev/null)
  if [[ -n "${CONTAINER_DATE}" ]]; then
    METRICS="${METRICS}\nconveior_hwDockerLs{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_DATE}"
  fi
done

# Push metrics to Prometheus Pushgateway
GW_URL=$(yq e ".config.prometheus_pushgateway" "${CONFIG_FILE_DIR}")
if [ -z "${GW_URL}" ]; then
  echo -e "${METRICS}"
else
  echo -e "${METRICS}" | curl --data-binary @- "${GW_URL}"
fi
