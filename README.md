# conveior

Small bash tool that backs up **MySQL/MariaDB services** and **directories inside pods** from a
Kubernetes cluster into an **S3 bucket**, and restores them again. It runs as a container
(typically an Argo Workflows / CronJob step) and is driven by one YAML config file.

- MySQL: `mysqldump` over the network against the service, one zip per target, optionally password protected
- Files: `tar` streamed out of a running pod over `kubectl exec`, zipped, uploaded
- Storage: any S3 compatible endpoint via `rclone`, optional retention
- Every step is retried, one failing target does not stop the others, the run ends with a summary
  table and a non-zero exit code when something failed (so the surrounding workflow can retry)
- Pure bash + `kubectl`, `yq`, `rclone`, `zip`, `mariadb-client`. Image: `ghcr.io/lukas-pastva/conveior`

Version 2 (2026-10) is a rewrite. Docker mode, PostgreSQL, Elasticsearch, volume backups,
Prometheus metrics, the cron scheduler and the Go HTTP server were removed; the config format and
the bucket layout stayed the same, existing backups and config secrets keep working.

## Config

See [examples/config.yaml](examples/config.yaml). The file is read from `CONFIG_FILE_DIR`
(default `/home/config.yaml`) or inline from `CONFIG_FILE_CONTENTS`.

```yaml
config:
  bucket_name: "my-backups"
  s3_url: "https://hel1.your-objectstorage.com"
  s3_key: "ACCESS_KEY"
  s3_secret: "SECRET_KEY"
  s3_region: "hel1"
  use_path_style: true
  # retention_days: 30
  backups:
    dbs_mysql:
      - name: "shop-sql"          # service shop-sql.shop.svc.cluster.local:3306
        namespace: "shop"
        password: "secretPass"
        encrypt: true             # zip protected with the DB password
    files:
      - name: "shop"              # pod shop-<hash>-<id> or shop-<n>
        namespace: "shop"
        path: "/app/media"
```

Bucket layout: `backup-mysql/<name>/<name>-<date>.sql.zip` and `backup-file/<name>/<name>[-<path>]-<date>.zip`.

## Commands

```
conveior backup                                   run every backup from the config
conveior check                                    validate config, bucket and kubectl access
conveior list mysql|files <name>                  list stored backups of one target
conveior restore-mysql <name> <object|latest> [--drop]
conveior restore-files <name> <object|latest> [--clean] [--path <dir>]
```

The container entrypoint runs `conveior <args>`, or `conveior backup` without arguments.
With `EVENT_DRIVEN` set and no arguments it only prints the version (compatibility with
workflow scripts that call `entrypoint.sh` and then `backup.sh`).

### Kubernetes

The pod needs a ServiceAccount allowed to `get/list pods` and `create pods/exec` in the
namespaces of the `files` targets. MySQL targets only need network access to the service
(port 3306); no exec into the database pod is done. Example Argo Workflows step:

```yaml
container:
  image: ghcr.io/lukas-pastva/conveior:<tag>
  command: ["conveior", "backup"]
  env:
    - name: CONFIG_FILE_DIR
      value: /tmp/config/config.yaml
  volumeMounts:
    - name: config
      mountPath: /tmp/config/config.yaml
      subPath: config.yaml
volumes:
  - name: config
    secret:
      secretName: backup-config
```

### Restore

```
kubectl -n argo-workflows run restore -it --rm --image=ghcr.io/lukas-pastva/conveior:<tag> \
  --overrides='{"spec":{"serviceAccountName":"...","volumes":[...]}}' -- \
  conveior restore-mysql shop-sql latest --drop
```

`restore-files ... --clean` empties the target directory in the pod before copying the backup in.

## Development

```
bash tests/smoke.sh          # stubbed kubectl / mysql / rclone, needs yq, zip, unzip
shellcheck -x src/bin/conveior src/lib/*.sh tests/*.sh
docker build -t conveior ./src
```

CI builds and pushes `ghcr.io/lukas-pastva/conveior:<git sha>` and `:latest` on every push to `main`.

## License

Apache License 2.0. Contact: info@lukaspastva.sk
