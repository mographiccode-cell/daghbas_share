import os
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_DB = BASE_DIR / 'data' / 'agent_guard.db'
DEFAULT_DB.parent.mkdir(parents=True, exist_ok=True)
DATABASE_URL = os.getenv('AGENT_GUARD_DB_URL', f'sqlite:///{DEFAULT_DB.as_posix()}')

connect_args = {'check_same_thread': False} if DATABASE_URL.startswith('sqlite') else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
Base = declarative_base()
