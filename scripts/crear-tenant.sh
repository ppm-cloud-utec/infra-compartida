#!/usr/bin/env bash
# Da de alta una organizacion completa lanzando la maquina de estados.
#
#   ./scripts/crear-tenant.sh t-umbrella "Umbrella Corp" farmaceutica
#
# No crea nada por su cuenta: solo arranca ppm-aprovisionar-tenant y muestra
# como va. Todo el trabajo (registro, los 3 schemas, el admin y la
# habilitacion) lo hacen las Lambdas de cada microservicio.
set -euo pipefail

REGION=us-east-1
STAGE=${STAGE:-dev}

TENANT=${1:-}
NOMBRE=${2:-}
RUBRO=${3:-}
ADMIN=${4:-}

if [ -z "$TENANT" ] || [ -z "$NOMBRE" ]; then
  echo "Uso: $0 <tenant_id> <nombre> [rubro] [admin_email]"
  echo "Ej:  $0 t-umbrella \"Umbrella Corp\" farmaceutica admin@umbrella.com"
  exit 1
fi

ARN=$(aws stepfunctions list-state-machines --region "$REGION" \
        --query "stateMachines[?name=='ppm-aprovisionar-tenant-$STAGE'].stateMachineArn" \
        --output text)
if [ -z "$ARN" ] || [ "$ARN" = "None" ]; then
  echo "No existe la maquina ppm-aprovisionar-tenant-$STAGE. Despliega infra-compartida."
  exit 1
fi

ENTRADA=$(python3 -c '
import json,sys
d={"tenant_id":sys.argv[1],"nombre":sys.argv[2]}
if sys.argv[3]: d["rubro"]=sys.argv[3]
if sys.argv[4]: d["admin_email"]=sys.argv[4]
print(json.dumps(d))' "$TENANT" "$NOMBRE" "$RUBRO" "$ADMIN")

echo "Dando de alta $TENANT ($NOMBRE)"
EJEC=$(aws stepfunctions start-execution --region "$REGION" \
         --state-machine-arn "$ARN" --input "$ENTRADA" \
         --query executionArn --output text)

printf '  ejecutando'
for _ in $(seq 1 40); do
  ESTADO=$(aws stepfunctions describe-execution --region "$REGION" \
             --execution-arn "$EJEC" --query status --output text)
  [ "$ESTADO" != "RUNNING" ] && break
  printf '.'; sleep 3
done
printf '\n'

SALIDA=$(aws stepfunctions describe-execution --region "$REGION" \
           --execution-arn "$EJEC" --query output --output text 2>/dev/null || true)

if [ "$ESTADO" = "SUCCEEDED" ]; then
  echo "LISTO. La organizacion ya aparece en el selector del login."
  python3 - "$SALIDA" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
print(f"  admin:   {d['identidad']['admin_email']}")
if d['identidad'].get('clave_en'):
    print(f"  clave:   guardada cifrada en {d['identidad']['clave_en']}")
    print( "           leela con: aws ssm get-parameter --with-decryption --name <ruta> --query Parameter.Value --output text")
for s in d.get('schemas', []):
    print(f"  schema:  {s['servicio']} -> {s['schema']} ({s['tablas']} tablas)")
print(f"  activos: {', '.join(d['publicacion']['habilitados'])}")
print(f"\n  Las Lambdas releen la lista cada 60s: espera ese minuto antes de entrar.")
PY
else
  echo "FALLO ($ESTADO). El rollback ya corrio; no quedo nada a medias."
  echo "Detalle paso a paso:"
  echo "  aws stepfunctions get-execution-history --region $REGION --execution-arn $EJEC --query 'events[?type==\`TaskFailed\`]'"
  exit 1
fi
