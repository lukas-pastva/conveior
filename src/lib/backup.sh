# shellcheck shell=bash
# conveior - backup of MySQL/MariaDB services and files inside pods.
#
# config.backups.dbs_mysql[]:
#   name        (required) config name; also default service host prefix and backup folder
#   namespace   (required) namespace of the service
#   host        optional, default <name>.<namespace>.svc.cluster.local
#   port        optional, default 3306
#   username    optional, default root
#   password    (required)
#   databases   optional list, default all non-system databases
#   encrypt     optional, zip protected with the DB password (legacy behaviour)
#   -> uploads backup-mysql/<name>/<name>-<DATE>.sql.zip
#
# config.backups.files[]:
#   name        (required) pod name prefix (Deployment/StatefulSet name) and backup folder
#   namespace   (required)
#   path        (required) directory inside the pod, or a list of directories
#   container   optional container name
#   selector    optional label selector instead of the name prefix match
#   -> uploads backup-file/<name>/<name>[-<path>]-<DATE>.zip

MYSQL_SYSTEM_DBS='^(information_schema|mysql|performance_schema|sys)$'

backup_run() {
  local n i
  n="$(cfg_len .config.backups.dbs_mysql)"
  for ((i = 0; i < n; i++)); do backup_mysql_target "$i"; done
  n="$(cfg_len .config.backups.files)"
  for ((i = 0; i < n; i++)); do backup_files_target "$i"; done
  (( ${#RESULTS[@]} > 0 )) || warn "nothing to back up: config.backups has no dbs_mysql / files entries"
}

# ---------------------------------------------------------------------------
# MySQL
# ---------------------------------------------------------------------------

# mysql_credentials <file> <host> <port> <user> <password> - writes a client option file (keeps the password off the command line)
mysql_credentials() {
  ( umask 077; printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword=%s\n' "$2" "$3" "$4" "$5" > "$1" )
}

# mysql_list_databases <credentials file> - user databases, one per line
mysql_list_databases() {
  local out
  out="$(mysql --defaults-extra-file="$1" --batch --skip-column-names -e 'SHOW DATABASES')" || return 1
  printf '%s\n' "$out" | grep -Ev "$MYSQL_SYSTEM_DBS" || true
}

# mysql_dump <credentials file> <output file> <database...>
mysql_dump() {
  local creds="$1" out="$2"
  shift 2
  mysqldump --defaults-extra-file="$creds" --single-transaction --quick --routines --triggers \
    --extended-insert --databases "$@" > "$out"
}

backup_mysql_target() {
  local p=".config.backups.dbs_mysql[$1]"
  local name ns host port user pass encrypt dbs dir creds dump zip count
  name="$(cfg "$p.name")"
  ns="$(cfg "$p.namespace")"
  host="$(cfg "$p.host" "${name}.${ns}.svc.cluster.local")"
  port="$(cfg "$p.port" 3306)"
  user="$(cfg "$p.username" root)"
  pass="$(cfg "$p.password")"
  encrypt="$(cfg "$p.encrypt" false)"

  log "MySQL ${name} (${host}:${port})"
  if [[ -z "$name" || -z "$ns" ]]; then record FAIL mysql "${name:-#$1}" "name/namespace missing in config"; return; fi
  if [[ -z "$pass" ]]; then record FAIL mysql "$name" "no password in config"; return; fi

  dir="$(workdir_new "mysql-${name}")"
  creds="$dir/my.cnf"
  mysql_credentials "$creds" "$host" "$port" "$user" "$pass"

  dbs="$(cfg_list "$p.databases")"
  if [[ -z "$dbs" ]]; then
    if ! dbs="$(retry "list databases on ${host}" mysql_list_databases "$creds")"; then
      record FAIL mysql "$name" "cannot connect / list databases on ${host}:${port}"
      workdir_rm "$dir"; return
    fi
  fi
  if [[ -z "$dbs" ]]; then
    record SKIP mysql "$name" "no user databases"
    workdir_rm "$dir"; return
  fi
  count="$(printf '%s\n' "$dbs" | sed '/^$/d' | wc -l | tr -d ' ')"
  log "Databases: $(printf '%s' "$dbs" | tr '\n' ' ')"

  dump="$dir/${name}-${DATE}.sql"
  # shellcheck disable=SC2086
  if ! retry "mysqldump ${name}" mysql_dump "$creds" "$dump" $dbs; then
    record FAIL mysql "$name" "mysqldump failed"
    workdir_rm "$dir"; return
  fi

  zip="${dump}.zip"
  if ! zip_file "$zip" "$([[ "$encrypt" == "true" ]] && printf '%s' "$pass")" "$dump"; then
    record FAIL mysql "$name" "zip failed"
    workdir_rm "$dir"; return
  fi
  rm -f -- "$dump"

  if ! storage_upload "$zip" "backup-mysql/${name}/$(basename "$zip")"; then
    record FAIL mysql "$name" "upload failed"
    workdir_rm "$dir"; return
  fi
  storage_prune "backup-mysql/${name}"
  record OK mysql "$name" "${count} db(s), $(human_size "$(file_size "$zip")")$([[ "$encrypt" == "true" ]] && printf ', encrypted')"
  workdir_rm "$dir"
}

# ---------------------------------------------------------------------------
# files
# ---------------------------------------------------------------------------
backup_files_target() {
  local p=".config.backups.files[$1]"
  local name ns container selector paths pod path suffix dir zip total=0 failed=0 n
  name="$(cfg "$p.name")"
  ns="$(cfg "$p.namespace")"
  container="$(cfg "$p.container")"
  selector="$(cfg "$p.selector")"
  paths="$(cfg_list "$p.path")"

  log "Files ${name} (${ns})"
  if [[ -z "$name" || -z "$ns" || -z "$paths" ]]; then record FAIL files "${name:-#$1}" "name/namespace/path missing in config"; return; fi

  if ! pod="$(k8s_find_pod "$ns" "$name" "$selector")"; then
    record FAIL files "$name" "no running pod found in ${ns}"
    return
  fi
  n="$(printf '%s\n' "$paths" | wc -l | tr -d ' ')"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    suffix=""
    (( n > 1 )) && suffix="-$(printf '%s' "$path" | sed 's#^/##; s#/*$##; s#/#_#g')"
    log "Copying ${pod}:${path}"

    if k8s_dir_empty "$ns" "$pod" "$container" "$path"; then
      log "${pod}:${path} is empty, skipping"
      continue
    fi

    dir="$(workdir_new "files-${name}")"
    mkdir -p "$dir/data"
    if ! retry "copy ${pod}:${path}" k8s_tar_to_dir "$ns" "$pod" "$container" "$path" "$dir/data"; then
      failed=$((failed + 1)); workdir_rm "$dir"; continue
    fi

    zip="$dir/${name}${suffix}-${DATE}.zip"
    if ! zip_dir "$zip" "$dir/data"; then
      err "zip of ${pod}:${path} failed"
      failed=$((failed + 1)); workdir_rm "$dir"; continue
    fi
    rm -rf -- "$dir/data"

    if ! storage_upload "$zip" "backup-file/${name}/$(basename "$zip")"; then
      failed=$((failed + 1)); workdir_rm "$dir"; continue
    fi
    total=$((total + $(file_size "$zip")))
    workdir_rm "$dir"
  done <<< "$paths"

  storage_prune "backup-file/${name}"
  if (( failed > 0 )); then
    record FAIL files "$name" "${failed} of ${n} path(s) failed (pod ${pod})"
  elif (( total == 0 )); then
    record SKIP files "$name" "all paths empty (pod ${pod})"
  else
    record OK files "$name" "${n} path(s), $(human_size "$total") (pod ${pod})"
  fi
}
