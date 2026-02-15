from fastapi import APIRouter, Header, HTTPException
from jose import JWTError
from sqlalchemy.orm import Session

from ..config import settings
from ..database import SessionLocal
from ..models import Installation
from ..schemas import (
    ActivationRequest,
    ActivationResponse,
    LicenseValidateRequest,
    LicenseValidateResponse,
)
from ..security import create_license_token, verify_license_token

router = APIRouter(prefix="/installations", tags=["installations"])


@router.post("/activate", response_model=ActivationResponse)
def activate_installation(
    payload: ActivationRequest,
    x_master_key: str = Header(default=""),
) -> ActivationResponse:
    if x_master_key != settings.installation_master_key:
        raise HTTPException(status_code=403, detail="Invalid master key")

    db: Session = SessionLocal()
    try:
        existing = db.query(Installation).filter(Installation.device_id == payload.device_id).first()
        if existing and existing.is_active:
            return ActivationResponse(device_id=existing.device_id, license_token=existing.license_token)

        token = create_license_token(payload.device_id)
        if existing:
            existing.customer_name = payload.customer_name
            existing.license_token = token
            existing.is_active = True
            db.commit()
            return ActivationResponse(device_id=existing.device_id, license_token=existing.license_token)

        install = Installation(
            device_id=payload.device_id,
            customer_name=payload.customer_name,
            license_token=token,
            is_active=True,
        )
        db.add(install)
        db.commit()
        return ActivationResponse(device_id=install.device_id, license_token=install.license_token)
    finally:
        db.close()


@router.post("/validate", response_model=LicenseValidateResponse)
def validate_license(payload: LicenseValidateRequest) -> LicenseValidateResponse:
    db: Session = SessionLocal()
    try:
        installation = db.query(Installation).filter(Installation.device_id == payload.device_id).first()
        if not installation or not installation.is_active:
            return LicenseValidateResponse(valid=False, message="Device is not activated")
        if installation.license_token != payload.license_token:
            return LicenseValidateResponse(valid=False, message="License token mismatch")

        try:
            decoded = verify_license_token(payload.license_token)
        except JWTError:
            return LicenseValidateResponse(valid=False, message="Invalid license token")

        if decoded.get("device_id") != payload.device_id:
            return LicenseValidateResponse(valid=False, message="Token is not bound to this device")

        return LicenseValidateResponse(valid=True, message="License is valid")
    finally:
        db.close()
