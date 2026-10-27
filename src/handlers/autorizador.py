"""Lambda Authorizer compartido por los 6 microservicios.

Valida la firma del JWT que emitio ms-identidad y entrega tenant_id, usuario_id
y rol a la Lambda destino. Ningun microservicio llama a ms-identidad por HTTP:
todos verifican la firma localmente con el mismo JWT_SECRET.
"""
import os

import jwt

SECRETO = os.environ["JWT_SECRET"]


def manejar(event, context):
    token = (event.get("headers", {}) or {}).get("authorization") or \
            (event.get("headers", {}) or {}).get("Authorization") or ""
    token = token.removeprefix("Bearer ").strip()

    if not token:
        raise Exception("Unauthorized")  # API Gateway lo traduce a 401

    try:
        datos = jwt.decode(token, SECRETO, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise Exception("Unauthorized")

    if not datos.get("tenant_id"):
        raise Exception("Unauthorized")

    return {
        "isAuthorized": True,
        "principalId": datos["sub"],
        "context": {
            "tenant_id": datos["tenant_id"],
            "usuario_id": datos["sub"],
            "rol": datos.get("rol", "miembro"),
        },
    }
