from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import require_roles
from ..models import Role, User
from ..schemas import UserCreate, UserOut
from ..security import get_password_hash

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(
    db: Session = Depends(get_db),
    _: User = Depends(require_roles("Admin", "Manager")),
) -> list[UserOut]:
    users = db.query(User).join(Role).all()
    return [UserOut(id=u.id, username=u.username, role=u.role.name) for u in users]


@router.post("", response_model=UserOut)
def create_user(
    payload: UserCreate,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles("Admin")),
) -> UserOut:
    exists = db.query(User).filter(User.username == payload.username).first()
    if exists:
        raise HTTPException(status_code=409, detail="Username already exists")

    role = db.query(Role).filter(Role.name == payload.role).first()
    if not role:
        raise HTTPException(status_code=404, detail="Role not found")

    user = User(
        username=payload.username,
        password_hash=get_password_hash(payload.password),
        role_id=role.id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return UserOut(id=user.id, username=user.username, role=role.name)


@router.patch("/{user_id}")
def update_user_status(
    user_id: int,
    is_active: bool,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles("Admin")),
) -> dict:
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = is_active
    db.commit()
    return {"message": "updated"}
