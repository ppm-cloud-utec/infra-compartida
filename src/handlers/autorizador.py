"""Lambda Authorizer compartido por los 6 microservicios."""
import os
import re

import jwt

from src import secretos

def _secreto():
    return secretos.de_entorno("JWT_SECRET_NOMBRE")


def _recurso_comodin(method_arn):
    """Convierte el ARN del metodo invocado en un comodin para todo el API."""
    m = re.match(r"^(arn:aws:execute-api:[^:]+:\d+:[^/]+/[^/]+)/", method_arn)
    return f"{m.group(1)}/*/*" if m else method_arn


def _politica(principal, recurso, efecto, contexto=None):
    return {
        "principalId": principal,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": efecto,
                    "Resource": recurso,
                }
            ],
        },
        "context": contexto or {},
    }


def manejar(event, context):
    cabeceras = event.get("headers") or {}
    bruto = cabeceras.get("Authorization") or cabeceras.get("authorization") or ""
    token = bruto.removeprefix("Bearer ").removeprefix("bearer ").strip()

    if not token:
        raise Exception("Unauthorized")

    try:
        datos = jwt.decode(token, _secreto(), algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise Exception("Unauthorized")
    except jwt.PyJWTError:
        raise Exception("Unauthorized")

    if not datos.get("tenant_id") or not datos.get("sub"):
        raise Exception("Unauthorized")

    return _politica(
        principal=datos["sub"],
        recurso=_recurso_comodin(event["methodArn"]),
        efecto="Allow",
        contexto={
            "tenant_id": datos["tenant_id"],
            "usuario_id": datos["sub"],
            "rol": datos.get("rol", "miembro"),
            "email": datos.get("email", ""),
        },
    )
