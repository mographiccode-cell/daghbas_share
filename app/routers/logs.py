from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import require_roles
from ..models import AuditLog, User
from ..schemas import LogOut

router = APIRouter(prefix="/logs", tags=["logs"])


@router.get("", response_model=list[LogOut])
def get_logs(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles("Admin", "Manager")),
) -> list[LogOut]:
    rows = db.query(AuditLog).order_by(AuditLog.timestamp.desc()).limit(500).all()
    return [LogOut(**r.__dict__) for r in rows]
