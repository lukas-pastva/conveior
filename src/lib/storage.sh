# shellcheck shell=bash
# conveior - S3 storage via rclone.
# Config keys (under config:): bucket_name, s3_url, s3_key, s3_secret, s3_region (default auto),
# use_path_style (default false), s3_provider (default AWS), retention_days (optional).
# bucket_type is accepted for compatibility; every value is handled by rclone.

BUCKET=""
RCLONE=()
RETENTION_DAYS=""

storage_init() {
  BUCKET="$(cfg .config.bucket_name)"
  [[ -n "$BUCKET" ]] || die "config.bucket_name is missing"

  local type url key secret region provider path_style conf
  type="$(cfg .config.bucket_type S3_RCLONE)"
  case "$type" in
    S3_RCLONE) ;;
    S3|S3_V4|S3_FS) warn "bucket_type '$type' is legacy, uploading via rclone (S3_RCLONE)" ;;
    *) die "bucket_type '$type' is not supported (S3 via rclone only)" ;;
  esac

  url="$(cfg .config.s3_url)"
  [[ -n "$url" ]] || die "config.s3_url is missing"
  [[ "$url" == http://* || "$url" == https://* ]] || url="https://${url}"
  key="$(cfg .config.s3_key)"
  secret="$(cfg .config.s3_secret)"
  [[ -n "$key" && -n "$secret" ]] || die "config.s3_key / config.s3_secret are missing"
  region="$(cfg .config.s3_region auto)"
  provider="$(cfg .config.s3_provider AWS)"
  path_style="$(cfg .config.use_path_style false)"
  RETENTION_DAYS="$(cfg .config.retention_days)"
  if [[ -n "$RETENTION_DAYS" && ! "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    die "config.retention_days must be a whole number of days"
  fi

  mkdir -p "$WORK_ROOT"
  conf="$WORK_ROOT/rclone.conf"
  (
    umask 077
    {
      printf '[s3]\ntype = s3\nenv_auth = false\nprovider = %s\nregion = %s\n' "$provider" "$region"
      printf 'access_key_id = %s\nsecret_access_key = %s\nendpoint = %s\n' "$key" "$secret" "$url"
      [[ "$path_style" == "true" ]] && printf 'force_path_style = true\n'
    } > "$conf"
  )
  RCLONE=(rclone --config "$conf" --s3-no-check-bucket -q --retries 1)
}

# storage_upload <local file> <path inside bucket>
storage_upload() {
  log "Uploading ${BUCKET}/$2 ($(human_size "$(file_size "$1")"))"
  retry "upload $2" "${RCLONE[@]}" copyto "$1" "s3:${BUCKET}/$2"
}

# storage_download <path inside bucket> <local file>
storage_download() {
  log "Downloading ${BUCKET}/$1"
  retry "download $1" "${RCLONE[@]}" copyto "s3:${BUCKET}/$1" "$2"
}

# storage_list <prefix>  - "<modtime>;<size>;<name>" per object, newest last
storage_list() {
  "${RCLONE[@]}" lsf --files-only --format tsp --separator ';' "s3:${BUCKET}/$1" 2>/dev/null | sort
}

# storage_latest <prefix> - name of the newest object under prefix
storage_latest() {
  storage_list "$1" | tail -n 1 | cut -d';' -f3
}

# storage_prune <prefix> - deletes objects older than retention_days (no-op when unset)
storage_prune() {
  [[ -n "$RETENTION_DAYS" ]] || return 0
  log "Pruning ${BUCKET}/$1 older than ${RETENTION_DAYS} days"
  "${RCLONE[@]}" delete --min-age "${RETENTION_DAYS}d" "s3:${BUCKET}/$1" || warn "prune of $1 failed (backup itself is fine)"
  return 0
}

storage_check() {
  "${RCLONE[@]}" lsd "s3:${BUCKET}" >/dev/null
}
