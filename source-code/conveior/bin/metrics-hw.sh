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
  if (( ${CONTAINER_SIZE} > 0 )) ; then
    METRIC="conveior_hwDockerSize{label_name=\"${CONTAINER_NAME}\"} ${CONTAINER_SIZE}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi

  # Docker volume size
  VOLUME_MOUNTS=$(docker inspect -f '{{ range .Mounts }}{{ .Source }} {{ end }}' ${CONTAINER_NAME})
  for VOLUME in ${VOLUME_MOUNTS}; do
    VOLUME_SIZE=$(du -sb ${VOLUME} | awk '{print $1}')
    if (( ${VOLUME_SIZE} > 0 )); then
      METRIC="conveior_hwDockerVolumeSize{label_name=\"${CONTAINER_NAME}\",volume_path=\"${VOLUME}\"} ${VOLUME_SIZE}"
      METRICS=$(echo -e "$METRICS\n$METRIC")
    fi
  done

  # hwProcess
  export PROCESS=$(docker exec -i ${CONTAINER_NAME} ps aux | ps -eo nlwp | tail -n +2 | awk '{ num_threads += $1 } END { print num_threads }')
  if (( ${PROCESS} > 0 )) ; then
    METRIC="conveior_hwProcess{label_name=\"${CONTAINER_NAME}\"} ${PROCESS}"
    METRICS=$(echo -e "$METRICS\n$METRIC")
  fi

  # ramProcessesUsage > 10 %
  export PROCESS_LIST=$(docker exec -i ${CONTAINER_NAME} ps -o pid,user,%mem,command ax | awk '$3 > 10')
  if [[ "${PROCESS_LIST}" != *"failed"* ]]; then
    if [[ "${PROCESS_LIST}" != *"supported"* ]]; then
      export IFS=$'\n'
      for PROCESS in ${PROCESS_LIST}; do
        export USER=$(echo "${PROCESS}" | awk '{print $2}')
        export VALUE=$(echo "${PROCESS}" | awk '{print $3}' | jq '.|ceil')
        export QUERY=$(echo "${PROCESS}" | awk '{print $4}'| cut -c1-50)
        export PID=$(echo "${PROCESS}" | awk '{print $1}')

        METRIC="conveior_hwRamProcess{label_name=\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\"} ${VALUE}"
        METRICS=$(echo -e "$METRICS\n$METRIC")

      done
    fi
  fi

  # cpuProcessesUsage > 10 %
    export PROCESS_LIST=$(docker exec -i ${CONTAINER_NAME} ps -o pid,user,%cpu,command ax | awk '$3 > 10')
    if [[ "${PROCESS_LIST}" != *"failed"* ]]; then
      if ([[ "${PROCESS_LIST}" != *"supported"* ]] ); then
        export IFS=$'\n'
        for PROCESS in ${PROCESS_LIST}; do
          export USER=$(echo "${PROCESS}" | awk '{print $2}')
          export VALUE=$(echo "${PROCESS}" | awk '{print $3}' | jq '.|ceil')
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

