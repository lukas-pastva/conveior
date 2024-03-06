#!/bin/bash

# Define variables
POD_NAME="weblate-postgresql-0"
NAMESPACE="weblate"
BACKUP_FILE="backup.sql"
DATABASE_ENV_VAR="POSTGRES_DATABASE"
PASSWORD_ENV_VAR="POSTGRES_PASSWORD"
CONTAINER_NAME="postgresql"

# Copy backup file to the pod
kubectl cp "./$BACKUP_FILE" "$NAMESPACE/$POD_NAME:/tmp/$BACKUP_FILE"

# Retrieve database name and password from pod's environment variables
DATABASE_NAME=$(kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- printenv $DATABASE_ENV_VAR)
echo "DATABASE_NAME: $DATABASE_NAME"
DATABASE_PASSWORD=$(kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- printenv $PASSWORD_ENV_VAR)
echo "DATABASE_PASSWORD: $DATABASE_PASSWORD"

# Import backup into PostgreSQL
kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- bash -c "PGPASSWORD=$DATABASE_PASSWORD psql -U $DATABASE_NAME -d $DATABASE_NAME -f /tmp/$BACKUP_FILE"

echo "Database import completed."
