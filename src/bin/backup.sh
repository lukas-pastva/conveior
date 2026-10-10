#!/usr/bin/env bash
# Compatibility wrapper: older workflow scripts call "backup.sh". Same as "conveior backup".
exec /usr/local/bin/conveior backup "$@"
