from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import Folder, User
from ..schemas import FolderCreate, FolderOut

router = APIRouter(prefix="/folders", tags=["folders"])


@router.get("", response_model=list[FolderOut])
def get_folders(db: Session = Depends(get_db), _: User = Depends(get_current_user)) -> list[FolderOut]:
    rows = db.query(Folder).all()
    return [FolderOut(id=r.id, name=r.name, parent_id=r.parent_id) for r in rows]


@router.post("", response_model=FolderOut)
def create_folder(
    payload: FolderCreate,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> FolderOut:
    if payload.parent_id:
        parent = db.query(Folder).filter(Folder.id == payload.parent_id).first()
        if not parent:
            raise HTTPException(status_code=404, detail="Parent folder not found")

    row = Folder(name=payload.name, parent_id=payload.parent_id, created_by=current.id)
    db.add(row)
    db.commit()
    db.refresh(row)
    return FolderOut(id=row.id, name=row.name, parent_id=row.parent_id)


@router.delete("/{folder_id}")
def delete_folder(
    folder_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> dict:
    row = db.query(Folder).filter(Folder.id == folder_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Folder not found")
    db.delete(row)
    db.commit()
    return {"message": "deleted"}
