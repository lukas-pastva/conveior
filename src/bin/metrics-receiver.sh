#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

source functions.inc.sh

PUSH_GW_URL="$(yq e '.config.forwarder | .[].pushGw' "${CONFIG_FILE_DIR}")"

# ------------------------------------------------------------------------------
# send_metric: accepts a metric name, zero or more "key=value" label pairs,
# and a final numeric value. Example usage:
#   ./metrics-receiver.sh send_metric my_metric foo=bar baz=qux 42
#
# This will generate and push a Prometheus metric line:
#   my_metric{foo="bar",baz="qux"} 42
# ------------------------------------------------------------------------------
send_metric() {
  if [ $# -lt 2 ]; then
    echo "Usage: send_metric <metric_name> [key=value ...] <numeric_value>"
    echo "Example: send_metric my_custom_metric env=dev region=us-east 123.45"
    return 1
  fi

  local metric_name="$1"
  shift

  # Everything but the last argument is treated as a label
  local labels=()
  while (( $# > 1 )); do
    labels+=( "$1" )
    shift
  done

  # The last argument is the numeric value
  local value="$1"

  # Build up the label string
  local label_string=""
  if [ ${#labels[@]} -gt 0 ]; then
    label_string="{"
    for (( i=0; i<${#labels[@]}; i++ )); do
      local kv="${labels[$i]}"
      local key="${kv%%=*}"
      local val="${kv#*=}"
      label_string+="${key}=\"${val}\""
      if [ $i -lt $(( ${#labels[@]} - 1 )) ]; then
        label_string+=","
      fi
    done
    label_string+="}"
  fi

  local metric_line="${metric_name}${label_string} ${value}"

  # Write to a temp file
  local tmp_file
  tmp_file="$(mktemp)"
  echo "$metric_line" > "$tmp_file"

  # Figure out the instance label so we can replace 'node-exporter' in the URL
  local instance_name="missing"
  for kv in "${labels[@]}"; do
    if [[ "$kv" =~ ^instance= ]]; then
      instance_name="${kv#instance=}"  # e.g. if label is instance=remp-nginx => instance_name="remp-nginx"
    fi
  done

  # Simple Bash string replacement: replace FIRST occurrence of 'node-exporter'
  # in PUSH_GW_URL with the instance name:
  local final_url="${PUSH_GW_URL/node-exporter/$instance_name}"

  echo "Pushing metric: $metric_line"

  # Push to the gateway
  curl --silent --data-binary @"$tmp_file" "$final_url"

  rm -f "$tmp_file"
}

# Let this script be called like:
#   ./metrics-receiver.sh send_metric metric_name instance=remp-nginx 1
# etc.
"$@"
