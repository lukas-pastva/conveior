#!/bin/bash

# Define variables
POD_NAME="weblate-postgresql-0"
NAMESPACE="weblate"
BACKUP_FILE="backup.sql"
DATABASE_ENV_VAR="POSTGRES_DATABASE"  # This will fetch the database name
PASSWORD_ENV_VAR="POSTGRES_PASSWORD"  # Not directly used, password fetched from secret instead
CONTAINER_NAME="postgresql"  # Corrected container name
USERNAME="postgres"  # Username for PostgreSQL
USERNAME="postgres"  # TODO

# Copy backup file to the pod
kubectl cp "./$BACKUP_FILE" "$NAMESPACE/$POD_NAME:/tmp/$BACKUP_FILE"

DATABASE_NAME=$(kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- printenv $DATABASE_ENV_VAR)
echo "DATABASE_NAME: $DATABASE_NAME"
DATABASE_PASSWORD=$(kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- printenv $PASSWORD_ENV_VAR)
echo "DATABASE_PASSWORD: $DATABASE_PASSWORD"

# Import backup into PostgreSQL
kubectl exec $POD_NAME --namespace=$NAMESPACE -c $CONTAINER_NAME -- bash -c "PGPASSWORD=$DATABASE_PASSWORD psql -U $USERNAME -d $DATABASE_NAME -f /tmp/$BACKUP_FILE"

echo "Database import completed."
