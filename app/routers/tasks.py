from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import AuditLog, Task, User
from ..schemas import TaskCreate, TaskOut, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.post("", response_model=TaskOut)
def create_task(
    payload: TaskCreate,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> TaskOut:
    task = Task(
        title=payload.title,
        description=payload.description,
        assigned_to=payload.assigned_to,
        due_date=payload.due_date,
    )
    db.add(task)
    db.flush()
    db.add(AuditLog(user_id=current.id, action="task_create", target_type="task", target_id=str(task.id)))
    db.commit()
    db.refresh(task)
    return TaskOut(**task.__dict__)


@router.patch("/{task_id}", response_model=TaskOut)
def update_task(
    task_id: int,
    payload: TaskUpdate,
    db: Session = Depends(get_db),
    current: User = Depends(get_current_user),
) -> TaskOut:
    task = db.query(Task).filter(Task.id == task_id).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    task.status = payload.status
    db.add(AuditLog(user_id=current.id, action="task_update", target_type="task", target_id=str(task.id)))
    db.commit()
    db.refresh(task)
    return TaskOut(**task.__dict__)


@router.get("/my", response_model=list[TaskOut])
def my_tasks(db: Session = Depends(get_db), current: User = Depends(get_current_user)) -> list[TaskOut]:
    tasks = db.query(Task).filter(Task.assigned_to == current.id).all()
    return [TaskOut(**t.__dict__) for t in tasks]
