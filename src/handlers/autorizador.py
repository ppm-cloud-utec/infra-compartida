"""Lambda Authorizer compartido por los 6 microservicios.

Valida la firma del JWT que emitio ms-identidad y entrega tenant_id, usuario_id,
rol y email a la Lambda destino por el requestContext. Ningun microservicio
llama a ms-identidad por HTTP: todos verifican la firma localmente con el mismo
JWT_SECRET.

Es un authorizer de tipo REQUEST sobre API Gateway REST (v1), asi que la
respuesta tiene que ser un documento de politica IAM. Devolver {"isAuthorized":
true} es el formato de HTTP API (v2) y aqui no funciona.
"""
import os
import re

import jwt

SECRETO = os.environ["JWT_SECRET"]


def _recurso_comodin(method_arn):
    """Convierte el ARN del metodo invocado en un comodin para todo el API.

    El resultado se cachea por token (resultTtlInSeconds), asi que si la
    politica apuntara solo al metodo llamado, la segunda ruta que use el mismo
    token recibiria un 403 del cache.

        arn:aws:execute-api:us-east-1:123:abc/dev/GET/usuarios
     -> arn:aws:execute-api:us-east-1:123:abc/dev/*/*
    """
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
        # Los valores del contexto solo pueden ser cadenas, numeros o booleanos:
        # API Gateway descarta en silencio cualquier objeto anidado.
        "context": contexto or {},
    }


def manejar(event, context):
    cabeceras = event.get("headers") or {}
    bruto = cabeceras.get("Authorization") or cabeceras.get("authorization") or ""
    token = bruto.removeprefix("Bearer ").removeprefix("bearer ").strip()

    # Levantar "Unauthorized" es lo que hace que API Gateway responda 401.
    # Devolver una politica Deny daria 403, que significa otra cosa.
    if not token:
        raise Exception("Unauthorized")

    try:
        datos = jwt.decode(token, SECRETO, algorithms=["HS256"])
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
