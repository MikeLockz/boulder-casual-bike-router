#!/bin/bash
# Exit on any error
set -e

PROJECT_DIR="/opt/boulder-casual-bike-router"
DOCKER_DIR="/root/lockdev-home"

echo "📥 Fetching latest changes from GitHub..."
cd "$PROJECT_DIR"
# Clear any local changes on the server to prevent pull conflicts
git reset --hard
git pull

echo "🏗️ Rebuilding and restarting containers..."
cd "$DOCKER_DIR"
docker compose up -d --build boulder-backend boulder-frontend

echo "✅ Update complete!"
