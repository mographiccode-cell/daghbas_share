import hashlib
import os
import secrets
from pathlib import Path
from datetime import datetime, timedelta, timezone
import jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

def _jwt_secret() -> str:
    configured = os.getenv('JWT_SECRET')
    if configured:
        return configured
    secret_file = Path(__file__).resolve().parents[2] / 'data' / '.jwt_secret'
    secret_file.parent.mkdir(parents=True, exist_ok=True)
    if secret_file.exists():
        return secret_file.read_text(encoding='utf-8').strip()
    generated = secrets.token_urlsafe(48)
    secret_file.write_text(generated, encoding='utf-8')
    return generated

JWT_SECRET = _jwt_secret()
JWT_ALGORITHM = 'HS256'
JWT_EXPIRE_MINUTES = int(os.getenv('JWT_EXPIRE_MINUTES', '1440'))
_ph = PasswordHasher()


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except VerifyMismatchError:
        return False


def create_access_token(user_id: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        'sub': str(user_id),
        'iat': int(now.timestamp()),
        'exp': int((now + timedelta(minutes=JWT_EXPIRE_MINUTES)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> int:
    payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    return int(payload['sub'])


def generate_integration_token() -> str:
    return 'ag_' + secrets.token_urlsafe(32)


def hash_integration_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()
