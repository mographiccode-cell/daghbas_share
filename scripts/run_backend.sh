#!/usr/bin/env sh
cd "$(dirname "$0")/../backend"
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
