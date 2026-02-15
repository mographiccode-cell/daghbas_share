#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/daghbas_share"
BIN_DIR="/usr/local/bin"

echo "Installing Daghbas Share to $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo cp DaghbasShareServer "$INSTALL_DIR/"
sudo cp DaghbasShareClient "$INSTALL_DIR/"
if [ -f "config/.env.example" ]; then
  sudo cp config/.env.example "$INSTALL_DIR/.env"
fi

sudo chmod +x "$INSTALL_DIR/DaghbasShareServer" "$INSTALL_DIR/DaghbasShareClient"

cat <<'SERVICE' | sudo tee /etc/systemd/system/daghbas-share.service >/dev/null
[Unit]
Description=Daghbas Share Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/daghbas_share
ExecStart=/opt/daghbas_share/DaghbasShareServer
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable daghbas-share
sudo systemctl restart daghbas-share

echo "Done. Server binary: $INSTALL_DIR/DaghbasShareServer"
echo "Client binary: $INSTALL_DIR/DaghbasShareClient"
echo "Service: systemctl status daghbas-share"
