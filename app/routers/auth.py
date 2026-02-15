from fastapi import APIRouter, Depends, HTTPException
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import User
from ..schemas import LoginRequest, RefreshRequest, Token
from ..security import create_token, verify_password

router = APIRouter(tags=["auth"])


@router.post("/login", response_model=Token)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> Token:
    user = db.query(User).filter(User.username == payload.username, User.is_active.is_(True)).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    user.device_id = payload.device_id
    db.commit()
    return Token(
        access_token=create_token(user.username, token_type="access"),
        refresh_token=create_token(user.username, token_type="refresh"),
    )


@router.post("/refresh", response_model=Token)
def refresh(payload: RefreshRequest) -> Token:
    try:
        decoded = jwt.decode(payload.refresh_token, settings.secret_key, algorithms=[settings.algorithm])
        if decoded.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid refresh token type")
        subject = decoded.get("sub")
        if not subject:
            raise HTTPException(status_code=401, detail="Invalid refresh token")
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid refresh token") from exc

    return Token(
        access_token=create_token(subject, token_type="access"),
        refresh_token=create_token(subject, token_type="refresh"),
    )


@router.post("/logout")
def logout() -> dict:
    return {"message": "Logged out"}
