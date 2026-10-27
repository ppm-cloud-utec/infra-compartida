#!/usr/bin/env bash
# Carga los secretos en SSM Parameter Store. Correr UNA VEZ antes del primer deploy.
# Los valores no se versionan: se generan aqui y quedan solo en SSM.
set -euo pipefail

REGION=us-east-1
gen() { openssl rand -base64 24 | tr -d '/+=' | head -c 24; }

poner() {
  aws ssm put-parameter --region "$REGION" --name "$1" --value "$2" \
    --type SecureString --overwrite >/dev/null
  echo "  $1"
}

echo "Cargando parametros en SSM ($REGION):"
poner /ppm/jwt-secret        "$(gen)"
poner /ppm/rds/master-user   "ppmadmin"
poner /ppm/rds/master-password "$(gen)"

for ms in portafolios recursos presupuestos; do
  poner "/ppm/$ms/db-user"     "ppm_$ms"
  poner "/ppm/$ms/db-password" "$(gen)"
done

echo
echo "Listo. Para verlos: aws ssm get-parameter --name /ppm/jwt-secret --with-decryption"
