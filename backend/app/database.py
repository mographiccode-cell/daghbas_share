import os
from pathlib import Path
from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

BASE_DIR = Path(__file__).resolve().parents[2]
DEFAULT_DB = BASE_DIR / 'data' / 'agent_guard.db'
DEFAULT_DB.parent.mkdir(parents=True, exist_ok=True)
DATABASE_URL = os.getenv('AGENT_GUARD_DB_URL', f'sqlite:///{DEFAULT_DB.as_posix()}')

connect_args = {'check_same_thread': False} if DATABASE_URL.startswith('sqlite') else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args, future=True)

if DATABASE_URL.startswith('sqlite'):
    @event.listens_for(engine, 'connect')
    def _set_sqlite_pragma(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute('PRAGMA foreign_keys=ON')
        cursor.close()

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)
Base = declarative_base()


def ensure_sqlite_schema():
    """Small additive migration layer for the academic SQLite release.

    SQLAlchemy create_all creates new tables but does not add new columns to
    existing tables. These ALTERs keep older local databases usable.
    """
    if not DATABASE_URL.startswith('sqlite'):
        return
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    additions = {
        'security_policies': {
            'blocked_domains_json': "TEXT NOT NULL DEFAULT '[]'",
            'blocked_tools_json': "TEXT NOT NULL DEFAULT '[]'",
            'approval_tools_json': "TEXT NOT NULL DEFAULT '[]'",
        },
        'security_scans': {
            'project_id': 'INTEGER NULL',
        },
    }
    with engine.begin() as conn:
        for table, wanted in additions.items():
            if table not in tables:
                continue
            existing = {c['name'] for c in inspect(engine).get_columns(table)}
            for column, ddl in wanted.items():
                if column not in existing:
                    conn.execute(text(f'ALTER TABLE {table} ADD COLUMN {column} {ddl}'))
