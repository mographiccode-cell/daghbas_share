from datetime import datetime, timedelta, timezone
from jose import jwt
from passlib.context import CryptContext

from .config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def create_token(subject: str, token_type: str = "access") -> str:
    now = datetime.now(timezone.utc)
    exp = now + (
        timedelta(minutes=settings.access_expire_min)
        if token_type == "access"
        else timedelta(days=settings.refresh_expire_days)
    )
    payload = {"sub": subject, "type": token_type, "iat": now, "exp": exp}
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def create_license_token(device_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "device_id": device_id,
        "iat": now,
        "exp": now + timedelta(days=3650),
    }
    return jwt.encode(payload, settings.license_secret, algorithm=settings.algorithm)


def verify_license_token(token: str) -> dict:
    return jwt.decode(token, settings.license_secret, algorithms=[settings.algorithm])
