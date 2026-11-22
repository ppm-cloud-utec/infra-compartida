#!/usr/bin/env bash
# Copia los secretos de Parameter Store a Secrets Manager.
#
# Copia, no regenera: si cambiara los valores habria que recrear las bases y
# todos los tokens vigentes dejarian de validar. Es idempotente, se puede
# correr las veces que haga falta.
#
# Lo que NO se mueve: /ppm/tenants, que es configuracion y no secreto, y
# /ppm/rds/master-*, que ademas los lee CloudFormation al crear el RDS.
set -euo pipefail
REGION=us-east-1

ssm() { aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
          --query Parameter.Value --output text; }

guardar() {  # guardar <nombre-secreto> <valor> <descripcion>
  if aws secretsmanager describe-secret --region "$REGION" --secret-id "$1" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --region "$REGION" \
      --secret-id "$1" --secret-string "$2" >/dev/null
    echo "   actualizado  $1"
  else
    aws secretsmanager create-secret --region "$REGION" \
      --name "$1" --secret-string "$2" --description "$3" >/dev/null
    echo "   creado       $1"
  fi
}

echo "Secretos de aplicacion -> Secrets Manager"
guardar "ppm/jwt-secret" "$(ssm /ppm/jwt-secret)" \
        "Clave HS256 que firma y valida los JWT de todos los tenants"

for ms in portafolios recursos presupuestos; do
  USUARIO=$(ssm "/ppm/$ms/db-user")
  CLAVE=$(ssm "/ppm/$ms/db-password")
  guardar "ppm/$ms/db" \
    "$(python3 -c 'import json,sys;print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$USUARIO" "$CLAVE")" \
    "Credenciales de ms-$ms contra su database en el RDS compartido"
done

echo
echo "Credenciales maestras del RDS -> tambien, para los scripts de administracion"
guardar "ppm/rds/master" \
  "$(python3 -c 'import json,sys;print(json.dumps({"username":sys.argv[1],"password":sys.argv[2]}))' "$(ssm /ppm/rds/master-user)" "$(ssm /ppm/rds/master-password)")" \
  "Usuario maestro del RDS. CloudFormation lo sigue leyendo de SSM al crear la instancia"

echo
echo "Listo. Los parametros de SSM se conservan a proposito:"
echo "  - /ppm/rds/master-*  los lee CloudFormation al CREAR el RDS; cambiarlos"
echo "                       por una referencia dinamica arriesga modificar la"
echo "                       instancia sin ninguna ganancia, porque ese valor"
echo "                       nunca llega a una Lambda."
echo "  - /ppm/tenants       es configuracion, no secreto."
