#!/bin/bash
source functions.inc.sh

#heatbeat
export EPOCH=$(date +%s)
METRIC="conveior_hwHeartbeat ${EPOCH}"
METRICS=$(echo -e "$METRICS\n$METRIC")

# boot time
export bootTime=$((($(date '+%s')-$(cat /proc/uptime | awk '{print $1}' | jq '.|ceil'))*1000))
METRIC="conveior_hwBoot{label_name=\"boot\"} ${bootTime}"
METRICS=$(echo -e "$METRICS\n$METRIC")

# hwRam
export totalRam=$(free | grep Mem | awk '{print $2}')
export usedRam=$(free | grep Mem | awk '{print $3}')
export totalRam=$(( ${totalRam} * 1024 ))
export usedRam=$(( ${usedRam} * 1024 ))
if (( ${totalRam} > 0 )) ; then
  METRIC="conveior_hwRam{label_name=\"total\"} ${totalRam}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
fi
if (( ${usedRam} > 0 )) ; then
  METRIC="conveior_hwRam{label_name=\"used\"} ${usedRam}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
fi

# hwSwap
export totalSwap=$(free | grep Swap | awk '{print $2}')
export usedSwap=$(free | grep Swap | awk '{print $3}')
totalSwap=$(( ${totalSwap} * 1024 ))
usedSwap=$(( ${usedSwap} * 1024 ))
if (( ${totalSwap} > 0 )) ; then
  METRIC="conveior_hwSwap{label_name=\"total\"} ${totalSwap}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
fi
if (( ${usedSwap} > 0 )) ; then
  METRIC="conveior_hwSwap{label_name=\"used\"} ${usedSwap}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
fi

# hwCpu
export cpu=$(vmstat 1 2 | tail -1 | awk '{print $15}')
cpu=$(( 100 - $cpu ))
if (( ${cpu} > 0 )) ; then
  METRIC="conveior_hwCpu{label_name=\"used\"} ${cpu}"
  METRICS=$(echo -e "$METRICS\n$METRIC")
fi

# hwDisk
while read DISK;
do
  export DISK_NAME=$( echo ${DISK} | grep -E [0-9] | awk '{print $1}')
  export DISK_VALUE=$( echo ${DISK} | grep -E [0-9] | awk '{print $5}' | awk -F"%" '{print $1}')
  if (( ${DISK_VALUE} > 0 )) ; then
    METRIC="conveior_hwDisk{label_name=\"${DISK_NAME}\"} ${DISK_VALUE}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi
done < <(df)

# docker
CONTAINER_LIST=$(docker ps -f status=running --format="{{.Names}};{{.Size}}")
IFS=$'\n'
for CONTAINER in $CONTAINER_LIST;
do
  export CONTAINER_NAME=$( echo ${CONTAINER} | awk -F";" '{print $1}')
  export CONTAINER_SIZE=$( echo ${CONTAINER} | awk -F";" '{print $2}' | awk -F"virtual " '{print $2}' | rev | cut -c3- | rev | numfmt --from=iec)

  # hwNetwork
  export networkRx1=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/rx_bytes)
  export networkTx1=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/tx_bytes)
  sleep 1
  export networkRx2=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/rx_bytes)
  export networkTx2=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/tx_bytes)
  if [ -n "${networkRx1}" ] &&  [ -n "${networkTx1}" ] &&  [ -n "${networkRx2}" ] &&  [ -n "${networkTx2}" ] 2>/dev/null; then
    export RX=$(( ${networkRx2} - ${networkRx1} ))
    export TX=$(( ${networkTx2} - ${networkTx1} ))
    if (( ${RX} > 0 )) ; then
        METRIC="conveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"rx\"} ${RX}"
        METRICS=$(echo -e "$METRICS\n$METRIC")
    fi
    if (( ${TX} > 0 )) ; then
        METRIC="conveior_hwNetwork{label_name=\"${CONTAINER_NAME}\",query_name=\"tx\"} ${TX}"
        METRICS=$(echo -e "$METRICS\n$METRIC")
    fi
  fi

  # Docker size
  if [ -n "${CONTAINER_SIZE}" ] && (( ${CONTAINER_SIZE} > 0 )) ; then
    METRIC="conveior_hwDockerSize{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_SIZE}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi

  # Docker volume size
  VOLUME_MOUNTS=$(docker inspect -f '{{ json .Mounts }}' ${CONTAINER_NAME} | jq -r '.[] | select(.Type=="volume") | .Destination')
  for VOLUME in ${VOLUME_MOUNTS}; do
    VOLUME_SIZE=$(docker exec -i ${CONTAINER_NAME} du -sb ${VOLUME} | awk '{print $1}')
    if [ -n "${VOLUME_SIZE}" ] && (( ${VOLUME_SIZE} > 0 )); then
      METRIC="conveior_hwDockerVolumeSize{label_name=\"${CONTAINER_NAME}\",volume_path=\"${VOLUME}\"} ${VOLUME_SIZE}"
      METRICS=$(echo -e "$METRICS\n$METRIC")
    fi
  done

  # hwProcess
  THREAD_COUNT=0
  PIDS=$(docker exec -i ${CONTAINER_NAME} ps -e -o pid | tail -n +2)
  for PID in $PIDS; do
    THREADS=$(docker exec -i ${CONTAINER_NAME} cat /proc/$PID/status 2>/dev/null | grep Threads | awk '{print $2}')
    if [[ -n "$THREADS" && "$THREADS" =~ ^[0-9]+$ ]]; then
      THREAD_COUNT=$((THREAD_COUNT + THREADS))
    fi
  done

  if (( THREAD_COUNT > 0 )) ; then
    METRIC="conveior_hwProcess{label_name=\"${CONTAINER_NAME}\"} ${THREAD_COUNT}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi

  # ramProcessesUsage > 10 %
  export PROCESS_LIST=$(docker exec -i ${CONTAINER_NAME} top -bn1 | awk '$10 > 10 {print $1, $2, $6, $12}')
  if [[ "${PROCESS_LIST}" != *"failed"* ]]; then
    if [[ "${PROCESS_LIST}" != *"supported"* ]]; then
      export IFS=$'\n'
      for PROCESS in ${PROCESS_LIST}; do
        export USER=$(echo "${PROCESS}" | awk '{print $2}')
        export VALUE=$(echo "${PROCESS}" | awk '{print $3}')
        export QUERY=$(echo "${PROCESS}" | awk '{print $4}'| cut -c1-50)
        export PID=$(echo "${PROCESS}" | awk '{print $1}')

        METRIC="conveior_hwRamProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${VALUE}"
        METRICS=$(echo -e "$METRICS\n$METRIC")

      done
    fi
  fi

  # cpuProcessesUsage > 10 %
  export PROCESS_LIST=$(docker exec -i ${CONTAINER_NAME} top -bn1 | awk '$9 > 10 {print $1, $2, $9, $12}')
  if [[ "${PROCESS_LIST}" != *"failed"* ]]; then
    if [[ "${PROCESS_LIST}" != *"supported"* ]]; then
      export IFS=$'\n'
      for PROCESS in ${PROCESS_LIST}; do
        export USER=$(echo "${PROCESS}" | awk '{print $2}')
        export VALUE=$(echo "${PROCESS}" | awk '{print $3}')
        export QUERY=$(echo "${PROCESS}" | awk '{print $4}'| cut -c1-50)
        export PID=$(echo "${PROCESS}" | awk '{print $1}')

        METRIC="conveior_hwCpuProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${VALUE}"
        METRICS=$(echo -e "$METRICS\n$METRIC")

      done
    fi
  fi

done
unset IFS

# hwDockerLs
while read CONTAINER;
do
  export CONTAINER_NAME=$( echo ${CONTAINER} | awk -F";" '{print $1}')
  export CONTAINER_DATE_STR=$( echo ${CONTAINER} | awk -F";" '{print $2}')
  export CONTAINER_DATE=$(date -d ${CONTAINER_DATE_STR} +"%s" )

  METRIC="conveior_hwDockerLs{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_DATE}"
  METRICS=$(echo -e "$METRICS\n$METRIC")

done < <(docker container ls --format="{{.Names}}" | xargs -n1 docker container inspect --format='{{.Name}};{{.State.StartedAt}}' | awk -F"/" '{print $2}')

GW_URL=$(yq e ".config.prometheus_pushgateway" ${CONFIG_FILE_DIR})
if [ -z "$GW_URL" ]; then
  echo -e "$METRICS"
else
  echo -e "$METRICS" | curl --data-binary @- "${GW_URL}"
fi
