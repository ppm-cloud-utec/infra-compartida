"""Pasos de plataforma de la maquina de estados `ppm-aprovisionar-tenant`.

Aqui viven los dos pasos que no pertenecen a ningun microservicio de negocio:
validar la peticion antes de tocar nada, y publicar la lista de tenants
vigentes cuando todo lo demas salio bien.

La lista en /ppm/tenants es la que leen ms-portafolios, ms-recursos y
ms-presupuestos para saber que schema pueden abrir. Se escribe AL FINAL a
proposito: hasta que las tres bases no esten listas, el tenant no debe poder
recibir trafico. Publicarla antes dejaria una ventana en la que el login
funciona y las consultas revientan.
"""
import json
import re

import boto3

PARAMETRO = "/ppm/tenants"
ORIGINALES = ["t-acme", "t-globex", "t-initech"]

_VALIDO = re.compile(r"^t-[a-z0-9]{2,30}$")


def _lista_actual(ssm):
    try:
        valor = ssm.get_parameter(Name=PARAMETRO)["Parameter"]["Value"]
        return json.loads(valor)
    except ssm.exceptions.ParameterNotFound:
        # Primera vez: la lista arranca con los tres que creo bases.sh.
        return list(ORIGINALES)


def validar(event, context):
    """Primer paso. Rechaza lo invalido ANTES de crear nada a medias."""
    tenant_id = (event.get("tenant_id") or "").strip().lower()
    nombre = (event.get("nombre") or "").strip()

    if not _VALIDO.match(tenant_id):
        raise ValueError(
            f"tenant_id invalido: {tenant_id!r}. Formato: t-<2 a 30 letras o digitos>, "
            "por ejemplo t-umbrella")
    if not nombre:
        raise ValueError("Falta 'nombre': es lo que vera el selector del login")

    ssm = boto3.client("ssm")
    if tenant_id in _lista_actual(ssm) and not event.get("forzar"):
        raise ValueError(
            f"{tenant_id} ya esta habilitado. Manda \"forzar\": true si de verdad "
            "quieres reaplicar el alta sobre una organizacion existente.")

    return {
        "tenant_id": tenant_id,
        "nombre": nombre,
        "rubro": (event.get("rubro") or "").strip(),
        "admin_email": (event.get("admin_email") or "").strip().lower() or None,
    }


def publicar(event, context):
    """Ultimo paso: habilita el tenant para los microservicios de RDS."""
    tenant_id = event["tenant_id"]
    ssm = boto3.client("ssm")

    lista = _lista_actual(ssm)
    if tenant_id not in lista:
        lista.append(tenant_id)

    ssm.put_parameter(
        Name=PARAMETRO, Value=json.dumps(sorted(lista)), Type="String",
        Overwrite=True,
        Description="Tenants habilitados. Lo escribe ppm-aprovisionar-tenant.",
    )
    # Las Lambdas de negocio lo releen solas cuando vence su cache (60s).
    return {"tenant_id": tenant_id, "habilitados": sorted(lista),
            "demora_propagacion_s": 60}


def retirar(event, context):
    """Compensacion de `publicar`: saca el tenant de la lista."""
    tenant_id = event["tenant_id"]
    if tenant_id in ORIGINALES:
        raise PermissionError(f"{tenant_id} es original: no se retira jamas")

    ssm = boto3.client("ssm")
    lista = [t for t in _lista_actual(ssm) if t != tenant_id]
    ssm.put_parameter(Name=PARAMETRO, Value=json.dumps(sorted(lista)),
                      Type="String", Overwrite=True)
    return {"tenant_id": tenant_id, "habilitados": sorted(lista)}
