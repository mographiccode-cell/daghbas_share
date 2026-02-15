from datetime import datetime
from pathlib import Path
import uuid

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import AuditLog, FileRecord, Folder, User

STORAGE_ROOT = Path("data/storage")
STORAGE_ROOT.mkdir(parents=True, exist_ok=True)

router = APIRouter(tags=["files"])


def _is_admin(user: User) -> bool:
    return bool(user.role and user.role.name == "Admin")


def _log(db: Session, user_id: int, action: str, target_type: str, target_id: str) -> None:
    db.add(AuditLog(user_id=user_id, action=action, target_type=target_type, target_id=target_id))


def _assert_can_edit(record: FileRecord, current: User) -> None:
    if _is_admin(current):
        return
    if record.is_locked and record.locked_by != current.id:
        raise HTTPException(status_code=409, detail="File locked by another user")


def _write_content_in_place(target_path: str, payload: bytes) -> None:
    path = Path(target_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


@router.post("/upload")
def upload_file(
    folder_id: int,
    incoming_file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    folder = db.query(Folder).filter(Folder.id == folder_id).first()
    if not folder:
        raise HTTPException(status_code=404, detail="Folder not found")

    content = incoming_file.file.read()
    existing = (
        db.query(FileRecord)
        .filter(FileRecord.folder_id == folder_id, FileRecord.original_name == incoming_file.filename)
        .first()
    )
    if existing:
        _assert_can_edit(existing, current)
        _write_content_in_place(existing.stored_name, content)
        existing.version += 1
        existing.size = len(content)
        existing.updated_at = datetime.utcnow()
        _log(db, current.id, "save_in_place", "file", str(existing.id))
        db.commit()
        return {
            "id": existing.id,
            "name": existing.original_name,
            "size": existing.size,
            "version": existing.version,
            "saved_in_place": True,
        }

    ext = Path(incoming_file.filename).suffix
    stored_name = f"{uuid.uuid4()}{ext}"
    year_dir = STORAGE_ROOT / str(datetime.utcnow().year)
    year_dir.mkdir(parents=True, exist_ok=True)
    target = year_dir / stored_name

    _write_content_in_place(str(target), content)

    record = FileRecord(
        folder_id=folder_id,
        stored_name=str(target),
        original_name=incoming_file.filename,
        version=1,
        size=len(content),
        created_by=current.id,
    )
    db.add(record)
    db.flush()
    _log(db, current.id, "upload", "file", str(record.id))
    db.commit()
    return {
        "id": record.id,
        "name": incoming_file.filename,
        "size": len(content),
        "version": record.version,
        "saved_in_place": False,
    }


@router.put("/files/{file_id}/save")
def save_file_in_place(
    file_id: int,
    incoming_file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    _assert_can_edit(record, current)

    content = incoming_file.file.read()
    _write_content_in_place(record.stored_name, content)
    record.size = len(content)
    record.version += 1
    record.updated_at = datetime.utcnow()
    _log(db, current.id, "save_in_place", "file", str(file_id))
    db.commit()

    return {
        "id": record.id,
        "name": record.original_name,
        "size": record.size,
        "version": record.version,
        "saved_in_place": True,
    }


@router.post("/files/{file_id}/move")
def move_file(
    file_id: int,
    target_folder_id: int,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    target_folder = db.query(Folder).filter(Folder.id == target_folder_id).first()
    if not target_folder:
        raise HTTPException(status_code=404, detail="Target folder not found")

    # الأدمن يمتلك صلاحية مطلقة للتحريك
    if not _is_admin(current):
        _assert_can_edit(record, current)

    record.folder_id = target_folder_id
    record.updated_at = datetime.utcnow()
    _log(db, current.id, "move", "file", str(file_id))
    db.commit()
    return {"message": "moved", "file_id": file_id, "target_folder_id": target_folder_id}


@router.delete("/files/{file_id}")
def delete_file(
    file_id: int,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")

    if not _is_admin(current):
        _assert_can_edit(record, current)

    path = Path(record.stored_name)
    if path.exists():
        path.unlink()
    db.delete(record)
    _log(db, current.id, "delete", "file", str(file_id))
    db.commit()
    return {"message": "deleted", "file_id": file_id}


@router.get("/download/{file_id}")
def download_file(
    file_id: int,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> FileResponse:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    _log(db, current.id, "download", "file", str(file_id))
    db.commit()
    return FileResponse(path=record.stored_name, filename=record.original_name)


@router.post("/lock/{file_id}")
def lock_file(
    file_id: int,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    if record.is_locked and record.locked_by != current.id and not _is_admin(current):
        raise HTTPException(status_code=409, detail="File locked by another user")

    record.is_locked = True
    record.locked_by = current.id
    _log(db, current.id, "lock", "file", str(file_id))
    db.commit()
    return {"message": "locked"}


@router.post("/unlock/{file_id}")
def unlock_file(
    file_id: int,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> dict:
    record = db.query(FileRecord).filter(FileRecord.id == file_id).first()
    if not record:
        raise HTTPException(status_code=404, detail="File not found")
    if record.locked_by not in (None, current.id) and not _is_admin(current):
        raise HTTPException(status_code=403, detail="Cannot unlock file locked by another user")

    record.is_locked = False
    record.locked_by = None
    _log(db, current.id, "unlock", "file", str(file_id))
    db.commit()
    return {"message": "unlocked"}
