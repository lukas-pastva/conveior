# shellcheck shell=bash
# conveior - shared helpers: logging, config access, retry, work dirs, result summary.
# Sourced by bin/conveior. Requires bash 4+, yq (mikefarah v4), zip/unzip.

CONVEIOR_VERSION=2.1.0

# Config file: CONFIG_FILE_DIR is the historical variable name (it points to a file), kept for compatibility.
CONFIG_FILE="${CONFIG_FILE_DIR:-${CONFIG_FILE:-/home/config.yaml}}"
WORK_ROOT="${CONVEIOR_WORK_DIR:-/tmp/conveior}"
RETRY_ATTEMPTS="${CONVEIOR_RETRY_ATTEMPTS:-3}"
RETRY_SLEEP="${CONVEIOR_RETRY_SLEEP:-10}"
# shellcheck disable=SC2034  # used by backup.sh for file names
DATE="$(date -u +"%Y-%m-%dT%H-%M-%SZ")"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
log()  { printf '%s # %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
warn() { log "WARN: $*" >&2; }
err()  { log "ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

banner() {
  cat <<'EOF'
  ___ ___  _ ____   _____(_) ___  ___
 / __/ _ \|  _ \ \ / / _ \ |/ _ \|  _|
| (_| (_) | | | \ V /  __/ | (_) | |
 \___\___/|_| |_|\_/ \___|_|\___/|_|
EOF
  log "conveior ${CONVEIOR_VERSION}"
}

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
# config_load: makes sure the config file exists (CONFIG_FILE_CONTENTS env may carry it inline).
config_load() {
  if [[ -n "${CONFIG_FILE_CONTENTS:-}" ]]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    printf '%s\n' "$CONFIG_FILE_CONTENTS" > "$CONFIG_FILE"
  fi
  [[ -r "$CONFIG_FILE" ]] || die "config file not found: $CONFIG_FILE (set CONFIG_FILE_DIR or CONFIG_FILE_CONTENTS)"
  yq -e '.config' "$CONFIG_FILE" >/dev/null 2>&1 || die "config file $CONFIG_FILE has no top-level 'config:' key"
  local orchestrator
  orchestrator="$(cfg .config.container_orchestrator kubernetes)"
  [[ "$orchestrator" == "kubernetes" ]] || die "container_orchestrator '$orchestrator' is not supported, only kubernetes"
}

# cfg <yq expression> [default]  - scalar value, default when missing/null
cfg() {
  local v
  v="$(yq -r "$1 // \"\"" "$CONFIG_FILE")" || die "cannot evaluate '$1' in $CONFIG_FILE"
  if [[ -z "$v" || "$v" == "null" ]]; then
    printf '%s' "${2-}"
  else
    printf '%s' "$v"
  fi
}

# cfg_len <yq expression> - number of items in a list (0 when missing)
cfg_len() {
  local n
  n="$(yq -r "$1 | length" "$CONFIG_FILE" 2>/dev/null)" || n=0
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# cfg_list <yq expression> - prints one item per line; accepts a scalar or a list
cfg_list() {
  yq -r "$1 | select(. != null) | (if tag == \"!!seq\" then .[] else . end)" "$CONFIG_FILE" 2>/dev/null | sed '/^$/d'
}

# cfg_index <list expression> <name> - index of the item with .name == <name>, or fail
cfg_index() {
  local i n
  n="$(cfg_len "$1")"
  for ((i = 0; i < n; i++)); do
    [[ "$(cfg "$1[$i].name")" == "$2" ]] && { printf '%s' "$i"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------------------
# retry <description> <command...>
# ---------------------------------------------------------------------------
retry() {
  local desc="$1" attempt=1 rc
  shift
  while true; do
    "$@" && return 0
    rc=$?
    if (( attempt >= RETRY_ATTEMPTS )); then
      err "$desc failed after $attempt attempt(s) (rc=$rc)"
      return "$rc"
    fi
    warn "$desc failed (rc=$rc), attempt $attempt/$RETRY_ATTEMPTS, retrying in ${RETRY_SLEEP}s"
    sleep "$RETRY_SLEEP"
    attempt=$((attempt + 1))
  done
}

# ---------------------------------------------------------------------------
# work dirs
# ---------------------------------------------------------------------------
workdir_new() {
  mkdir -p "$WORK_ROOT"
  mktemp -d "$WORK_ROOT/${1:-work}.XXXXXX"
}

workdir_rm() {
  [[ -n "$1" && "$1" == "$WORK_ROOT"/* ]] && rm -rf -- "$1"
}

workdir_cleanup_all() {
  [[ -d "$WORK_ROOT" ]] && rm -rf -- "$WORK_ROOT"
  return 0
}

# ---------------------------------------------------------------------------
# files
# ---------------------------------------------------------------------------
file_size() { wc -c < "$1" | tr -d ' '; }

human_size() {
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
  }'
}

# zip_file <zip path> <password or empty> <file...>   (stores file names only, no directories)
zip_file() {
  local out="$1" pass="$2"
  shift 2
  if [[ -n "$pass" ]]; then
    zip -q -j -P "$pass" "$out" "$@"
  else
    zip -q -j "$out" "$@"
  fi
}

# zip_dir <zip path> <directory>   (archive the directory contents, paths relative to it)
zip_dir() {
  ( cd "$2" && zip -q -r "$1" . )
}

# unzip_file <zip path> <destination dir> <password or empty>
unzip_file() {
  if [[ -n "$3" ]]; then
    unzip -q -o -P "$3" "$1" -d "$2"
  else
    unzip -q -o "$1" -d "$2"
  fi
}

# ---------------------------------------------------------------------------
# results: record <OK|FAIL|SKIP> <kind> <name> <detail>; summary prints a table and returns #failures
# ---------------------------------------------------------------------------
RESULTS=()

record() {
  RESULTS+=("$1|$2|$3|$4")
  case "$1" in
    OK)   log "$2 $3: OK ($4)" ;;
    SKIP) log "$2 $3: skipped ($4)" ;;
    *)    err "$2 $3: FAILED ($4)" ;;
  esac
}

summary() {
  local r status kind name detail failed=0
  printf '\n%-6s %-6s %-30s %s\n' STATUS KIND NAME DETAIL
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r status kind name detail <<< "$r"
    printf '%-6s %-6s %-30s %s\n' "$status" "$kind" "$name" "$detail"
    [[ "$status" == "FAIL" ]] && failed=$((failed + 1))
  done
  printf '\n'
  if (( failed > 0 )); then
    err "$failed of ${#RESULTS[@]} target(s) failed"
  else
    log "all ${#RESULTS[@]} target(s) finished"
  fi
  return "$failed"
}
