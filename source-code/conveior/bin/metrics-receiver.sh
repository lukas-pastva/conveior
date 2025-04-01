#!/bin/bash
export $(xargs -0 -a "/proc/1/environ") 2>/dev/null

source functions.inc.sh

PUSH_GW_URL=$(yq e ".config.forwarder | .[].pushGw" ${CONFIG_FILE_DIR})

# ------------------------------------------------------------------------------
# send_metric: accepts a metric name, zero or more key=value label pairs,
# and a final numeric value. Example usage:
#   ./metrics-receiver.sh send_metric my_metric foo=bar baz=qux 42
# This will generate and push a Prometheus metric line like:
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

  # Everything except the last argument is treated as a label "key=value" pair
  local labels=()
  while (( $# > 1 )); do
    labels+=( "$1" )
    shift
  done

  # The last argument is the numeric value
  local value="$1"

  # Build up a label string for Prometheus
  local label_string=""
  if [ ${#labels[@]} -gt 0 ]; then
    label_string="{"
    for (( i=0; i<${#labels[@]}; i++ )); do
      local kv="${labels[$i]}"
      local key="${kv%%=*}"
      local val="${kv#*=}"
      # Ensure we properly escape quotes or special characters if needed
      label_string+="${key}=\"${val}\""
      if [ $i -lt $(( ${#labels[@]} - 1 )) ]; then
        label_string+=","
      fi
    done
    label_string+="}"
  fi

  # Construct the metric line that Prometheus expects
  local metric_line="${metric_name}${label_string} ${value}"

  # Write to a temporary file
  local temp_file
  temp_file="$(mktemp)"
  echo "$metric_line" > "$temp_file"

  echo "Pushing metric: $metric_line"
  # Push the metric to the push gateway
  curl --silent --data-binary @"$temp_file" "${PUSH_GW_URL}"

  # Clean up
  rm "$temp_file"
}

# Allow the script itself to be called with a function name, e.g.
#   ./metrics-receiver.sh send_metric my_metric foo=bar 123
# so that the shell calls the function above.
"$@"
