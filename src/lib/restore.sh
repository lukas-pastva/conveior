# shellcheck shell=bash
# conveior - restore MySQL dumps and pod files from the bucket.
#
#   conveior list mysql|files <name>
#   conveior restore-mysql <name> <object|latest> [--drop]
#   conveior restore-files <name> <object|latest> [--clean] [--path <dir>]
#
# <object> is the file name inside backup-mysql/<name>/ or backup-file/<name>/ (as printed by list).

# resolve_object <prefix> <object|latest>
resolve_object() {
  local obj="$2"
  if [[ "$obj" == "latest" ]]; then
    obj="$(storage_latest "$1")"
    [[ -n "$obj" ]] || die "no backups found under ${BUCKET}/$1"
  fi
  printf '%s' "$obj"
}

list_backups() {
  local kind="$1" name="$2" prefix
  case "$kind" in
    mysql) prefix="backup-mysql/${name}" ;;
    files) prefix="backup-file/${name}" ;;
    *) die "list: kind must be mysql or files" ;;
  esac
  [[ -n "$name" ]] || die "list: name is required"
  log "Backups in ${BUCKET}/${prefix}:"
  storage_list "$prefix" | awk -F';' '{ printf "%s  %12s  %s\n", $1, $2, $3 }'
}

restore_mysql() {
  local name="$1" object="$2" drop=false arg idx p host port user pass encrypt dir zip f dbs db creds
  shift 2
  for arg in "$@"; do
    case "$arg" in
      --drop) drop=true ;;
      *) die "restore-mysql: unknown argument '$arg'" ;;
    esac
  done
  [[ -n "$name" && -n "$object" ]] || die "usage: conveior restore-mysql <name> <object|latest> [--drop]"
  idx="$(cfg_index .config.backups.dbs_mysql "$name")" || die "no dbs_mysql entry named '$name' in config"
  p=".config.backups.dbs_mysql[$idx]"
  host="$(cfg "$p.host" "${name}.$(cfg "$p.namespace").svc.cluster.local")"
  port="$(cfg "$p.port" 3306)"
  user="$(cfg "$p.username" root)"
  pass="$(cfg "$p.password")"
  encrypt="$(cfg "$p.encrypt" false)"
  object="$(resolve_object "backup-mysql/${name}" "$object")"

  dir="$(workdir_new "restore-mysql-${name}")"
  zip="$dir/$object"
  storage_download "backup-mysql/${name}/${object}" "$zip" || die "download failed"
  unzip_file "$zip" "$dir/sql" "$([[ "$encrypt" == "true" ]] && printf '%s' "$pass")" || die "unzip failed (wrong password?)"
  rm -f -- "$zip"

  creds="$dir/my.cnf"
  mysql_credentials "$creds" "$host" "$port" "$user" "$pass"

  if [[ "$drop" == "true" ]]; then
    dbs="$(mysql_list_databases "$creds")" || die "cannot list databases on ${host}"
    while IFS= read -r db; do
      [[ -n "$db" ]] || continue
      log "Dropping database ${db}"
      mysql --defaults-extra-file="$creds" -e "DROP DATABASE \`${db}\`" || die "drop of ${db} failed"
    done <<< "$dbs"
  fi

  while IFS= read -r f; do
    log "Importing $(basename "$f") into ${host}:${port}"
    mysql --defaults-extra-file="$creds" < "$f" || die "import of $(basename "$f") failed"
  done < <(find "$dir/sql" -type f -name '*.sql' | sort)

  workdir_rm "$dir"
  log "MySQL restore of ${name} from ${object} done"
}

restore_files() {
  local name="$1" object="$2" clean=false dest="" idx p ns container selector pod dir zip
  shift 2
  while (( $# > 0 )); do
    case "$1" in
      --clean) clean=true ;;
      --path) dest="$2"; shift ;;
      *) die "restore-files: unknown argument '$1'" ;;
    esac
    shift
  done
  [[ -n "$name" && -n "$object" ]] || die "usage: conveior restore-files <name> <object|latest> [--clean] [--path <dir>]"
  idx="$(cfg_index .config.backups.files "$name")" || die "no files entry named '$name' in config"
  p=".config.backups.files[$idx]"
  ns="$(cfg "$p.namespace")"
  container="$(cfg "$p.container")"
  selector="$(cfg "$p.selector")"
  if [[ -z "$dest" ]]; then
    dest="$(cfg_list "$p.path" | head -n 1)"
    (( $(cfg_list "$p.path" | wc -l) > 1 )) && warn "entry has several paths, restoring into the first one: ${dest} (use --path to pick another)"
  fi
  object="$(resolve_object "backup-file/${name}" "$object")"
  pod="$(k8s_find_pod "$ns" "$name" "$selector")" || die "no running pod for ${name} in ${ns}"

  dir="$(workdir_new "restore-files-${name}")"
  zip="$dir/$object"
  storage_download "backup-file/${name}/${object}" "$zip" || die "download failed"
  mkdir -p "$dir/data"
  unzip_file "$zip" "$dir/data" "" || die "unzip failed"
  rm -f -- "$zip"

  if [[ "$clean" == "true" ]]; then
    log "Cleaning ${pod}:${dest}"
    k8s_exec "$ns" "$pod" "$container" sh -c 'find "$1" -mindepth 1 -delete' sh "$dest" || die "cleanup of ${dest} failed"
  fi
  log "Copying $(du -sh "$dir/data" | cut -f1) into ${pod}:${dest}"
  k8s_dir_from_tar "$ns" "$pod" "$container" "$dir/data" "$dest" || die "copy into pod failed"

  workdir_rm "$dir"
  log "Files restore of ${name} from ${object} done"
}
