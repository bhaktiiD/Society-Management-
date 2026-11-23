
import logging
import os
import jwt

from jwt import PyJWKClient
from dotenv import load_dotenv
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

backend_dir = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(backend_dir, ".env"))

log = logging.getLogger("societyos.auth")
security = HTTPBearer()

SUPABASE_URL = "https://tdzajtscinvnbcdthszg.supabase.co"

JWKS_URL = f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json"

ISSUER = f"{SUPABASE_URL}/auth/v1"

jwks_client = PyJWKClient(JWKS_URL)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    token = credentials.credentials

    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)

        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256"],
            audience="authenticated",
            issuer=ISSUER,
            options={"require": ["exp", "sub"]},
        )

        return payload

    except jwt.ExpiredSignatureError as error:
        log.info("JWT expired")
        raise HTTPException(
            status_code=401,
            detail="Authentication token has expired"
        )

    except jwt.InvalidTokenError as error:
        log.warning("JWT invalid: %s", type(error).__name__)
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication token"
        )

    except Exception as error:
        log.error("JWT verification unavailable: %s", type(error).__name__)
        raise HTTPException(
            status_code=503,
            detail="Authentication verification temporarily unavailable"
        )