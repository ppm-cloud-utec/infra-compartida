#!/usr/bin/env bash
#
# Verificacion de extremo a extremo del SaaS PPM completo.
#
#   ./verificar-sistema.sh [stage]
#
# Descubre las URLs de los 6 microservicios por CloudFormation, entra con dos
# tenants y comprueba los tres pilares que exige el enunciado:
#
#   multi-tenancy  -> un tenant no ve los datos del otro
#   serverless     -> los 6 responden detras de API Gateway
#   EDA            -> completar una tarea cambia el avance sin llamar a nadie mas
#
# ES LO QUE SE CORRE EN VIVO EN LA EXPOSICION.
set -uo pipefail

STAGE=${1:-dev}
REGION=${AWS_REGION:-us-east-1}
PASS=${PASSWORD_DEMO:-Demo1234}

ok=0; fallo=0; omitido=0
verde()   { printf '  \033[32m  OK\033[0m  %s\n' "$1"; ok=$((ok+1)); }
rojo()    { printf '  \033[31mFALLO\033[0m  %s\n' "$1"; fallo=$((fallo+1)); }
gris()    { printf '  \033[90mOMIT\033[0m  %s\n' "$1"; omitido=$((omitido+1)); }
titulo()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
codigo()  { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }
# Extrae un valor del JSON por una ruta con puntos: json datos.token
# No usa eval: la version anterior generaba eval('d['datos']['token']') y las
# comillas simples chocaban, asi que SIEMPRE devolvia vacio y el script
# reportaba fallos que no existian.
json() {
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].split("."):
    if d is None:
        break
    d = d[int(k)] if k.lstrip("-").isdigit() else d.get(k)
print("" if d is None else d)
' "$1" 2>/dev/null
}

# ---------------------------------------------------------------- descubrir
titulo "0. Descubriendo los microservicios desplegados"

declare -A URL
for s in identidad portafolios tareas recursos presupuestos analitico; do
  u=$(aws cloudformation describe-stacks --region "$REGION" \
        --stack-name "ms-$s-$STAGE" \
        --query "Stacks[0].Outputs[?OutputKey=='ServiceEndpoint'].OutputValue" \
        --output text 2>/dev/null)
  if [ -n "$u" ] && [ "$u" != "None" ]; then
    URL[$s]=$u
    verde "ms-$s  $u"
  else
    rojo "ms-$s no esta desplegado (no existe el stack ms-$s-$STAGE)"
  fi
done

[ -z "${URL[identidad]:-}" ] && {
  printf '\nSin ms-identidad no hay tokens y no se puede verificar nada mas.\n'
  exit 1
}

# ------------------------------------------------------------------- login
titulo "1. Login en dos tenants (la demo usa estos dos)"

entrar() {
  curl -s --max-time 20 -X POST "${URL[identidad]}/login" \
    -H 'Content-Type: application/json' \
    -d "{\"tenant_id\":\"$1\",\"email\":\"$2\",\"password\":\"$PASS\"}"
}

TOK_A=$(entrar t-acme   admin@acme.com.pe | json datos.token)
TOK_G=$(entrar t-globex admin@globex.com  | json datos.token)

[ -n "$TOK_A" ] && verde "Acme devuelve token"   || rojo "Acme no devolvio token"
[ -n "$TOK_G" ] && verde "Globex devuelve token" || rojo "Globex no devolvio token"
[ -z "$TOK_A" ] && { printf '\nSin token no se puede seguir.\n'; exit 1; }

cA=(-H "Authorization: Bearer $TOK_A")
cG=(-H "Authorization: Bearer $TOK_G")

# El tenant_id viaja DENTRO del token, no en la URL ni en el body
for par in "identidad:t-acme:A" "identidad:t-globex:G"; do
  IFS=: read -r s esperado tok <<< "$par"
  t=$([ "$tok" = A ] && curl -s "${URL[$s]}/health" "${cA[@]}" || curl -s "${URL[$s]}/health" "${cG[@]}")
  real=$(echo "$t" | json datos.tenant)
  [ "$real" = "$esperado" ] && verde "el token se resuelve a $esperado" \
    || rojo "el token se resuelve a '$real', se esperaba $esperado"
done

# ------------------------------------------------- endpoints protegidos
titulo "2. Los 6 microservicios rechazan peticiones sin token"

for s in "${!URL[@]}"; do
  c=$(codigo "${URL[$s]}/health")
  [ "$c" = 401 ] && verde "ms-$s sin token -> 401" || rojo "ms-$s sin token -> $c (se esperaba 401)"
done
c=$(codigo -H "Authorization: Bearer token.falso.aqui" "${URL[identidad]}/health")
[ "$c" = 401 ] && verde "token invalido -> 401" || rojo "token invalido -> $c"

titulo "3. Los 6 responden con token valido"
for s in "${!URL[@]}"; do
  c=$(codigo "${URL[$s]}/health" "${cA[@]}")
  [ "$c" = 200 ] && verde "ms-$s con token -> 200" || rojo "ms-$s con token -> $c"
done

# --------------------------------------------------------- multi-tenancy
titulo "4. AISLAMIENTO: cada tenant solo ve lo suyo"

if [ -n "${URL[portafolios]:-}" ]; then
  nA=$(curl -s "${URL[portafolios]}/proyectos?limite=1" "${cA[@]}" | json meta.total)
  nG=$(curl -s "${URL[portafolios]}/proyectos?limite=1" "${cG[@]}" | json meta.total)
  verde "Acme ve $nA proyectos · Globex ve $nG proyectos"

  pA=$(curl -s "${URL[portafolios]}/proyectos?limite=1" "${cA[@]}" | json datos.0.codigo)
  pG=$(curl -s "${URL[portafolios]}/proyectos?limite=1" "${cG[@]}" | json datos.0.codigo)
  [ -n "$pA" ] && [ "$pA" != "$pG" ] \
    && verde "los codigos difieren: Acme '$pA' vs Globex '$pG'" \
    || rojo "los dos tenants devuelven el mismo proyecto: '$pA'"
else
  gris "ms-portafolios no desplegado: no se puede verificar el aislamiento de datos"
fi

# El usuario admin de Acme NO existe en la particion de Globex
c=$(codigo "${URL[identidad]}/usuarios/admin@acme.com.pe" "${cG[@]}")
[ "$c" = 404 ] && verde "Globex pidiendo un usuario de Acme -> 404 (no existe para el)" \
  || rojo "Globex pidiendo un usuario de Acme -> $c (se esperaba 404)"
c=$(codigo "${URL[identidad]}/usuarios/admin@acme.com.pe" "${cA[@]}")
[ "$c" = 200 ] && verde "Acme pidiendo su propio usuario -> 200" || rojo "Acme pidiendo lo suyo -> $c"

# ------------------------------------------------------------------- EDA
titulo "5. EDA: completar una tarea recalcula el avance sin llamar a nadie mas"

if [ -n "${URL[tareas]:-}" ] && [ -n "${URL[portafolios]:-}" ]; then
  # Un proyecto en curso con tareas pendientes
  PID=$(curl -s "${URL[portafolios]}/proyectos?estado=en_curso&limite=1" "${cA[@]}" | json datos.0.id)
  if [ -n "$PID" ]; then
    ANTES=$(curl -s "${URL[portafolios]}/proyectos/$PID" "${cA[@]}" | json datos.avance_pct)
    TID=$(curl -s "${URL[tareas]}/proyectos/$PID/tareas?estado=pendiente&limite=1" "${cA[@]}" | json datos.0.tarea_id)

    if [ -n "$TID" ]; then
      r=$(curl -s -X POST "${URL[tareas]}/proyectos/$PID/tareas/$TID/completar" "${cA[@]}")
      nuevo=$(echo "$r" | json datos.proyecto.avance_pct)
      verde "tarea completada · ms-tareas dice que el avance es $nuevo%"

      printf '         esperando a que el worker procese el evento'
      for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2; printf '.'
        DESPUES=$(curl -s "${URL[portafolios]}/proyectos/$PID" "${cA[@]}" | json datos.avance_pct)
        [ "$DESPUES" != "$ANTES" ] && break
      done
      printf '\n'

      if [ "$DESPUES" != "$ANTES" ]; then
        verde "ms-portafolios paso de $ANTES% a $DESPUES% SIN que nadie se lo pidiera"
        verde "   (SNS -> SQS -> worker, con el frontend fuera del circuito)"
      else
        rojo "el avance sigue en $ANTES% tras 20s: revisa la cola ppm-cola-portafolios-$STAGE y su DLQ"
      fi
    else
      gris "el proyecto $PID no tiene tareas pendientes"
    fi
  else
    gris "no hay proyectos en curso en Acme"
  fi
else
  gris "faltan ms-tareas o ms-portafolios: no se puede verificar el flujo de eventos"
fi

# ------------------------------------------------------------- data lake
titulo "6. El data lake recibe los eventos"

if [ -n "${URL[analitico]:-}" ]; then
  hoy=$(date -u +%F)
  n=$(curl -s "${URL[analitico]}/eventos?fecha=$hoy&limite=5" "${cA[@]}" | json meta.total)
  [ -n "$n" ] && [ "$n" != "0" ] \
    && verde "hay $n objetos escritos hoy en S3 para Acme" \
    || gris "aun no hay objetos de hoy en S3 (si el worker acaba de correr, espera un momento)"
  ev=$(curl -s "${URL[analitico]}/kpis" "${cA[@]}" | json datos.eventos_procesados)
  [ -n "$ev" ] && verde "agregados: $ev eventos procesados en total"
else
  gris "ms-analitico no desplegado"
fi

# ----------------------------------------------------------------- colas
titulo "7. Colas SQS y sus DLQ"

for c in portafolios presupuestos analitico alertas; do
  u=$(aws sqs get-queue-url --region "$REGION" --queue-name "ppm-cola-$c-$STAGE" \
        --query QueueUrl --output text 2>/dev/null)
  if [ -n "$u" ] && [ "$u" != "None" ]; then
    pend=$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$u" \
             --attribute-names ApproximateNumberOfMessages \
             --query 'Attributes.ApproximateNumberOfMessages' --output text 2>/dev/null)
    d=$(aws sqs get-queue-url --region "$REGION" --queue-name "ppm-cola-$c-dlq-$STAGE" \
          --query QueueUrl --output text 2>/dev/null)
    muertos=$(aws sqs get-queue-attributes --region "$REGION" --queue-url "$d" \
                --attribute-names ApproximateNumberOfMessages \
                --query 'Attributes.ApproximateNumberOfMessages' --output text 2>/dev/null)
    if [ "${muertos:-0}" != "0" ]; then
      rojo "cola-$c: $pend pendientes · \033[31m$muertos EN LA DLQ\033[0m"
    else
      verde "cola-$c: $pend pendientes · DLQ vacia"
    fi
  else
    gris "cola-$c-$STAGE no existe"
  fi
done

# --------------------------------------------------------------- resumen
printf '\n\033[1m%s\033[0m\n' "RESULTADO"
printf '  %d correctas · %d fallidas · %d omitidas\n' "$ok" "$fallo" "$omitido"
[ "$fallo" -eq 0 ] && printf '\n  \033[32mEl sistema cumple los tres pilares: multi-tenancy, serverless y EDA.\033[0m\n\n' \
                   || printf '\n  \033[31mHay %d verificaciones fallidas.\033[0m\n\n' "$fallo"
exit $([ "$fallo" -eq 0 ] && echo 0 || echo 1)
