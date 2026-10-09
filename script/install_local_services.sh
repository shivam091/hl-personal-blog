#!/usr/bin/env bash
# One-time local dev setup for Ubuntu 22.04 (jammy): installs MongoDB 8.0
# (server, mongosh, and the mongodump/mongorestore tools). The test suite
# runs against this local mongod; development uses Atlas via MONGODB_URI.

set -euo pipefail

echo "== Installing MongoDB 8.0 =="
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" \
  | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl enable --now mongod

echo "== Done. Verify with: =="
echo "  mongosh --eval 'db.version()'"
