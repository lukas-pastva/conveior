#!/usr/bin/env bash
# Container entrypoint.
#   with arguments      -> conveior <arguments>            (docker run ... backup / check / restore-...)
#   without arguments   -> conveior backup
#   EVENT_DRIVEN set and no arguments -> print banner only; the workflow script calls backup.sh itself
#   (this is how the Argo Workflows templates invoke it: "entrypoint.sh" followed by "backup.sh").
set -euo pipefail

if (( $# > 0 )); then
  exec /usr/local/bin/conveior "$@"
fi
if [[ -n "${EVENT_DRIVEN+x}" ]]; then
  /usr/local/bin/conveior version
  exit 0
fi
exec /usr/local/bin/conveior backup
