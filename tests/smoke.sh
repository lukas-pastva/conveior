#!/usr/bin/env bash
# Smoke test with stubbed kubectl / mysql / mysqldump / rclone. Needs bash, yq, zip, unzip, tar.
#   bash tests/smoke.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
export PATH="$HERE/stubs:$PATH"
export STUB_DIR; STUB_DIR="$(mktemp -d /tmp/conveior-test.XXXXXX)"
export CONVEIOR_WORK_DIR="$STUB_DIR/work"
export CONVEIOR_RETRY_SLEEP=0
export CONFIG_FILE_DIR="$STUB_DIR/config.yaml"
CONVEIOR="$REPO/src/bin/conveior"
chmod +x "$CONVEIOR" "$HERE"/stubs/*
trap 'rm -rf "$STUB_DIR"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
assert() { if eval "$2"; then ok "$1"; else fail "$1 [$2]"; fi; }

# --- fixtures -----------------------------------------------------------------
printf 'secretPass\n' > "$STUB_DIR/expected-password"
printf 'information_schema\nmysql\nperformance_schema\nsys\nshop\nshop_logs\n' > "$STUB_DIR/databases"
printf 'shop-7fc756894f-fwcdk\nshop-sql-0\nother-app-5d8f9c7b6-abcde\n' > "$STUB_DIR/pods"
mkdir -p "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/sub" "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/empty"
printf 'hello\n' > "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/a.txt"
head -c 300000 /dev/urandom > "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/sub/blob.bin"

cat > "$CONFIG_FILE_DIR" <<'EOF'
config:
  container_orchestrator: kubernetes
  bucket_type: "S3_RCLONE"
  bucket_name: "test-bucket"
  s3_url: "s3.example.test"
  s3_key: "KEY"
  s3_secret: "SECRET"
  s3_region: "hel1"
  use_path_style: true
  retention_days: 30
  backups:
    dbs_mysql:
      - name: "shop-sql"
        namespace: "shop"
        password: "secretPass"
        encrypt: true
      - name: "plain-sql"
        namespace: "shop"
        host: "db.example.test"
        port: 3307
        username: "backup"
        password: "secretPass"
        databases: ["onlythis"]
      - name: "nopass-sql"
        namespace: "shop"
    files:
      - name: "shop"
        namespace: "shop"
        path:
          - "/app/media"
          - "/app/empty"
      - name: "missing"
        namespace: "shop"
        path: "/data"
EOF

echo "== backup (one mysql target without password must fail, the rest must succeed)"
set +e
STUB_FAIL_TAR_ONCE=1 STUB_FAIL_MYSQL_ONCE=1 "$CONVEIOR" backup > "$STUB_DIR/backup.out" 2>&1
rc=$?
set -e
sed 's/^/    /' "$STUB_DIR/backup.out"
assert "exit code is 2 (nopass-sql and missing failed)" "[[ $rc -eq 2 ]]"
assert "shop-sql OK, encrypted"            "grep -q 'OK     mysql  shop-sql .*2 db(s).*encrypted' '$STUB_DIR/backup.out'"
assert "plain-sql OK (explicit databases)"  "grep -q 'OK     mysql  plain-sql .*1 db(s)' '$STUB_DIR/backup.out'"
assert "nopass-sql FAIL"                    "grep -q 'FAIL   mysql  nopass-sql' '$STUB_DIR/backup.out'"
assert "files shop OK with 2 paths"         "grep -q 'OK     files  shop .*2 path(s)' '$STUB_DIR/backup.out'"
assert "files missing FAIL (no pod)"        "grep -q 'FAIL   files  missing .*no running pod' '$STUB_DIR/backup.out'"
assert "tar was retried after truncated stream" "grep -q 'copy shop-7fc756894f-fwcdk:/app/media failed (rc=1), attempt 1/3' '$STUB_DIR/backup.out'"
assert "mysql list was retried"             "grep -q 'list databases on shop-sql.shop.svc.cluster.local failed' '$STUB_DIR/backup.out'"
assert "empty path skipped"                 "grep -q '/app/empty is empty, skipping' '$STUB_DIR/backup.out'"
assert "password not on mysqldump command line" "! grep -q 'secretPass' '$STUB_DIR/mysql.log'"
assert "mysqldump used --single-transaction and both dbs" "grep -q -- '--single-transaction.*--databases shop shop_logs' '$STUB_DIR/mysql.log'"
assert "plain-sql used host/port/user from config" "grep -q 'host=db.example.test' '$STUB_DIR/work/'*/my.cnf 2>/dev/null || grep -q 'onlythis' '$STUB_DIR/mysql.log'"
assert "rclone config has endpoint, region, path style" "grep -q 'endpoint = https://s3.example.test' '$STUB_DIR/rclone.conf.seen' && grep -q 'region = hel1' '$STUB_DIR/rclone.conf.seen' && grep -q 'force_path_style = true' '$STUB_DIR/rclone.conf.seen'"
assert "retention prune called for shop-sql" "grep -q 'delete --min-age=30d s3:test-bucket/backup-mysql/shop-sql' '$STUB_DIR/rclone-delete.log'"
mysql_zip="$(ls "$STUB_DIR"/bucket/backup-mysql/shop-sql/*.sql.zip | head -n1)"
assert "mysql zip uploaded"                 "[[ -f '$mysql_zip' ]]"
assert "mysql zip is encrypted (wrong password fails)" "! unzip -qq -o -P wrong '$mysql_zip' -d '$STUB_DIR/x1' >/dev/null 2>&1"
assert "mysql zip opens with DB password and holds the dump" "unzip -qq -o -P secretPass '$mysql_zip' -d '$STUB_DIR/x2' && grep -q 'dump of shop_logs' '$STUB_DIR'/x2/*.sql"
assert "mysql zip stores the file without directories" "! unzip -Z1 '$mysql_zip' | grep -q /"
files_zip="$(ls "$STUB_DIR"/bucket/backup-file/shop/shop-app_media-*.zip | head -n1)"
assert "files zip uploaded with path suffix" "[[ -f '$files_zip' ]]"
assert "files zip has the nested content"   "unzip -Z1 '$files_zip' | grep -q 'sub/blob.bin' && unzip -Z1 '$files_zip' | grep -q 'a.txt'"
assert "no files zip for the empty path"    "! ls '$STUB_DIR'/bucket/backup-file/shop/shop-app_empty-* >/dev/null 2>&1"
assert "work dir cleaned up"                "[[ ! -d '$STUB_DIR/work' || -z \"\$(ls -A '$STUB_DIR/work')\" ]]"

echo "== check"
assert "check succeeds" "'$CONVEIOR' check > '$STUB_DIR/check.out' 2>&1 && grep -q 'bucket test-bucket: reachable' '$STUB_DIR/check.out'"

echo "== list"
assert "list mysql shows the zip" "'$CONVEIOR' list mysql shop-sql 2>&1 | grep -q '$(basename "$mysql_zip")'"
assert "list files shows the zip" "'$CONVEIOR' list files shop 2>&1 | grep -q '$(basename "$files_zip")'"

echo "== restore-mysql latest --drop"
set +e; "$CONVEIOR" restore-mysql shop-sql latest --drop > "$STUB_DIR/rm.out" 2>&1; rc=$?; set -e
sed 's/^/    /' "$STUB_DIR/rm.out"
assert "restore-mysql exit 0"               "[[ $rc -eq 0 ]]"
assert "user databases dropped, system ones not" "grep -q 'DROP DATABASE \`shop\`' '$STUB_DIR/mysql-drops.log' && ! grep -q 'mysql\`' '$STUB_DIR/mysql-drops.log'"
assert "dump imported"                      "grep -q 'dump of shop_logs' '$STUB_DIR/mysql-import.sql'"
assert "unknown target is rejected"         "! '$CONVEIOR' restore-mysql nope latest >/dev/null 2>&1"

echo "== restore-files latest --clean"
printf 'stale\n' > "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/stale.txt"
rm -f "$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/a.txt"
set +e; "$CONVEIOR" restore-files shop latest --clean > "$STUB_DIR/rf.out" 2>&1; rc=$?; set -e
sed 's/^/    /' "$STUB_DIR/rf.out"
assert "restore-files exit 0"               "[[ $rc -eq 0 ]]"
assert "restored file is back"              "[[ -f '$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/a.txt' ]]"
assert "stale file removed by --clean"      "[[ ! -f '$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/stale.txt' ]]"
assert "blob restored intact"               "cmp -s '$STUB_DIR/podfs/shop-7fc756894f-fwcdk/app/media/sub/blob.bin' <(unzip -p '$files_zip' sub/blob.bin)"

echo "== entrypoint / misc"
assert "version prints"                     "'$CONVEIOR' version | grep -q '^conveior '"
assert "unknown command exits 2"            "'$CONVEIOR' bogus >/dev/null 2>&1; [[ \$? -eq 2 ]]"
assert "docker orchestrator is rejected"    "sed 's/kubernetes/docker/' '$CONFIG_FILE_DIR' > '$STUB_DIR/docker.yaml' && ! CONFIG_FILE_DIR='$STUB_DIR/docker.yaml' '$CONVEIOR' check >/dev/null 2>&1"
assert "CONFIG_FILE_CONTENTS is honoured"   "CONFIG_FILE_DIR='$STUB_DIR/inline.yaml' CONFIG_FILE_CONTENTS=\"\$(cat '$CONFIG_FILE_DIR')\" '$CONVEIOR' check >/dev/null 2>&1 && [[ -f '$STUB_DIR/inline.yaml' ]]"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
