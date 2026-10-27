#!/usr/bin/env bash
# Crea las 3 databases, sus schemas por tenant y el usuario de cada microservicio.
# Correr DESPUES de `sls deploy`, cuando el RDS ya existe.
set -euo pipefail

REGION=us-east-1
STAGE=${1:-dev}

param() { aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
            --query Parameter.Value --output text; }

HOST=$(aws cloudformation describe-stacks --region "$REGION" \
  --stack-name "infra-compartida-$STAGE" \
  --query "Stacks[0].Outputs[?OutputKey=='RdsEndpoint'].OutputValue" --output text)
ADMIN=$(param /ppm/rds/master-user)
export PGPASSWORD=$(param /ppm/rds/master-password)

psql_admin() { psql -h "$HOST" -U "$ADMIN" -d "${2:-postgres}" -v ON_ERROR_STOP=1 -c "$1"; }

for ms in portafolios recursos presupuestos; do
  DB="ppm_$ms"
  USER="ppm_$ms"
  PASS=$(param "/ppm/$ms/db-password")

  echo "== $DB =="
  psql_admin "CREATE DATABASE $DB;" || echo "   (ya existia)"
  psql_admin "CREATE USER $USER WITH PASSWORD '$PASS';" || echo "   (usuario ya existia)"
  psql_admin "GRANT ALL PRIVILEGES ON DATABASE $DB TO $USER;"

  # Un schema por tenant: patron Single Database, Multiple Schemas
  for t in t_acme t_globex t_initech; do
    psql_admin "CREATE SCHEMA IF NOT EXISTS $t AUTHORIZATION $USER;" "$DB"
    echo "   schema $t"
  done
  # El usuario del microservicio NO debe ver el schema public ni otras databases
  psql_admin "REVOKE ALL ON SCHEMA public FROM $USER;" "$DB" || true
done

echo
echo "Listo. Host: $HOST"
