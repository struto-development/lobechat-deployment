#!/bin/bash

# LobeChat Restore Script
# Restores from backup archive

set -e

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo "Example: $0 /backups/lobechat/lobechat_backup_20241029_120000.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="/tmp/lobechat_restore_$$"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verify backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo -e "${RED}Error: Backup file not found: ${BACKUP_FILE}${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will restore data from backup and may overwrite current data!${NC}"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

echo -e "${GREEN}Starting LobeChat Restore${NC}"
echo "Backup file: ${BACKUP_FILE}"

# Create temporary restore directory
mkdir -p "${RESTORE_DIR}"

# Extract backup
echo "Extracting backup..."
tar -xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"
echo "✓ Backup extracted"

# Stop services
echo "Stopping services..."
docker compose stop
echo "✓ Services stopped"

# Restore PostgreSQL databases
echo "Restoring PostgreSQL databases..."
docker compose up -d postgresql
sleep 10

# Drop and recreate databases
docker exec lobe-postgres psql -U postgres -c "DROP DATABASE IF EXISTS lobe;"
docker exec lobe-postgres psql -U postgres -c "CREATE DATABASE lobe;"
docker exec lobe-postgres psql -U postgres -c "DROP DATABASE IF EXISTS casdoor;"
docker exec lobe-postgres psql -U postgres -c "CREATE DATABASE casdoor;"

# Restore data
docker exec -i lobe-postgres psql -U postgres -d lobe < "${RESTORE_DIR}/lobe_"*.sql
docker exec -i lobe-postgres psql -U postgres -d casdoor < "${RESTORE_DIR}/casdoor_"*.sql
echo "✓ Databases restored"

# Restore MinIO data
echo "Restoring MinIO storage..."
docker compose up -d minio
sleep 10

# Clear existing buckets
docker exec lobe-minio mc rm -r --force myminio/lobe 2>/dev/null || true
docker exec lobe-minio mc rm -r --force myminio/casdoor 2>/dev/null || true

# Recreate buckets
docker exec lobe-minio mc mb myminio/lobe 2>/dev/null || true
docker exec lobe-minio mc mb myminio/casdoor 2>/dev/null || true

# Copy data back
if [ -d "${RESTORE_DIR}/minio_"*/lobe ]; then
    docker exec lobe-minio mc cp -r "${RESTORE_DIR}/minio_"*/lobe/* myminio/lobe/
fi
if [ -d "${RESTORE_DIR}/minio_"*/casdoor ]; then
    docker exec lobe-minio mc cp -r "${RESTORE_DIR}/minio_"*/casdoor/* myminio/casdoor/
fi
echo "✓ Storage restored"

# Restore configuration (optional)
echo -e "${YELLOW}Do you want to restore configuration files? (yes/no):${NC}"
read -p "" RESTORE_CONFIG

if [ "${RESTORE_CONFIG}" == "yes" ]; then
    echo "Creating configuration backup..."
    cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

    echo "Restoring configuration..."
    tar -xzf "${RESTORE_DIR}/config_"*.tar.gz -C .
    echo "✓ Configuration restored (old .env backed up)"
fi

# Start all services
echo "Starting all services..."
docker compose up -d
echo "✓ All services started"

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "${RESTORE_DIR}"

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# Verify services
docker compose ps

echo ""
echo -e "${GREEN}Restore Complete!${NC}"
echo "All services have been restored and restarted."
echo "Please verify that everything is working correctly."