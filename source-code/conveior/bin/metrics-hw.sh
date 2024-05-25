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
while read -r DISK_NAME DISK_VALUE; do
  METRICS="${METRICS}\nconveior_hwDisk{label_name=\"${DISK_NAME}\"} ${DISK_VALUE}"
done < <(df -h | grep -E '^/dev/' | awk '{print $1, $5}' | tr -d '%')

# Gather Docker metrics
CONTAINER_LIST=$(docker ps -f status=running --format="{{.Names}};{{.Size}}")
IFS=$'\n'

# Function to process each container
process_container() {
  local CONTAINER=$1
  local CONTAINER_METRICS=""
  local CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  local CONTAINER_SIZE_RAW=$(echo "${CONTAINER}" | awk -F";" '{print $2}' | awk '{print $1}')
  local CONTAINER_SIZE_RAW_CORRECTED=$(echo "${CONTAINER_SIZE_RAW}" | sed -e 's/kB$/K/' -e 's/MB$/M/' -e 's/GB$/G/' -e 's/B$//')
  local CONTAINER_SIZE=$(numfmt --from=iec <<< "${CONTAINER_SIZE_RAW_CORRECTED}" 2>/dev/null)

  local VIRTUAL_SIZE_RAW=$(echo "${CONTAINER}" | awk -F"[()]" '{print $2}' | awk '{print $2}')
  local VIRTUAL_SIZE_RAW_CORRECTED=$(echo "${VIRTUAL_SIZE_RAW}" | sed -e 's/kB$/K/' -e 's/MB$/M/' -e 's/GB$/G/' -e 's/B$//')
  local VIRTUAL_SIZE=$(numfmt --from=iec <<< "${VIRTUAL_SIZE_RAW_CORRECTED}" 2>/dev/null)

  if [[ -n "${CONTAINER_SIZE}" ]]; then
    CONTAINER_METRICS="${CONTAINER_METRICS}\nconveior_hwDockerSize{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_SIZE}"
  fi
  if [[ -n "${VIRTUAL_SIZE}" ]]; then
    CONTAINER_METRICS="${CONTAINER_METRICS}\nconveior_hwDockerVirtualSize{label_name=\"${CONTAINER_NAME}\"} ${VIRTUAL_SIZE}"
  fi

  # Network usage
  network_stats1=$(docker exec -i "${CONTAINER_NAME}" sh -c 'cat /sys/class/net/eth0/statistics/rx_bytes; cat /sys/class/net/eth0/statistics/tx_bytes')
  network_stats1="${network_stats1//$'\n'/ }"
  networkRx1="${network_stats1%% *}"
  networkTx1="${network_stats1#* }"
  sleep 1
  network_stats2=$(docker exec -i "${CONTAINER_NAME}" sh -c 'cat /sys/class/net/eth0/statistics/rx_bytes; cat /sys/class/net/eth0/statistics/tx_bytes')
  network_stats2="${network_stats1//$'\n'/ }"
  networkRx2="${network_stats2%% *}"
  networkTx2="${network_stats2#* }"

  if [[ -n "${networkRx1}" && -n "${networkTx1}" && -n "${networkRx2}" && -n "${networkTx2}" ]]; then
    local RX=$((networkRx2 - networkRx1))
    local TX=$((networkTx2 - networkTx1))
    CONTAINER_METRICS="${CONTAINER_METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"rx\"} ${RX}"
    CONTAINER_METRICS="${CONTAINER_METRICS}\nconveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"tx\"} ${TX}"
  fi
  
  # Docker volume size
  VOLUME_MOUNTS=$(docker inspect -f '{{ json .Mounts }}' "${CONTAINER_NAME}" | jq -r '.[] | select(.Type=="volume") | .Destination')
  for VOLUME in ${VOLUME_MOUNTS}; do
    local VOLUME_SIZE=$(docker exec -i "${CONTAINER_NAME}" du -sb "${VOLUME}" | awk '{print $1}' 2>/dev/null)
    if [[ -n "${VOLUME_SIZE}" ]]; then
      CONTAINER_METRICS="${CONTAINER_METRICS}\nconveior_hwDockerVolumeSize{label_name=\"${CONTAINER_NAME}\",volume_path=\"${VOLUME}\"} ${VOLUME_SIZE}"
    fi
  done

  echo "${CONTAINER_METRICS}\n"
}

process_containers_memory_and_cpu() {
  # Fetching overall CPU and RAM usage of the container
  docker stats --no-stream --format "{{.Name}} {{.CPUPerc}} {{.MemUsage}}" | while IFS=" " read -r NAME CPU_USAGE MEM_USAGE; do
    CPU_VALUE=$(echo "${CPU_USAGE}" | tr -d '%')
    MEM_VALUE=$(echo "${MEM_USAGE}" | awk '{print $1 * 1024 * 1024}' | tr -d 'MiB')

    if [[ "${CPU_VALUE}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo "\nconveior_hwCpuProcess{label_name=\"${NAME}\"} ${CPU_VALUE}"
    fi
    if [[ "${MEM_VALUE}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      echo "\nconveior_hwRamProcess{label_name=\"${NAME}\"} ${MEM_VALUE}"
    fi
  done
}

# Process each container sequentially
for CONTAINER in ${CONTAINER_LIST}; do
  CONTAINER_METRICS=$(process_container "${CONTAINER}")
  METRICS="${METRICS}${CONTAINER_METRICS}"
done

# Process overall CPU and RAM usage of the containers
CONTAINERS_MEMORY_AND_CPU_METRICS=$(process_containers_memory_and_cpu)
METRICS="${METRICS}${CONTAINERS_MEMORY_AND_CPU_METRICS}"

# Gather Docker container start times
while read -r CONTAINER; do
  CONTAINER_NAME=$(echo "${CONTAINER}" | awk -F";" '{print $1}')
  CONTAINER_DATE_STR=$(echo "${CONTAINER}" | awk -F";" '{print $2}')
  CONTAINER_DATE=$(date -d "${CONTAINER_DATE_STR}" +"%s" 2>/dev/null)
  if [[ -n "${CONTAINER_DATE}" ]]; then
    METRICS="${METRICS}\nconveior_hwDockerLs{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_DATE}"
  fi
done < <(docker container ls --format="{{.Names}}" | xargs -n1 docker container inspect --format='{{.Name}};{{.State.StartedAt}}' | awk -F"/" '{print $2}')

# Push metrics to Prometheus Pushgateway
GW_URL=$(yq e ".config.prometheus_pushgateway" "${CONFIG_FILE_DIR}")
if [ -z "${GW_URL}" ]; then
  echo -e "${METRICS}"
else
  echo -e "${METRICS}" | curl --data-binary @- "${GW_URL}"
fi
