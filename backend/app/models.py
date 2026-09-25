from datetime import datetime, timezone
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import relationship
from .database import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    name = Column(String(120), nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    password_hash = Column(String(512), nullable=False)
    language = Column(String(5), default='en', nullable=False)
    integration_token_hash = Column(String(128), nullable=True)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)

    policy = relationship('SecurityPolicy', back_populates='user', uselist=False, cascade='all, delete-orphan')


class SecurityPolicy(Base):
    __tablename__ = 'security_policies'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), unique=True, index=True, nullable=False)
    approval_threshold = Column(Integer, default=45, nullable=False)
    block_threshold = Column(Integer, default=75, nullable=False)
    llm_enabled = Column(Boolean, default=True, nullable=False)
    require_approval_for_sensitive_files = Column(Boolean, default=True, nullable=False)
    enabled_categories_json = Column(Text, default='[]', nullable=False)
    updated_at = Column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)

    user = relationship('User', back_populates='policy')


class SecurityScan(Base):
    __tablename__ = 'security_scans'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    source_type = Column(String(32), nullable=False)
    source_text = Column(Text, nullable=False)
    tool_name = Column(String(255), nullable=True)
    session_id = Column(String(255), nullable=True, index=True)
    decision = Column(String(32), nullable=False)
    risk_score = Column(Integer, nullable=False)
    threat_level = Column(String(32), nullable=False)
    findings_json = Column(Text, nullable=False)
    llm_used = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)


class ApprovalRequest(Base):
    __tablename__ = 'approval_requests'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    scan_id = Column(Integer, ForeignKey('security_scans.id', ondelete='CASCADE'), index=True, nullable=False)
    status = Column(String(32), default='pending', index=True, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
    decided_at = Column(DateTime(timezone=True), nullable=True)


class AuditLog(Base):
    __tablename__ = 'audit_logs'
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    event_type = Column(String(80), index=True, nullable=False)
    details_json = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), default=utcnow, nullable=False)
