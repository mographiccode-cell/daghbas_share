#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y postgresql postgresql-contrib

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='daghbas'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE USER daghbas WITH PASSWORD 'daghbas';"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='daghbas_share'" | grep -q 1; then
  sudo -u postgres createdb -O daghbas daghbas_share
fi

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE daghbas_share TO daghbas;"

echo "تم إعداد PostgreSQL: user=daghbas db=daghbas_share"
