#!/usr/bin/env bash
# Demuestra el manejo de fallos: un evento que el worker no puede procesar
# se reintenta 3 veces y termina en la DLQ, que dispara una alarma de CloudWatch.
#
#   ./scripts/simular-fallo.sh            envia el evento y sigue su recorrido
#   ./scripts/simular-fallo.sh --limpiar  vacia la DLQ (dejarla en 0 para verificar-sistema.sh)
#
# El evento es recurso.asignado con un recurso_id que no es un numero. El worker
# de ms-presupuestos falla al convertirlo, la transaccion hace rollback y no se
# guarda nada. Se envia directo a la cola de presupuestos para no ensuciar el
# data lake con un evento falso.
set -euo pipefail

REGION=us-east-1
STAGE=${STAGE:-dev}
COLA=$(aws sqs get-queue-url --region $REGION --queue-name ppm-cola-presupuestos-$STAGE --query QueueUrl --output text)
DLQ=$(aws sqs get-queue-url --region $REGION --queue-name ppm-cola-presupuestos-dlq-$STAGE --query QueueUrl --output text)

contar() {
  aws sqs get-queue-attributes --region $REGION --queue-url "$1" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --query "Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible]" --output text \
    | awk '{print $1+$2}'
}

if [ "${1:-}" = "--limpiar" ]; then
  aws sqs purge-queue --region $REGION --queue-url "$DLQ"
  echo "DLQ de presupuestos vaciada (la purga tarda hasta 60 s en reflejarse)."
  exit 0
fi

EVENTO_ID=$(python3 -c 'import uuid;print(uuid.uuid4())')
CUERPO=$(python3 - "$EVENTO_ID" <<'PY'
import json, sys, datetime
print(json.dumps({
    "evento_id": sys.argv[1], "tipo": "recurso.asignado", "version": 1,
    "tenant_id": "t-acme", "origen": "simulacion-de-fallo",
    "ocurrido_en": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "datos": {"proyecto_id": 1, "recurso_id": "no-es-un-id", "horas_semana": 10,
              "costo_hora": 30, "semanas": 2},
}))
PY
)

echo "1. Envio un evento malformado a ppm-cola-presupuestos-$STAGE"
echo "   recurso_id = \"no-es-un-id\"   evento_id = $EVENTO_ID"
aws sqs send-message --region $REGION --queue-url "$COLA" --message-body "$CUERPO" >/dev/null
INICIO=$(date +%s)

echo "2. El worker lo intenta, falla y SQS lo reintenta (3 intentos, cada 120 s)"
echo "   Logs: CloudWatch > /aws/lambda/ms-presupuestos-$STAGE-worker  (buscar 'ERROR mensaje')"
while :; do
  sleep 15
  t=$(( $(date +%s) - INICIO ))
  en_dlq=$(contar "$DLQ")
  printf '   %3ds  en cola: %s   en DLQ: %s\n' "$t" "$(contar "$COLA")" "$en_dlq"
  [ "$en_dlq" != "0" ] && break
  [ $t -gt 600 ] && { echo "   No llego a la DLQ en 10 min: revisa el trigger del worker."; exit 1; }
done

echo "3. El mensaje quedo apartado en la DLQ (no bloquea a los demas ni se pierde)."
echo "   Consola: SQS > ppm-cola-presupuestos-dlq-$STAGE > Send and receive messages > Poll"
echo "4. La alarma ppm-dlq-presupuestos-$STAGE pasa a ALARM en 1-2 min (CloudWatch > Alarms)."
echo
echo "Al terminar la demo: ./scripts/simular-fallo.sh --limpiar"
