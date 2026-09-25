from fastapi import Depends, Header, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from .auth import decode_access_token, hash_integration_token
from .database import SessionLocal
from .models import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl='/api/auth/login')


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        user_id = decode_access_token(token)
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid or expired token')
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='User not found')
    return user


def get_integration_user(
    x_agent_guard_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    if not x_agent_guard_token:
        raise HTTPException(status_code=401, detail='Missing integration token')
    digest = hash_integration_token(x_agent_guard_token)
    user = db.query(User).filter(User.integration_token_hash == digest).first()
    if not user:
        raise HTTPException(status_code=401, detail='Invalid integration token')
    return user
