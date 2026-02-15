from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse

from .config import settings
from .database import Base, SessionLocal, engine
from .models import Role, User
from .routers import auth, files, folders, installations, logs, tasks, users
from .security import get_password_hash

app = FastAPI(title=settings.app_name, version=settings.app_version)


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        for role_name in ["Admin", "Manager", "Employee", "Read-Only"]:
            if not db.query(Role).filter(Role.name == role_name).first():
                db.add(Role(name=role_name))
        db.commit()

        admin = db.query(User).filter(User.username == "admin").first()
        if not admin:
            admin_role = db.query(Role).filter(Role.name == "Admin").first()
            db.add(
                User(
                    username="admin",
                    password_hash=get_password_hash("admin123"),
                    role_id=admin_role.id,
                )
            )
            db.commit()
    finally:
        db.close()


@app.get("/")
def root() -> dict:
    return {"message": f"{settings.app_name} is running"}


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "version": settings.app_version}


@app.get("/ui")
def web_ui() -> FileResponse:
    return FileResponse(Path(__file__).parent / "web" / "index.html")


app.include_router(auth.router)
app.include_router(users.router)
app.include_router(folders.router)
app.include_router(files.router)
app.include_router(tasks.router)
app.include_router(logs.router)
app.include_router(installations.router)
