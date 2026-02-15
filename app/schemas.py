from datetime import datetime
from pydantic import BaseModel


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    username: str
    password: str
    device_id: str = "desktop"


class RefreshRequest(BaseModel):
    refresh_token: str


class UserCreate(BaseModel):
    username: str
    password: str
    role: str = "Employee"


class UserOut(BaseModel):
    id: int
    username: str
    role: str


class FolderCreate(BaseModel):
    name: str
    parent_id: int | None = None


class FolderOut(BaseModel):
    id: int
    name: str
    parent_id: int | None


class TaskCreate(BaseModel):
    title: str
    description: str = ""
    assigned_to: int
    due_date: str | None = None


class TaskUpdate(BaseModel):
    status: str


class TaskOut(BaseModel):
    id: int
    title: str
    description: str
    assigned_to: int
    status: str
    due_date: str | None


class LogOut(BaseModel):
    id: int
    user_id: int
    action: str
    target_type: str
    target_id: str
    timestamp: datetime


class ActivationRequest(BaseModel):
    device_id: str
    customer_name: str


class ActivationResponse(BaseModel):
    device_id: str
    license_token: str
    status: str = "active"


class LicenseValidateRequest(BaseModel):
    device_id: str
    license_token: str


class LicenseValidateResponse(BaseModel):
    valid: bool
    message: str
