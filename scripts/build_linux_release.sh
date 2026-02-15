#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python -m pip install -r requirements.txt
python -m PyInstaller --noconfirm --onefile --windowed --name DaghbasShareClient desktop_client/main.py
python -m PyInstaller --noconfirm --onefile --name DaghbasShareServer server_entry.py

OUT_DIR="release/linux/${VERSION}"
mkdir -p "$OUT_DIR/config" "$OUT_DIR/docs"
cp dist/DaghbasShareClient "$OUT_DIR/"
cp dist/DaghbasShareServer "$OUT_DIR/"
cp .env.example "$OUT_DIR/config/.env.example"
cp README.md "$OUT_DIR/README.md"
cp docs/deployment_guide_ar.md "$OUT_DIR/docs/deployment_guide_ar.md"
cp scripts/install_linux_release.sh "$OUT_DIR/install.sh"
chmod +x "$OUT_DIR/install.sh"

tar -czf "release/DaghbasShare-linux-${VERSION}.tar.gz" -C "release/linux" "$VERSION"
echo "Linux release created: release/DaghbasShare-linux-${VERSION}.tar.gz"
