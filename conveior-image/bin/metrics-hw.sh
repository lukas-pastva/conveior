#!/bin/bash
source functions.inc.sh

echo_prom_helper "Running HW monitor"

# boot time
export bootTime=$((($(date '+%s')-$(cat /proc/uptime | awk '{print $1}' | jq '.|ceil'))*1000))
PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwBoot\",\"name\":\"boot\",\"value\":${bootTime}},"

# hwRam
export totalRam=$(free | grep Mem | awk '{print $2}')
export usedRam=$(free | grep Mem | awk '{print $3}')
export totalRam=$(( ${totalRam} * 1024 ))
export usedRam=$(( ${usedRam} * 1024 ))
if (( ${totalRam} > 0 )) ; then
  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwRam\",\"name\":\"total\",\"value\":${totalRam}},"
fi
if (( ${usedRam} > 0 )) ; then
  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwRam\",\"name\":\"used\",\"value\":${usedRam}},"
fi

# hwSwap
export totalSwap=$(free | grep Swap | awk '{print $2}')
export usedSwap=$(free | grep Swap | awk '{print $3}')
totalSwap=$(( ${totalSwap} * 1024 ))
usedSwap=$(( ${usedSwap} * 1024 ))
if (( ${totalSwap} > 0 )) ; then
  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwSwap\",\"name\":\"total\",\"value\":${totalSwap}},"
fi
if (( ${usedSwap} > 0 )) ; then
  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwSwap\",\"name\":\"used\",\"value\":${usedSwap}},"
fi

# hwCpu
export cpu=$(vmstat 1 2 | tail -1 | awk '{print $15}')
cpu=$(( 100 - $cpu ))
if (( ${cpu} > 0 )) ; then
  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwCpu\",\"name\":\"used\",\"value\":${cpu}},"
fi

# hwDisk
while read DISK;
do
  export DISK_NAME=$( echo ${DISK} | grep -E [0-9] | awk '{print $1}')
  export DISK_VALUE=$( echo ${DISK} | grep -E [0-9] | awk '{print $5}' | awk -F"%" '{print $1}')
  if (( ${DISK_VALUE} > 0 )) ; then
    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwDisk\",\"name\":\"${DISK_NAME}\",\"value\":${DISK_VALUE}},"
  fi
done < <(df)

#in caase docker not allowed sending at least what i can
echo "${PROMETHEUS_DATA}"
PROMETHEUS_DATA=""

# docker
CONTAINER_LIST=$(docker ps --format="{{.Names}};{{.Size}}")
IFS=$'\n'
for CONTAINER in $CONTAINER_LIST;
do
  export CONTAINER_NAME=$( echo ${CONTAINER} | awk -F";" '{print $1}')
  export CONTAINER_SIZE=$( echo ${CONTAINER} | awk -F";" '{print $2}' | awk -F"virtual " '{print $2}' | rev | cut -c3- | rev | numfmt --from=iec)

  echo_prom_helper "CONTAINER_NAME: ${CONTAINER_NAME}"

  # hwZombie
  export ZOMBIE=$(docker exec -i ${CONTAINER_NAME} ps aux | grep defunct | wc -l)
  if (( ${ZOMBIE} > 0 )) ; then
    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwZombie\",\"name\":\"${CONTAINER_NAME}\",\"value\":${ZOMBIE}},"
  fi

  # hwNetwork
  export networkRx1=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/rx_bytes || true)
  export networkTx1=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/tx_bytes || true)
  sleep 1
  export networkRx2=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/rx_bytes || true)
  export networkTx2=$(docker exec -i ${CONTAINER_NAME} cat /sys/class/net/eth0/statistics/tx_bytes || true)
  if [ -n "${networkRx1}" ] &&  [ -n "${networkTx1}" ] &&  [ -n "${networkRx2}" ] &&  [ -n "${networkTx2}" ] 2>/dev/null; then
    export RX=$(( ${networkRx2} - ${networkRx1} ))
    export TX=$(( ${networkTx2} - ${networkTx1} ))
    if (( ${RX} > 0 )) ; then
        PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwNetwork\",\"name\":\"${CONTAINER_NAME}/Rx\",\"value\":${RX}},"
    fi
    if (( ${TX} > 0 )) ; then
        PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwNetwork\",\"name\":\"${CONTAINER_NAME}/Tx\",\"value\":${TX}},"
    fi
  fi

  # Docker size
  if (( ${CONTAINER_SIZE} > 0 )) ; then
    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwDockerSize\",\"name\":\"${CONTAINER_NAME}\",\"value\":${CONTAINER_SIZE}},"
  fi

  # hwProcess
  export PROCESS=$(docker exec -i ${CONTAINER_NAME} ps aux | ps -eo nlwp | tail -n +2 | awk '{ num_threads += $1 } END { print num_threads }')
  if (( ${PROCESS} > 0 )) ; then
    PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwProcess\",\"name\":\"${CONTAINER_NAME}\",\"value\":${PROCESS}},"
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

        PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwRamProcess\",\"name\":\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\",\"value\":${VALUE}},"
      done
    fi
  fi

  # cpuProcessesUsage > 10 %
    export PROCESS_LIST=$(docker exec -i ${CONTAINER_NAME} ps -o pid,user,%cpu,command ax | awk '$3 > 10')
    if [[ "${PROCESS_LIST}" != *"failed"* ]]; then
      if [[ "${PROCESS_LIST}" != *"supported"* ]]; then
        export IFS=$'\n'
        for PROCESS in ${PROCESS_LIST}; do
          export USER=$(echo "${PROCESS}" | awk '{print $2}')
          export VALUE=$(echo "${PROCESS}" | awk '{print $3}' | jq '.|ceil')
          export QUERY=$(echo "${PROCESS}" | awk '{print $4}'| cut -c1-50)
          export PID=$(echo "${PROCESS}" | awk '{print $1}')

          PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwCpuProcess\",\"name\":\"${CONTAINER_NAME}/${PID}/${USER}/${QUERY}\",\"value\":${VALUE}},"
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

  PROMETHEUS_DATA="${PROMETHEUS_DATA}{\"chart\":\"hwDockerLs\",\"name\":\"${CONTAINER_NAME}\",\"value\":${CONTAINER_DATE}},"
done < <(docker container ls --format="{{.Names}}" | xargs -n1 docker container inspect --format='{{.Name}};{{.State.StartedAt}}' | awk -F"/" '{print $2}')

echo "${PROMETHEUS_DATA}"
