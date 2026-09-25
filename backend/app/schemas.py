from typing import Any
from pydantic import BaseModel, EmailStr, Field


class SignupIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    language: str = 'en'


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class ScanIn(BaseModel):
    source_type: str = 'prompt'
    source_text: str = Field(min_length=1, max_length=200000)
    tool_name: str | None = None
    session_id: str | None = None


class PolicyIn(BaseModel):
    approval_threshold: int = Field(ge=1, le=99)
    block_threshold: int = Field(ge=2, le=100)
    llm_enabled: bool = True
    require_approval_for_sensitive_files: bool = True
    enabled_categories: list[str] = []


class CodexPromptIn(BaseModel):
    session_id: str | None = None
    turn_id: str | None = None
    prompt: str
    model: str | None = None
    cwd: str | None = None


class CodexToolIn(BaseModel):
    session_id: str | None = None
    turn_id: str | None = None
    tool_name: str
    tool_input: Any = None
    model: str | None = None
    cwd: str | None = None
