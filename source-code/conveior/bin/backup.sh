#!/bin/bash
export $(xargs -0 -a "/proc/1/environ")

sleep $(shuf -i 10-30 -n1)

backup-mysql.sh
backup-pgsql.sh
backup-files.sh